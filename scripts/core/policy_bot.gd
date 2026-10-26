class_name PolicyBot
extends RefCounted
## Deterministic public-information policy; all consequences use real rules.
const RNG = preload("res://scripts/core/rng.gd")
var _definitions: Dictionary = {}
var _random_stream: RefCounted
var _last_seed: int = -1
func _init(definitions: Dictionary = {}) -> void:
	_definitions = definitions.duplicate(true)
func choose_action(state: Dictionary, rules: RefCounted, strategy: String = "competent") -> Dictionary:
	var actions: Array = rules.legal_actions(state)
	if actions.is_empty(): return {}
	if strategy == "random_legal":
		if _last_seed != int(state["seed"]):
			_last_seed = int(state["seed"])
			_random_stream = RNG.new(RNG.derive(_last_seed, "random_policy"))
		return actions[_random_stream.range_int(0, actions.size() - 1)].duplicate(true)
	var best: Dictionary = actions[0]
	var best_score: float = -INF
	var before: Dictionary = rules.forecast(state)
	for action: Dictionary in actions:
		if action["type"] == "end_turn":
			if best_score < 0.0:
				best_score = 0.0
				best = action
			continue
		if int(state["turn_flags"]["cards_played"]) >= 30: continue
		if strategy == "no_pairs" and _makes_tie(action, state, rules): continue
		var next: Dictionary = state.duplicate(true)
		var events: Array = rules.apply_action(next, action)
		if not events.is_empty() and events[0].get("type", "") == "invalid_action": continue
		var score: float = _score(state, next, before, rules.forecast(next), rules)
		if action["type"] == "shake_card":
			var removed: Dictionary = rules.definition("cards", state["hand"][action["hand_index"]]["id"])
			var gained: float = 0.0
			for instance: Dictionary in next["hand"]:
				if rules.find_card(state["hand"], instance["uid"]) < 0: gained += _card_value(rules.definition("cards", instance["id"]), next, rules)
			score += (gained - _card_value(removed, state, rules)) * 0.6 - 0.5
		if score > best_score:
			best_score = score
			best = action
	return best.duplicate(true)
func _makes_tie(action: Dictionary, state: Dictionary, rules: RefCounted) -> bool:
	if action["type"] == "use_keepsake": return action["id"] == "keepsake.letter"
	if action["type"] != "play_card": return false
	var card: Dictionary = rules.definition("cards", state["hand"][action["hand_index"]]["id"])
	if rules.is_tie_card(card): return true
	for op: Dictionary in card.get("ops", []):
		if op.get("op", "") in ["pair_threshold_override", "pair_any_now"]: return true
	if action.get("choices", {}).has("other_uid"):
		var index: int = rules.find_card(state["hand"], action["choices"]["other_uid"])
		return index >= 0 and _makes_tie({"type": "play_card", "hand_index": index, "choices": action["choices"].get("other_choices", {})}, state, rules)
	return false
func _score(old: Dictionary, next: Dictionary, before: Dictionary, after: Dictionary, rules: RefCounted) -> float:
	if next["status"] == "victory": return 100000.0 + int(next["battle_flags"]["pairs"]) * 100.0
	if next["status"] == "defeat": return -100000.0
	var score: float = 0.0
	for slot: int in range(old["enemies"].size()):
		var a: Dictionary = old["enemies"][slot]
		var b: Dictionary = next["enemies"][slot]
		score += int(a["hp"]) - int(b["hp"])
		# A renewable minion is not progress against a boss that heals by eating it.
		# Prefer permanent boss HP loss and a breakable armor setup over farming kids.
		if rules.definition("enemies", a["id"]).get("mechanics", {}).has("summon_enemy_id"):
			score += (int(a["hp"]) - int(b["hp"])) * 8.0
			if int(a["guard"]) > int(b["guard"]):
				var followup: float = 0.0
				for instance: Dictionary in next["hand"]:
					var card: Dictionary = rules.definition("cards", instance["id"])
					if rules.card_cost(next, card) <= int(next["energy"]): followup = maxf(followup, _card_damage(card))
				score += maxf(0.0, followup - int(b["guard"])) * 3.0
		score += (int(a["guard"]) - int(b["guard"])) * 0.2
		score += (int(b["binds"]) - int(a["binds"])) * 0.3
		if rules.enemy_alive(old, slot) and not rules.enemy_alive(next, slot): score += 4.0
		var partner: int = rules.partner_slot(next, slot)
		if partner >= 0 and b["pair_tag"] != "" and b["pair_tag"] == next["enemies"][partner]["pair_tag"]:
			if rules.partner_slot(old, slot) < 0: score += 5.0
			var threshold: int = int(ceil(int(b["max_hp"]) * float(b["pair_threshold"])))
			score += (maxi(0, int(a["hp"]) - threshold) - maxi(0, int(b["hp"]) - threshold)) * 0.7
	score += (int(next["battle_flags"]["pairs"]) - int(old["battle_flags"]["pairs"])) * 35.0
	var defense_weight: float = 1.7 + (5.0 if int(before["hp_after"]) <= 0 else 0.0)
	score += (int(before["damage"]) - int(after["damage"])) * defense_weight
	score += (int(next["player"]["hp"]) - int(old["player"]["hp"])) * 1.5
	score += (int(next["energy"]) - int(old["energy"])) * 0.35
	score += (int(next["next_turn_refill"]) - int(old["next_turn_refill"])) * 0.2
	for instance: Dictionary in next["hand"]:
		if rules.find_card(old["hand"], instance["uid"]) < 0:
			var card: Dictionary = rules.definition("cards", instance["id"])
			if rules.card_cost(next, card) <= int(next["energy"]): score += 0.7
	return score
func choose_reward(offers: Array, run: Dictionary, strategy: String = "competent") -> int:
	var best: int = 0
	var best_score: float = -INF
	for i: int in range(offers.size()):
		var id: String = str(offers[i].get("id", ""))
		var score: float = 1.0
		if id.begins_with("relic."): score += 1.0
		var preferred: Array = ["card.big_hammer", "card.double_knot", "card.double_tap", "card.curl_up", "card.clothesline", "relic.shedding_brush", "relic.half_biscuit", "relic.lost_kite", "relic.open_ink", "relic.tangled_earbuds"]
		if id in preferred: score += 3.0
		if strategy == "no_pairs" and id in ["card.double_knot", "card.clothesline", "card.one_pair", "relic.crooked_compass", "relic.lost_kite", "relic.half_biscuit", "relic.lone_glove"]: score -= 10.0
		if id == "relic.half_biscuit" and int(run.get("hp", 40)) < 20: score += 1.0
		if score > best_score:
			best = i
			best_score = score
	return best

func _card_damage(card: Dictionary) -> float:
	var damage: float = 0.0
	for op: Dictionary in card.get("ops", []):
		if op.get("op", "") in ["damage", "damage_all", "damage_if_wilted"]: damage += int(op.get("amount", 0)) * int(op.get("times", 1))
		elif op.get("op", "") == "unbind_damage": damage += int(op.get("amount", 0)) * 3
	return damage

func _card_value(card: Dictionary, state: Dictionary, rules: RefCounted) -> float:
	var value: float = _card_damage(card) * 2.0
	if rules.is_tie_card(card): value += 4.0
	for op: Dictionary in card.get("ops", []):
		if op.get("op", "") in ["bind", "bind_all"]:
			var shortage: int = 0
			for slot: int in rules.living_slots(state): shortage = maxi(shortage, 5 - int(state["enemies"][slot]["binds"]))
			value += mini(int(op.get("amount", 0)), maxi(1, shortage)) * 0.5
		elif op.get("op", "") == "draw": value += int(op.get("amount", 0))
	return value

func choose_replacement(run: Dictionary, strategy: String = "competent", random_index: int = 0) -> int:
	if strategy == "random_legal": return posmod(random_index, run["deck"].size())
	var incoming: Dictionary = _find_card(str(run.get("pending_card", {}).get("id", "")))
	var offensive: bool = _card_damage(incoming) > 0.0
	var selected: int = 0
	var lowest: float = INF
	for index: int in range(run["deck"].size()):
		var old: Dictionary = _find_card(run["deck"][index])
		var damage: float = _card_damage(old)
		if not offensive and damage > 0.0: continue
		var value: float = damage * 3.0
		if old.get("id", "") == "card.bind": value = 1.0
		elif old.get("id", "") == "card.tie": value = 3.0
		elif damage == 0.0: value = 4.0
		if offensive and damage > 0.0: value = damage
		if value < lowest:
			lowest = value
			selected = index
	return selected

func _find_card(id: String) -> Dictionary:
	for card: Dictionary in _definitions.get("cards", []):
		if card["id"] == id: return card
	return {}
