class_name BattleHooks
extends RefCounted
## Declarative relic hooks. Keepsakes are active abilities, never passive hooks.
static func trigger(rules: RefCounted, state: Dictionary, name: String, context: Dictionary, events: Array) -> void:
	for entry: Variant in state["relics"]:
		var item_id: String = rules.item_id(entry)
		var definition: Dictionary = rules.definition("relics", item_id)
		if str(definition.get("trigger", "")) != name: continue
		var condition: Dictionary = definition.get("when", {})
		var matches: bool = true
		for key: String in condition:
			if context.get(key, null) != condition[key]: matches = false
		if not matches: continue
		var operations: Array = definition.get("ops", [])
		if operations.is_empty(): continue
		var active_key: String = item_id + ":" + name
		if state.get("_active_hooks", []).has(active_key):
			events.append({"type": "hook_cycle_blocked", "id": item_id, "trigger": name})
			continue
		if not state.has("_active_hooks"): state["_active_hooks"] = []
		state["_active_hooks"].append(active_key)
		var effect_context: Dictionary = context.duplicate(true)
		effect_context["source"] = item_id
		effect_context["is_attack_card"] = false
		effect_context["multiplier"] = 1
		events.append({"type": "relic_proc", "id": item_id, "trigger": name})
		rules.apply_ops(state, operations, effect_context, events)
		state["_active_hooks"].erase(active_key)
		if state["_active_hooks"].is_empty(): state.erase("_active_hooks")

static func card_modifiers(_rules: RefCounted, state: Dictionary, card: Dictionary, _events: Array) -> Dictionary:
	if card.get("type", "") == "attack": state["turn_flags"]["attack_played"] = true
	return {"repeats": 1, "multiplier": 1}
