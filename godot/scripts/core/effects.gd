class_name BattleEffects
extends RefCounted
## Data operations use one resolution path for actual play and copied previews.
static func resolve(rules: RefCounted, state: Dictionary, operations: Array, context: Dictionary, events: Array) -> void:
	for operation: Dictionary in operations:
		if state["status"] == "defeat":
			return
		var amount: int = int(operation.get("amount", 1)) * int(context.get("multiplier", 1))
		if operation.get("multiplier", "") == "remaining_energy":
			amount *= int(state["energy"])
		var target: int = int(context.get("target", -1))
		match str(operation.get("op", "")):
			"damage":
				for hit: int in range(int(operation.get("times", 1))):
					rules.damage_enemy(state, target, amount, context, events)
			"damage_all":
				for slot: int in rules.living_slots(state):
					rules.damage_enemy(state, slot, amount, context, events)
			"damage_random":
				var slots: Array = rules.living_slots(state)
				if not slots.is_empty():
					rules.damage_enemy(state, slots[rules.random_index(state, slots.size())], amount, context, events)
			"damage_equal_guard":
				rules.damage_enemy(state, target, int(state["player"]["guard"]) * int(context.get("multiplier", 1)), context, events)
			"gain_guard":
				rules.gain_guard(state, amount, events, str(context.get("source", "player")))
			"heal":
				rules.heal(state, amount, events, str(context.get("source", "player")))
			"draw":
				rules.draw(state, amount, events)
			"gain_energy":
				state["energy"] += amount
				events.append({"type": "energy", "amount": amount, "energy": state["energy"]})
			"next_turn_energy":
				state["next_turn_energy"] += amount
				events.append({"type": "next_turn_energy", "amount": amount})
			"weaken_next_attack":
				if rules.enemy_alive(state, target):
					state["enemies"][target]["weaken"] += amount
					events.append({"type": "weaken", "enemy": target, "amount": amount})
			"set_intent_idle":
				if rules.enemy_alive(state, target):
					state["enemies"][target]["idle_override"] = true
					events.append({"type": "idle", "enemy": target})
			"return_from_discard":
				var uid: Variant = context.get("choices", {}).get("discard_uid", "")
				var chosen: int = rules.find_card(state["discard"], uid)
				if chosen >= 0 and state["hand"].size() < rules.limit("hand_limit", 8):
					var card: Dictionary = state["discard"].pop_at(chosen)
					state["hand"].append(card)
					events.append({"type": "return_card", "card": card.duplicate(true)})
			"double_guard_this_turn":
				# A rule switch, not a counted effect: candle does not make it x4.
				state["guard_multiplier"] = 2
				events.append({"type": "guard_multiplier", "amount": 2})
			"free_play_other":
				var choices: Dictionary = context.get("choices", {})
				var chosen: int = rules.find_card(state["hand"], choices.get("other_uid", ""))
				if chosen >= 0:
					rules.resolve_card(state, chosen, int(choices.get("other_target_index", -1)), choices.get("other_choices", {}), true, events)
			"retaliate":
				state["retaliate"] += amount
				events.append({"type": "retaliate", "amount": amount})
