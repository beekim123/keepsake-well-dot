class_name PolicyBot
extends RefCounted
## A transparent legal-action heuristic, not a claim about human enjoyment.
## All consequences come from BattleRules; this policy cannot award itself wins.
var _definitions: Dictionary = {}

func _init(definitions: Dictionary = {}) -> void:
	_definitions = definitions.duplicate(true)

func choose_action(state: Dictionary, rules: RefCounted, strategy: String = "defensive") -> Dictionary:
	var actions: Array = rules.legal_actions(state)
	if actions.is_empty():
		return {}
	var best: Dictionary = {"type": "end_turn", "keep_index": -1}
	var best_score: float = 0.0
	var before: Dictionary = rules.forecast(state)
	var played: int = int(state.get("turn_flags", {}).get("cards_played", 0))
	# A policy-only loop escape for pathological zero-cost draw cycles. The game
	# itself has no action/turn cap and this never changes victory conditions.
	var search_cards: bool = played < 40
	for action: Dictionary in actions:
		if action["type"] == "end_turn":
			if int(action.get("keep_index", -1)) >= 0:
				var card: Dictionary = rules.definition("cards", state["hand"][action["keep_index"]]["id"])
				var retention_score: float = 0.01 * (1.0 + int(card.get("cost", 0)))
				if retention_score > best_score:
					best_score = retention_score
					best = action
			continue
		if not search_cards:
			continue
		var prediction: Dictionary = rules.preview(state, action["hand_index"], action["target_index"], action["choices"])
		if not prediction["valid"]:
			continue
		var next: Dictionary = prediction["state"]
		var score: float = _score(state, next, before, prediction["forecast_after"], rules, strategy)
		if score > best_score:
			best_score = score
			best = action
	return best.duplicate(true)

func _score(before_state: Dictionary, after_state: Dictionary, before: Dictionary, after: Dictionary, rules: RefCounted, strategy: String) -> float:
	if after_state["status"] == "victory":
		return 100000.0
	if after_state["status"] == "defeat":
		return -100000.0
	var dealt: int = 0
	var guard_damage: int = 0
	var defeated: int = 0
	for index: int in range(before_state["enemies"].size()):
		var old: Dictionary = before_state["enemies"][index]
		var new: Dictionary = after_state["enemies"][index]
		dealt += int(old["hp"]) - int(new["hp"])
		guard_damage += int(old["guard"]) - int(new["guard"])
		if int(old["hp"]) > 0 and int(new["hp"]) == 0:
			defeated += 1
	var defense_weight: float = 1.5 if strategy == "defensive" else 0.8
	if int(before["hp_after"]) <= 0:
		defense_weight += 5.0
	var score: float = dealt + guard_damage * 0.25 + defeated * 3.0
	score += (int(before["damage"]) - int(after["damage"])) * defense_weight
	score += (int(after_state["player"]["hp"]) - int(before_state["player"]["hp"])) * 1.3
	score += (int(after_state["energy"]) - int(before_state["energy"])) * 0.35
	score += (int(after_state["next_turn_energy"]) - int(before_state["next_turn_energy"])) * 1.1
	# Draw is useful when it reveals playable cards; hand count alone must not
	# prefer infinite 0-cost redraw loops over ending the turn.
	var draw_value: float = 0.0
	for instance: Dictionary in after_state["hand"]:
		if rules.find_card(before_state["hand"], instance["uid"]) < 0:
			var card: Dictionary = rules.definition("cards", instance["id"])
			if rules.card_cost(after_state, card) <= int(after_state["energy"]):
				for op: Dictionary in card.get("ops", []):
					if op.get("op", "") in ["damage", "damage_all", "damage_equal_guard", "gain_guard", "weaken_next_attack", "set_intent_idle"]:
						draw_value += 1.5
	score += draw_value
	# Setup cards matter even before immediate damage: guard can power wring,
	# and vow can double guard cards still in hand this same turn.
	for instance: Dictionary in after_state["hand"]:
		var card: Dictionary = rules.definition("cards", instance["id"])
		if rules.card_cost(after_state, card) > int(after_state["energy"]):
			continue
		for op: Dictionary in card.get("ops", []):
			if op.get("op", "") == "damage_equal_guard":
				score += maxi(0, int(after_state["player"]["guard"]) - int(before_state["player"]["guard"])) * 0.8
			if op.get("op", "") == "gain_guard" and int(after_state["guard_multiplier"]) > int(before_state["guard_multiplier"]):
				score += int(op.get("amount", 0)) * 0.4
	return score

func choose_reward(offers: Array, run: Dictionary, strategy: String = "defensive") -> int:
	if offers.is_empty():
		return -1
	var desired: String = "guard" if strategy == "defensive" else "attack"
	var best: int = 0
	var best_score: int = -1
	for index: int in range(offers.size()):
		var offer: Variant = offers[index]
		var id: String = str(offer.get("id", offer.get("item_id", ""))) if offer is Dictionary else str(offer)
		var definition: Dictionary = _find_definition(id)
		var score: int = 2 if definition.get("tendency", "general") == desired else 1
		if id.begins_with("relic."):
			score += 1
		if id == "relic.lone_glove" and desired == "attack":
			score += 2
		if id == "relic.half_biscuit" and int(run.get("hp", 40)) < int(run.get("max_hp", 40)) / 2:
			score += 2
		if score > best_score:
			best_score = score
			best = index
	return best

func _find_definition(id: String) -> Dictionary:
	for category: String in ["cards", "relics"]:
		var table: Variant = _definitions.get(category, [])
		if table is Dictionary and table.has(id):
			return table[id]
		if table is Array:
			for record: Dictionary in table:
				if record.get("id", "") == id:
					return record
	return {}
