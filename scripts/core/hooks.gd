class_name BattleHooks
extends RefCounted
## Hooks never recursively emit card_played. Keepsakes precede relic acquisition order.
static func trigger(rules: RefCounted, state: Dictionary, name: String, context: Dictionary, events: Array) -> void:
	for category: String in ["keepsakes", "relics"]:
		for entry: Variant in state[category]:
			var item_id: String = rules.item_id(entry)
			var definition: Dictionary = rules.definition(category, item_id)
			if str(definition.get("trigger", "")) != name:
				continue
			var condition: Dictionary = definition.get("when", {})
			if condition.has("card_type") and condition["card_type"] != context.get("card_type", ""):
				continue
			if condition.has("card_number") and int(condition["card_number"]) != int(context.get("card_number", state["turn_flags"].get("cards_played", 0))):
				continue
			# Draw bonuses are combined in the draw stage, after all start hooks.
			if item_id == "relic.open_ink" and name == "turn_start":
				continue
			var operations: Array = definition.get("ops", [])
			if operations.is_empty():
				continue
			var effect_context: Dictionary = context.duplicate(true)
			effect_context["source"] = item_id
			effect_context["is_attack_card"] = false
			effect_context["multiplier"] = 1
			events.append({"type": "keepsake_proc" if category == "keepsakes" else "relic_proc", "id": item_id, "trigger": name})
			rules.apply_ops(state, operations, effect_context, events)

static func card_modifiers(rules: RefCounted, state: Dictionary, card: Dictionary, events: Array) -> Dictionary:
	var result: Dictionary = {"repeats": 1, "multiplier": 1}
	if str(card.get("type", "")) == "attack":
		if not bool(state["turn_flags"].get("attack_played", false)) and rules.has_item(state, "relics", "relic.lone_glove"):
			result["repeats"] = int(rules.param("relics", "relic.lone_glove", "repeats", 2))
			events.append({"type": "relic_proc", "id": "relic.lone_glove"})
		state["turn_flags"]["attack_played"] = true
	if int(state["battle_flags"]["cards_played"]) == 0 and rules.has_item(state, "relics", "relic.birthday_candle"):
		result["multiplier"] = int(rules.param("relics", "relic.birthday_candle", "multiplier", 2))
		events.append({"type": "relic_proc", "id": "relic.birthday_candle"})
	return result

static func after_first_draw(rules: RefCounted, state: Dictionary, events: Array) -> void:
	if not rules.has_item(state, "relics", "relic.empty_frame") or state["hand"].is_empty():
		return
	var selected: Dictionary = state["hand"][0]
	var cost: int = int(rules.definition("cards", selected["id"]).get("cost", 0))
	for card: Dictionary in state["hand"]:
		var other_cost: int = int(rules.definition("cards", card["id"]).get("cost", 0))
		if other_cost > cost:
			selected = card
			cost = other_cost
	for count: int in range(int(rules.param("relics", "relic.empty_frame", "copies", 1))):
		if state["hand"].size() >= rules.limit("hand_limit", 8):
			break
		var copy: Dictionary = rules.new_card(state, selected["id"])
		copy["temporary"] = true
		state["hand"].append(copy)
		events.append({"type": "relic_proc", "id": "relic.empty_frame", "card": copy.duplicate(true)})
