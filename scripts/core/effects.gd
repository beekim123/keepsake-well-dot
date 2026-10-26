class_name BattleEffects
extends RefCounted
## Data operations share actual-play and copied-preview resolution.
static func resolve(rules: RefCounted, state: Dictionary, operations: Array, context: Dictionary, events: Array) -> void:
	for operation: Dictionary in operations:
		if state["status"] == "defeat": return
		var amount: int = int(operation.get("amount", 1)) * int(context.get("multiplier", 1))
		if operation.get("multiplier", "") == "remaining_energy": amount *= int(state["energy"])
		var target: int = int(context.get("target", -1))
		var second: int = int(context.get("choices", {}).get("second_target", context.get("second_target", -1)))
		var source: String = str(context.get("source", "player"))
		match str(operation.get("op", "")):
			"damage":
				var damage_context: Dictionary = context.duplicate(true)
				damage_context["link_full"] = bool(operation.get("link_full", context.get("link_full", false)))
				for hit: int in range(int(operation.get("times", 1))): rules.damage_enemy(state, target, amount, damage_context, events)
			"link_full": context["link_full"] = true
			"damage_all":
				for slot: int in rules.living_slots(state): rules.damage_enemy(state, slot, amount, context, events)
			"damage_both":
				rules.damage_enemy(state, target, amount, context, events)
				rules.damage_enemy(state, second, amount, context, events)
			"damage_random":
				var slots: Array = rules.living_slots(state)
				if not slots.is_empty(): rules.damage_enemy(state, slots[rules.random_index(state, slots.size())], amount, context, events)
			"bind": rules.bind_enemy(state, target, amount, events, source)
			"bind_all":
				for slot: int in rules.living_slots(state): rules.bind_enemy(state, slot, amount, events, source)
			"bind_both":
				rules.bind_enemy(state, target, amount, events, source)
				rules.bind_enemy(state, second, amount, events, source)
			"tie": rules.tie_enemies(state, target, second, events, bool(operation.get("any_pair", false)))
			"tie_leftmost":
				var slots: Array = []
				for slot: int in rules.living_slots(state):
					if rules.partner_slot(state, slot) < 0: slots.append(slot)
				if slots.size() >= 2: rules.tie_enemies(state, slots[0], slots[1], events)
			"tie_matching":
				var found: bool = false
				for first: int in rules.living_slots(state):
					for other: int in rules.living_slots(state):
						if not found and first < other and not str(state["enemies"][first]["pair_tag"]).is_empty() and state["enemies"][first]["pair_tag"] == state["enemies"][other]["pair_tag"]:
							rules.tie_enemies(state, first, other, events)
							found = true
			"unbind_damage":
				if rules.enemy_alive(state, target):
					var rings: int = int(state["enemies"][target]["binds"])
					state["enemies"][target]["binds"] = 0
					rules.damage_enemy(state, target, rings * amount, context, events)
			"move_binds":
				if rules.enemy_alive(state, target) and rules.enemy_alive(state, second):
					var rings: int = int(state["enemies"][target]["binds"])
					state["enemies"][target]["binds"] = 0
					state["enemies"][second]["binds"] = mini(rules.limit("bind_cap", 12), int(state["enemies"][second]["binds"]) + rings)
					rules.bind_enemy(state, second, amount, events, source)
			"swap_intent_with_partner":
				var partner: int = rules.partner_slot(state, target)
				if partner >= 0:
					var own: Dictionary = rules.Enemies.raw_intent(rules, state, target)
					var other: Dictionary = rules.Enemies.raw_intent(rules, state, partner)
					state["enemies"][target]["intent_override"] = other
					state["enemies"][partner]["intent_override"] = own
			"idle_if_binds":
				if rules.enemy_alive(state, target):
					if int(state["enemies"][target]["binds"]) >= int(operation.get("threshold", 3)): state["enemies"][target]["idle_override"] = true
					else: rules.bind_enemy(state, target, amount, events, source)
			"bonus_hit_if_bound":
				if rules.enemy_alive(state, target) and int(state["enemies"][target]["binds"]) > 0: rules.damage_enemy(state, target, amount, context, events)
			"damage_if_wilted":
				if rules.enemy_alive(state, target): rules.damage_enemy(state, target, int(operation.get("wilted_amount", amount)) if rules.wilted(state["enemies"][target]) else amount, context, events)
			"recoil_if_fully_bound":
				if rules.enemy_alive(state, target): state["enemies"][target]["recoil"] = int(state["enemies"][target].get("recoil", 0)) + amount
			"pair_threshold_override":
				var found: bool = false
				for slot: int in rules.living_slots(state):
					var partner: int = rules.partner_slot(state, slot)
					if partner >= 0 and not str(state["enemies"][slot]["pair_tag"]).is_empty() and state["enemies"][slot]["pair_tag"] == state["enemies"][partner]["pair_tag"]: found = true
				if found: state["turn_flags"]["pair_threshold"] = float(operation.get("threshold", 0.75))
				else:
					for slot: int in rules.living_slots(state): rules.bind_enemy(state, slot, amount, events, source)
			"double_binds_this_turn": state["turn_flags"]["bind_multiplier"] = 2
			"next_turn_refill": state["next_turn_refill"] = maxi(int(state["next_turn_refill"]), amount)
			"extra_shake": state["turn_flags"]["extra_shakes"] += amount
			"per_pair_draw_energy":
				var pairs: int = int(state["battle_flags"]["pairs"])
				rules.draw(state, maxi(1, pairs), events)
				state["energy"] += pairs
			"reveal_intents":
				if rules.enemy_alive(state, target): state["enemies"][target]["lookahead"] = amount
			"heal": rules.heal(state, amount, events, source)
			"draw": rules.draw(state, amount, events)
			"gain_energy":
				state["energy"] += amount
				events.append({"type": "energy", "amount": amount, "energy": state["energy"]})
			"next_turn_energy": state["next_turn_energy"] += amount
			"set_intent_idle":
				if rules.enemy_alive(state, target): state["enemies"][target]["idle_override"] = true
			"idle_leftmost":
				var slots: Array = rules.living_slots(state)
				if not slots.is_empty(): state["enemies"][slots[0]]["idle_override"] = true
			"bind_threat":
				var selected: int = -1
				var danger: int = -1
				for intent: Dictionary in rules._intent_views(state):
					if int(intent.get("net_total", 0)) > danger:
						selected = int(intent["enemy"])
						danger = int(intent.get("net_total", 0))
				rules.bind_enemy(state, selected, amount, events, source)
			"free_play_other":
				var choices: Dictionary = context.get("choices", {})
				var chosen: int = rules.find_card(state["hand"], choices.get("other_uid", ""))
				if chosen >= 0:
					var tie_card: bool = rules.is_tie_card(rules.definition("cards", state["hand"][chosen]["id"]))
					rules.resolve_card(state, chosen, int(choices.get("other_target_index", -1)), choices.get("other_choices", {}), true, events)
					if tie_card: rules.check_pairs(state, events, float(operation.get("pair_threshold", 0.75)))
