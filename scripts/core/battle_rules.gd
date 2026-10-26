class_name BattleRules
extends RefCounted
## Pure deterministic battle engine. Definitions are injected, never read from disk.
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/battle_state.gd")
const Effects = preload("res://scripts/core/effects.gd")
const Hooks = preload("res://scripts/core/hooks.gd")
const Enemies = preload("res://scripts/core/enemy_ai.gd")
const Damage = preload("res://scripts/core/damage_rules.gd")
const Tutorial = preload("res://scripts/core/tutorial_rules.gd")
var _tables: Dictionary = {}
var _balance: Dictionary = {}

func _init(definitions: Dictionary = {}) -> void:
	for category: String in definitions:
		var source: Variant = definitions[category]
		var table: Dictionary = {}
		if source is Array:
			for row: Variant in source:
				if row is Dictionary and row.has("id"):
					table[str(row["id"])] = row.duplicate(true)
		elif source is Dictionary:
			if source.has("id"):
				table[str(source["id"])] = source.duplicate(true)
			else:
				table = source.duplicate(true)
		_tables[category] = table
	_balance = definition("balance", "balance.default")

func definition(category: String, id: String) -> Dictionary:
	return _tables.get(category, {}).get(id, {})

func limit(key: String, fallback: int) -> int:
	# Fallbacks only keep incomplete injected fixtures safe; shipped values are data.
	return int(_balance.get(key, fallback))

func param(category: String, id: String, key: String, fallback: Variant) -> Variant:
	return definition(category, id).get("params", {}).get(key, fallback)

func item_id(value: Variant) -> String:
	return str(value.get("id", "")) if value is Dictionary else str(value)

func has_item(state: Dictionary, category: String, id: String) -> bool:
	for item: Variant in state.get(category, []):
		if item_id(item) == id:
			return true
	return false

func living_slots(state: Dictionary) -> Array[int]:
	return State.living_slots(state)

func enemy_alive(state: Dictionary, slot: int) -> bool:
	return slot >= 0 and slot < state["enemies"].size() and int(state["enemies"][slot]["hp"]) > 0 and str(state["enemies"][slot].get("departed", "")).is_empty()

func find_card(cards: Array, uid: Variant) -> int:
	return State.find_card(cards, uid)

func new_card(state: Dictionary, id: String) -> Dictionary:
	return State.new_card(state, id)

func minion_slots(state: Dictionary, id: String) -> Array[int]:
	var result: Array[int] = []
	for slot: int in living_slots(state):
		if state["enemies"][slot]["id"] == id:
			result.append(slot)
	return result

func start_tutorial(run_state: Dictionary = {}, seed_value: int = 1, tutorial_id: String = "tutorial.wet_sock") -> Dictionary:
	var data: Dictionary = definition("tutorial", tutorial_id)
	if not Tutorial.valid(self, data):
		return {"state": {}, "events": _invalid("invalid_tutorial"), "error": "invalid_tutorial"}
	return start({"id": data["encounter_id"], "enemies": data.get("enemies", [data["enemy"]["enemy_id"]]), "tutorial_id": tutorial_id}, run_state, seed_value)

func _tutorial_data(state: Dictionary) -> Dictionary:
	var data: Dictionary = definition("tutorial", str(state.get("tutorial", {}).get("id", ""))).duplicate(true)
	for prompt: Dictionary in data.get("prompts", {}).values():
		if prompt.has("text_id"): prompt["text"] = definition("ui", prompt["text_id"]).get("text", "")
	return data

func tutorial_status(state: Dictionary) -> Dictionary:
	return Tutorial.status(state, _tutorial_data(state))

func is_tutorial_state_valid(value: Variant) -> bool:
	return Tutorial.valid_saved_state(self, value)

func start(encounter_def: Dictionary, run_state: Dictionary, seed_value: int) -> Dictionary:
	var run: Dictionary = run_state.duplicate(true)
	var tutorial: Dictionary = {}
	if encounter_def.has("tutorial_id"):
		tutorial = definition("tutorial", str(encounter_def["tutorial_id"]))
		if not Tutorial.valid(self, tutorial):
			return {"state": {}, "events": _invalid("invalid_tutorial"), "error": "invalid_tutorial"}
		Tutorial.prepare_run(run, tutorial)
	if not run.has("max_hp"):
		run["max_hp"] = limit("max_hp", 40)
	if not run.has("hp"):
		run["hp"] = run["max_hp"]
	if int(run["max_hp"]) <= 0 or int(run["hp"]) <= 0 or int(run["hp"]) > int(run["max_hp"]):
		return {"state": {}, "events": _invalid("invalid_player_hp"), "error": "invalid_player_hp"}
	var deck: Array = run.get("deck", [])
	if deck.is_empty():
		for id: String in _tables.get("cards", {}):
			for count: int in range(int(definition("cards", id).get("starterCount", 0))):
				deck.append(id)
	if deck.is_empty() or deck.size() > limit("deck_limit", 12):
		return {"state": {}, "events": _invalid("invalid_deck"), "error": "invalid_deck"}
	for card: Variant in deck:
		if definition("cards", item_id(card)).is_empty():
			return {"state": {}, "events": _invalid("unknown_card"), "error": "unknown_card"}
	var encounter: Dictionary = encounter_def.duplicate(true)
	if not tutorial.is_empty():
		encounter["id"] = tutorial["encounter_id"]
		encounter["enemies"] = tutorial.get("enemies", [tutorial["enemy"]["enemy_id"]]).duplicate()
	var enemy_ids: Array = encounter.get("enemies", []).duplicate(true)
	if enemy_ids.is_empty() and not definition("enemies", str(encounter.get("id", ""))).is_empty():
		enemy_ids = [encounter["id"]]
	var modifiers: Dictionary = run.get("next_battle", {})
	for extra: Variant in modifiers.get("extra_enemies", []):
		enemy_ids.append(extra)
	if enemy_ids.is_empty() or enemy_ids.size() > limit("enemy_limit", 4):
		return {"state": {}, "events": _invalid("invalid_encounter"), "error": "invalid_encounter"}
	for enemy: Variant in enemy_ids:
		if definition("enemies", item_id(enemy)).is_empty():
			return {"state": {}, "events": _invalid("unknown_enemy"), "error": "unknown_enemy"}
	var state: Dictionary = State.create(seed_value, run)
	if not tutorial.is_empty():
		state["tutorial"] = {"id": tutorial["id"], "locked_uid": "", "last_step": ""}
	state["player"]["hp"] = clampi(int(run["hp"]), 1, int(run["max_hp"]))
	state["encounter"] = encounter
	state["start_snapshot"] = {"run": run.duplicate(true), "encounter": encounter.duplicate(true), "seed": seed_value}
	state["retry_attempt"] = int(run.get("retry_attempt", 0))
	state["rng"] = {
		"shuffle": Rng.new(int(run.get("shuffle_seed", Rng.derive(seed_value, "shuffle")))).snapshot(),
		"battle": Rng.new(int(run.get("battle_seed", Rng.derive(seed_value, "battle")))).snapshot()
	}
	for card: Variant in deck:
		state["draw_pile"].append(new_card(state, item_id(card)))
	if tutorial.is_empty():
		_shuffle(state, state["draw_pile"])
	var events: Array = [{"type": "battle_start", "encounter": encounter.get("id", "custom"), "seed": seed_value}]
	for enemy: Variant in enemy_ids:
		spawn_enemy(state, item_id(enemy), events)
	Hooks.trigger(self, state, "battle_start", {}, events)
	_refresh_intents(state, events)
	_begin_turn(state, events)
	check_pairs(state, events)
	_finalize(state, events)
	_refresh_intents(state, events)
	Tutorial.update_prompt(state, _tutorial_data(state), events)
	return {"state": state, "events": events}

func play_card(state: Dictionary, hand_index: int, target_index: int = -1, choices: Dictionary = {}) -> Array:
	if state.get("status", "") != "player":
		return _invalid("not_player_turn")
	var reason: String = _validate_card(state, hand_index, target_index, choices, false, [])
	if not reason.is_empty():
		return _invalid(reason)
	var events: Array = []
	resolve_card(state, hand_index, target_index, choices, false, events)
	_finalize(state, events)
	_refresh_intents(state, events)
	Tutorial.update_prompt(state, _tutorial_data(state), events)
	return events

func resolve_card(state: Dictionary, hand_index: int, target_index: int, choices: Dictionary, free: bool, events: Array) -> void:
	if hand_index < 0 or hand_index >= state["hand"].size() or state["status"] == "defeat":
		return
	var instance: Dictionary = state["hand"][hand_index]
	var card: Dictionary = definition("cards", instance["id"])
	var cost: int = 0 if free else card_cost(state, card)
	var modifiers: Dictionary = Hooks.card_modifiers(self, state, card, events)
	state["hand"].remove_at(hand_index)
	if state.has("tutorial") and state["tutorial"].get("locked_uid", "") == instance["uid"]:
		state["tutorial"]["locked_uid"] = ""
	state["energy"] -= cost
	state["resolution_depth"] += 1
	state["battle_flags"]["cards_played"] += 1
	state["turn_flags"]["cards_played"] += 1
	if is_tie_card(card): state["turn_flags"]["ties_played"] += 1
	if card.get("type", "") == "special":
		state["turn_flags"]["special_played"] += 1
	var uses: Dictionary = state["battle_flags"]["uses"]
	uses[instance["id"]] = int(uses.get(instance["id"], 0)) + 1
	var card_number: int = int(state["turn_flags"]["cards_played"])
	events.append({"type": "card_played", "id": instance["id"], "uid": instance["uid"], "target": target_index, "cost": cost, "free": free, "card_number": card_number})
	var context: Dictionary = {"source": instance["id"], "target": target_index, "choices": choices.duplicate(true), "multiplier": modifiers["multiplier"], "is_attack_card": card.get("type", "") == "attack", "card_type": card.get("type", ""), "card_number": card_number}
	for repeat: int in range(int(modifiers["repeats"])):
		apply_ops(state, card.get("fallback_ops", []) if card.get("target", "") == "two_enemies" and living_slots(state).size() == 1 else card.get("ops", []), context, events)
		if state["status"] == "defeat":
			break
	# Restore outer card's sequence for hooks: nested deliver counts as another play,
	# but cannot make both outer and inner cards trigger the third-card hook.
	context["card_number"] = card_number
	if state["status"] != "defeat":
		_trigger_card_hooks(state, context, events)
	state["discard"].append(instance)
	state["resolution_depth"] -= 1
	check_pairs(state, events)

func _trigger_card_hooks(state: Dictionary, context: Dictionary, events: Array) -> void:
	# Generic trigger reads the immutable card-number context, not nested final count.
	Hooks.trigger(self, state, "card_played", context, events)

func is_tie_card(card: Dictionary) -> bool:
	for op: Dictionary in card.get("ops", []):
		if op.get("op", "") in ["tie", "tie_leftmost"]: return true
	return false

func card_cost(state: Dictionary, card: Dictionary) -> int:
	if is_tie_card(card) and int(state["turn_flags"].get("ties_played", 0)) == 0 and item_rule(state, "first_tie_free", false): return 0
	return maxi(0, int(card.get("cost", 0)))

func item_rule(state: Dictionary, key: String, fallback: Variant) -> Variant:
	var value: Variant = fallback
	for item: Variant in state.get("relics", []):
		var data: Dictionary = definition("relics", item_id(item)).get("rules", {})
		if data.has(key): value = data[key]
	return value

func end_turn(state: Dictionary, keep_index: int = -1) -> Array:
	if state.get("status", "") != "player":
		return _invalid("not_player_turn")
	if not tutorial_status(state)["can_end_turn"]:
		return _invalid("tutorial_locked")
	if keep_index < -1 or keep_index >= state["hand"].size():
		return _invalid("invalid_keep_index")
	if keep_index >= 0 and not has_item(state, "relics", "relic.bookmark"):
		return _invalid("no_bookmark")
	var events: Array = []
	Hooks.trigger(self, state, "turn_end", {}, events)
	events.append({"type": "turn_end", "turn": state["turn"], "kept_uid": ""})
	var tutorial: Dictionary = _tutorial_data(state)
	if not tutorial.is_empty() and int(state["turn"]) == 1:
		var prompt: Dictionary = tutorial_status(state)
		prompt.merge(tutorial["prompts"][tutorial["enemy_prompt"]], true)
		prompt.merge({"type": "tutorial_prompt", "prompt_id": str(tutorial["id"]) + "." + str(tutorial["enemy_prompt"]), "step": "enemy", "allowed_card_uid": "", "can_end_turn": false}, true)
		events.append(prompt)
	_enemy_phase(state, events)
	_finalize(state, events)
	if state["status"] == "player":
		_begin_turn(state, events)
	_refresh_intents(state, events)
	Tutorial.update_prompt(state, _tutorial_data(state), events)
	return events

func _begin_turn(state: Dictionary, events: Array) -> void:
	state["status"] = "player"
	state["turn"] += 1
	state["turn_flags"] = {"cards_played": 0, "attack_played": false, "special_played": 0, "first_attacker": -1, "shakes_used": 0, "extra_shakes": 0, "ties_played": 0, "bind_multiplier": 1, "pair_threshold": 0.0}
	state["guard_multiplier"] = 1
	state["retaliate"] = 0
	state["player"]["guard"] = 0
	state["energy"] = limit("energy_per_turn", 3) + int(state["next_turn_energy"])
	var tutorial: Dictionary = _tutorial_data(state)
	if not tutorial.is_empty():
		state["energy"] = int(tutorial["player"]["energy"])
	state["next_turn_energy"] = 0
	events.append({"type": "turn_start", "turn": state["turn"], "energy": state["energy"], "guard": 0})
	if state["turn"] == 1:
		for slot: int in living_slots(state):
			bind_enemy(state, slot, int(state["modifiers"].get("bind_all_start", 0)), events, "next_battle")
	Hooks.trigger(self, state, "turn_start", {}, events)
	var refill: int = maxi(int(item_rule(state, "hand_size", limit("hand_size", 5))), int(state.get("next_turn_refill", 0)))
	var draw_count: int = maxi(0, refill - int(state["next_draw_penalty"]) - state["hand"].size())
	state["next_turn_refill"] = 0
	state["next_draw_penalty"] = 0
	if not tutorial.is_empty():
		draw_count = Tutorial.prepare_draw(state, tutorial, draw_count)
	draw(state, maxi(0, draw_count), events)
	if not tutorial.is_empty():
		Tutorial.after_draw(state, tutorial)
	if state["turn"] == 1:
		pass

func _enemy_phase(state: Dictionary, events: Array) -> void:
	if state["status"] == "defeat" or bool(state["battle_flags"].get("victory_pending", false)):
		return
	state["status"] = "enemy"
	Enemies.turn_start(self, state, events)
	var actors: Array[int] = living_slots(state)
	for slot: int in actors:
		if state["status"] == "defeat" or living_slots(state).is_empty():
			break
		if enemy_alive(state, slot):
			Enemies.execute(self, state, slot, events)
	if state["status"] != "defeat" and not living_slots(state).is_empty():
		Enemies.turn_end(self, state, events)
	if state["status"] != "defeat": check_pairs(state, events)
	if state["status"] != "defeat":
		state["status"] = "player"

func draw(state: Dictionary, amount: int, events: Array) -> void:
	for count: int in range(maxi(0, amount)):
		if state["hand"].size() >= limit("hand_limit", 8):
			events.append({"type": "hand_full", "remaining": amount - count})
			break
		if state["draw_pile"].is_empty():
			if state["discard"].is_empty():
				break
			state["draw_pile"] = state["discard"]
			state["discard"] = []
			_shuffle(state, state["draw_pile"])
			events.append({"type": "shuffle", "count": state["draw_pile"].size()})
		var card: Dictionary = state["draw_pile"].pop_front()
		state["hand"].append(card)
		events.append({"type": "draw", "card": card.duplicate(true)})

func _shuffle(state: Dictionary, cards: Array) -> void:
	var rng: RefCounted = Rng.new(state["rng"]["shuffle"])
	rng.shuffle(cards)
	state["rng"]["shuffle"] = rng.snapshot()

func random_index(state: Dictionary, size: int) -> int:
	var rng: RefCounted = Rng.new(state["rng"]["battle"])
	var value: int = rng.range_int(0, size - 1)
	state["rng"]["battle"] = rng.snapshot()
	return value

func apply_ops(state: Dictionary, operations: Array, context: Dictionary, events: Array) -> void:
	Effects.resolve(self, state, operations, context, events)

func gain_guard(state: Dictionary, _amount: int, _events: Array, _source: String = "player") -> void:
	# Compatibility API only; player armor no longer exists.
	state["player"]["guard"] = 0

func heal(state: Dictionary, amount: int, events: Array, source: String = "player") -> void:
	var actual: int = maxi(0, mini(amount, int(state["player"]["max_hp"]) - int(state["player"]["hp"])))
	state["player"]["hp"] += actual
	events.append({"type": "heal", "target": "player", "amount": actual, "source": source})

func enemy_guard(state: Dictionary, slot: int, amount: int, events: Array) -> void:
	if not enemy_alive(state, slot) or amount <= 0:
		return
	state["enemies"][slot]["guard"] += amount
	events.append({"type": "guard", "target": slot, "amount": amount})

func damage_enemy(state: Dictionary, slot: int, amount: int, context: Dictionary, events: Array) -> void:
	if not enemy_alive(state, slot):
		return
	var enemy: Dictionary = state["enemies"][slot]
	var actual: int = maxi(0, amount)
	if bool(context.get("is_attack_card", false)) and not bool(context.get("linked", false)):
		if int(enemy.get("binds", 0)) > 0: actual += int(item_rule(state, "bound_attack_bonus", 0))
		if living_slots(state).size() == 1: actual += int(item_rule(state, "lone_attack_bonus", 0))
	var partner: int = partner_slot(state, slot)
	var damage_target: Dictionary = enemy.duplicate(true)
	if bool(context.get("linked", false)): damage_target["guard"] = 0
	var result: Dictionary = Damage.apply_damage(damage_target, actual)
	enemy["hp"] = result["state"]["hp"]
	if not bool(context.get("linked", false)): enemy["guard"] = result["state"]["guard"]
	var event: Dictionary = result["events"][0]
	event.merge({"target": slot, "source": context.get("source", "player")})
	events.append(event)
	if partner >= 0 and not bool(context.get("linked", false)) and str(context.get("source", "")).begins_with("card."):
		var linked: Dictionary = context.duplicate(true)
		linked["linked"] = true
		var ratio: float = 1.0 if bool(context.get("link_full", false)) else float(_balance.get("link_ratio", 0.5))
		damage_enemy(state, partner, int(floor(int(event.get("hp_damage", 0)) * ratio)), linked, events)
	if int(enemy["hp"]) == 0 and str(enemy.get("departed", "")).is_empty():
		enemy["departed"] = "scattered"
		untie(state, slot)
		if partner >= 0:
			damage_enemy(state, partner, int(item_rule(state, "scattered_partner_damage", 0)), {"source": "scattered_partner"}, events)
		events.append({"type": "enemy_defeated", "enemy": slot, "id": enemy["id"]})
		Hooks.trigger(self, state, "enemy_defeated", {"target": slot}, events)
		if living_slots(state).is_empty():
			state["battle_flags"]["victory_pending"] = true
	elif int(enemy["hp"]) > 0:
		var mechanics: Dictionary = definition("enemies", enemy["id"]).get("mechanics", {})
		if mechanics.has("phase_hp_below") and int(enemy["hp"]) < int(mechanics["phase_hp_below"]) and not bool(enemy.get("phase_triggered", false)):
			enemy["phase_triggered"] = true
			enemy["phase_first_response_turn"] = int(state["turn"]) + (1 if state["status"] == "enemy" else 0)
			events.append({"type": "boss_warning", "enemy": slot, "turns": int(mechanics.get("phase_warning_turns", 2)), "amount": int(mechanics.get("phase_damage", 16))})

func enemy_attack(state: Dictionary, slot: int, intent: Dictionary, events: Array) -> void:
	var enemy: Dictionary = state["enemies"][slot]
	var canceled: bool = bool(enemy.get("first_attack_pending", false))
	enemy["first_attack_pending"] = false
	var total_damage: int = 0
	var total_blocked: int = 0
	for hit: int in range(int(intent.get("times", 1))):
		if state["status"] == "defeat" or not enemy_alive(state, slot): break
		var amount: int = 0 if canceled else attack_amount(state, slot, intent)
		var available: int = maxi(0, int(enemy["binds"]) - int(intent.get("ignore_binds", 0)))
		var blocked: int = mini(amount, available)
		enemy["binds"] -= blocked
		var damage: int = amount - blocked
		total_damage += damage
		total_blocked += blocked
		var before: int = int(state["player"]["hp"])
		state["player"]["guard"] = 0
		state["player"]["hp"] = maxi(0, before - damage)
		var event: Dictionary = {"type": "damage", "target": "player", "source": slot, "hit": hit, "amount": amount, "blocked": blocked, "hp_damage": mini(before, damage), "canceled": canceled}
		events.append(event)
		if int(state["player"]["hp"]) <= 0:
			if bool(state["spare_rope_available"]) and not bool(state["spare_rope_used"]):
				state["spare_rope_used"] = true
				state["player"]["hp"] = mini(int(state["player"]["max_hp"]), limit("spare_rope_hp", 1))
				event["hp_damage"] = maxi(0, before - int(state["player"]["hp"]))
				event["prevented_lethal"] = true
				for other: int in living_slots(state): bind_enemy(state, other, limit("spare_rope_binds", 5), events, "spare_rope")
				events.append({"type": "spare_rope"})
			else:
				state["status"] = "defeat"
				events.append({"type": "defeat"})
				return
	if total_damage == 0 and total_blocked > 0 and int(enemy.get("recoil", 0)) > 0:
		damage_enemy(state, slot, int(enemy["recoil"]), {"source": "recoil"}, events)
	enemy["recoil"] = 0

func attack_amount(state: Dictionary, slot: int, intent: Dictionary) -> int:
	var amount: int = int(intent.get("amount", 0))
	var partner: int = partner_slot(state, slot)
	var mechanics: Dictionary = definition("enemies", state["enemies"][slot]["id"]).get("mechanics", {})
	if partner >= 0 and state["enemies"][partner].get("pair_tag", "") == mechanics.get("tied_attack_tag", "__none"):
		amount -= int(mechanics.get("tied_attack_reduction", 0))
	return maxi(0, amount)

func spawn_enemy(state: Dictionary, enemy_id: String, events: Array) -> int:
	if living_slots(state).size() >= limit("enemy_limit", 4):
		return -1
	var data: Dictionary = definition("enemies", enemy_id)
	if data.is_empty():
		return -1
	var reduction: float = minf(float(_balance.get("retry_enemy_hp_cap", 0.4)), int(state["retry_attempt"]) * float(_balance.get("retry_enemy_hp_step", 0.2)))
	var hp: int = maxi(1, int(ceil(int(data.get("hp", 1)) * (1.0 - reduction))))
	var tutorial: Dictionary = _tutorial_data(state)
	if not tutorial.is_empty() and tutorial["enemy"]["enemy_id"] == enemy_id:
		hp = int(tutorial["enemy"]["hp"])
	state["next_uid"] += 1
	var enemy: Dictionary = {"uid": "enemy_%d" % state["next_uid"], "id": enemy_id, "hp": hp, "max_hp": hp, "guard": 0, "binds": 0, "tie": "", "departed": "", "pair_tag": data.get("pair_tag", ""), "pair_threshold": data.get("pair_threshold", _balance.get("pair_threshold", 0.5)), "cycle_index": 0, "guard_cycles": 0, "weaken": 0, "idle_override": false, "intent": {}, "phase_triggered": false, "phase_done": false, "first_attack_pending": bool(state["modifiers"].get("cancel_first_attack", state["modifiers"].get("first_attack_immune", false)))}
	if not tutorial.is_empty() and tutorial["enemy"]["enemy_id"] == enemy_id:
		enemy["tutorial_intents"] = tutorial["enemy"]["intents"].duplicate(true)
	var slot: int = state["enemies"].size()
	for index: int in range(state["enemies"].size()):
		if not enemy_alive(state, index):
			slot = index
			break
	if slot == state["enemies"].size():
		state["enemies"].append(enemy)
	else:
		state["enemies"][slot] = enemy
	events.append({"type": "spawn", "enemy_id": enemy_id, "slot": slot, "uid": enemy["uid"]})
	return slot

func _finalize(state: Dictionary, events: Array) -> void:
	if state["status"] == "defeat" or state["status"] == "victory" or int(state["resolution_depth"]) > 0:
		return
	if bool(state["battle_flags"].get("victory_pending", false)) or living_slots(state).is_empty():
		state["status"] = "victory"
		Hooks.trigger(self, state, "battle_won", {}, events)
		events.append({"type": "victory", "turn": state["turn"]})

func retry(state: Dictionary, attempt: int) -> Dictionary:
	if state.get("status", "") != "defeat" or state.get("start_snapshot", {}).is_empty():
		return {"state": state.duplicate(true), "events": _invalid("not_defeated"), "error": "not_defeated"}
	var snapshot: Dictionary = state["start_snapshot"]
	var run: Dictionary = snapshot["run"].duplicate(true)
	var retry_attempt: int = maxi(int(state.get("retry_attempt", 0)) + 1, attempt)
	run["hp"] = maxi(int(snapshot["run"].get("hp", state["player"]["max_hp"])), int(ceil(int(state["player"]["max_hp"]) * float(_balance.get("retry_hp_fraction", 0.5)))))
	run["spare_rope_used"] = bool(state["spare_rope_used"])
	run["keepsakes"] = state["keepsakes"].duplicate(true)
	run["retry_attempt"] = retry_attempt
	run["shuffle_seed"] = Rng.derive(int(snapshot["seed"]), "retry_shuffle_%d" % retry_attempt)
	var result: Dictionary = start(snapshot["encounter"], run, int(snapshot["seed"]))
	if not result["state"].is_empty():
		# Always compare healing against the original battle entry, not prior retry.
		result["state"]["start_snapshot"] = snapshot.duplicate(true)
		result["events"].push_front({"type": "retry", "attempt": retry_attempt})
	return result

func _invalid(reason: String) -> Array:
	return [{"type": "invalid_action", "reason": reason}]

func _validate_card(state: Dictionary, hand_index: int, target_index: int, choices: Dictionary, free: bool, excluded: Array) -> String:
	if hand_index < 0 or hand_index >= state["hand"].size():
		return "invalid_hand_index"
	var instance: Dictionary = state["hand"][hand_index]
	var locked: String = str(state.get("tutorial", {}).get("locked_uid", ""))
	if not locked.is_empty() and instance["uid"] != locked:
		return "tutorial_locked"
	if excluded.has(instance["uid"]):
		return "recursive_card_choice"
	var card: Dictionary = definition("cards", instance["id"])
	if card.is_empty():
		return "unknown_card"
	if card.has("uses_per_battle") and int(state["battle_flags"]["uses"].get(instance["id"], 0)) >= int(card["uses_per_battle"]):
		return "card_use_limit"
	if not free and card_cost(state, card) > int(state["energy"]):
		return "insufficient_energy"
	if card.get("target", "self") in ["enemy", "two_enemies"]:
		if not enemy_alive(state, target_index):
			return "invalid_target"
		if card.get("target", "") == "two_enemies" and living_slots(state).size() > 1:
			var second: int = int(choices.get("second_target", -1))
			if second == target_index or not enemy_alive(state, second): return "invalid_second_target"
	elif target_index != -1:
		return "unexpected_target"
	for op: Dictionary in card.get("ops", []):
		if op.get("op", "") == "return_from_discard":
			if not choices.has("discard_uid") or find_card(state["discard"], choices["discard_uid"]) < 0:
				return "invalid_discard_choice"
		if op.get("op", "") == "free_play_other":
			if not choices.has("other_uid"):
				return "missing_other_choice"
			var selected: int = find_card(state["hand"], choices["other_uid"])
			if selected < 0 or selected == hand_index:
				return "invalid_other_choice"
			if not (choices.get("other_choices", {}) is Dictionary):
				return "invalid_nested_choices"
			var blocked: Array = excluded.duplicate()
			blocked.append(instance["uid"])
			var reason: String = _validate_card(state, selected, int(choices.get("other_target_index", -1)), choices.get("other_choices", {}), true, blocked)
			if not reason.is_empty():
				return reason
	return ""

func legal_actions(state: Dictionary) -> Array:
	var result: Array = []
	if state.get("status", "") != "player":
		return result
	for entry: Variant in state["keepsakes"]:
		var id: String = item_id(entry)
		if bool(state["battle_flags"]["keepsake_uses"].get(id, false)): continue
		var data: Dictionary = definition("keepsakes", id)
		var targets: Array = living_slots(state) if data.get("target", "") in ["enemy", "two_enemies"] else [-1]
		for first: int in targets:
			if data.get("target", "") == "two_enemies" and targets.size() > 1:
				for second: int in targets:
					if first != second: result.append({"type": "use_keepsake", "id": id, "target_index": first, "choices": {"second_target": second}})
			else: result.append({"type": "use_keepsake", "id": id, "target_index": first, "choices": {}})
	for index: int in range(state["hand"].size()):
		for action: Dictionary in _card_actions(state, index, false, []):
			result.append(action)
	if tutorial_status(state)["can_end_turn"]:
		result.append({"type": "end_turn", "keep_index": -1})
	if str(state.get("tutorial", {}).get("locked_uid", "")).is_empty() and int(state["turn_flags"].get("shakes_used", 0)) < limit("shakes_per_turn", 1) + int(state["turn_flags"].get("extra_shakes", 0)):
		for index: int in range(state["hand"].size()): result.append({"type": "shake_card", "hand_index": index})
	return result

func _card_actions(state: Dictionary, index: int, free: bool, excluded: Array) -> Array:
	var instance: Dictionary = state["hand"][index]
	var locked: String = str(state.get("tutorial", {}).get("locked_uid", ""))
	if not locked.is_empty() and instance["uid"] != locked:
		return []
	if excluded.has(instance["uid"]):
		return []
	var card: Dictionary = definition("cards", instance["id"])
	if card.is_empty() or (not free and card_cost(state, card) > int(state["energy"])):
		return []
	if card.has("uses_per_battle") and int(state["battle_flags"]["uses"].get(instance["id"], 0)) >= int(card["uses_per_battle"]):
		return []
	var targets: Array = [-1]
	if card.get("target", "self") in ["enemy", "two_enemies"]:
		targets = living_slots(state)
	var choice_sets: Array = [{}]
	for op: Dictionary in card.get("ops", []):
		if op.get("op", "") == "return_from_discard":
			choice_sets = []
			for discarded: Dictionary in state["discard"]:
				choice_sets.append({"discard_uid": discarded["uid"]})
		elif op.get("op", "") == "free_play_other":
			choice_sets = []
			var blocked: Array = excluded.duplicate()
			blocked.append(instance["uid"])
			for other: int in range(state["hand"].size()):
				if other == index:
					continue
				for nested: Dictionary in _card_actions(state, other, true, blocked):
					choice_sets.append({"other_uid": state["hand"][other]["uid"], "other_target_index": nested["target_index"], "other_choices": nested["choices"]})
	var result: Array = []
	for target: int in targets:
		for choice: Dictionary in choice_sets:
			if card.get("target", "") == "two_enemies" and targets.size() > 1:
				for second: int in targets:
					if second != target: result.append({"type": "play_card", "hand_index": index, "target_index": target, "choices": {"second_target": second}})
			else:
				result.append({"type": "play_card", "hand_index": index, "target_index": target, "choices": choice})
	return result

func preview(state: Dictionary, hand_index: int, target_index: int = -1, choices: Dictionary = {}) -> Dictionary:
	var next: Dictionary = state.duplicate(true)
	var before: Dictionary = forecast(state)
	var events: Array = play_card(next, hand_index, target_index, choices)
	var valid: bool = events.is_empty() or events[0].get("type", "") != "invalid_action"
	var changes: Array = []
	for index: int in range(next.get("enemies", []).size()):
		changes.append({"enemy": index, "hp_before": state["enemies"][index]["hp"], "guard_before": state["enemies"][index]["guard"], "hp_after": next["enemies"][index]["hp"], "guard_after": next["enemies"][index]["guard"]})
	return {"valid": valid, "events": events, "state": next, "forecast_before": before, "forecast_after": forecast(next), "enemy_changes": changes, "player": next.get("player", {}).duplicate(true)}

func forecast(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {"damage": 0, "resolved_damage": 0, "predicted_damage": 0, "hp_loss": 0, "incoming": 0, "hp_after": 0, "guard_after": 0, "intents": [], "next_intents": [], "warnings": [], "events": [], "prediction_stops_at_defeat": false}
	var current: Array = _intent_views(state)
	var next: Dictionary = state.duplicate(true)
	var events: Array = []
	var predicted_damage: int = 0
	if state["status"] == "player":
		Hooks.trigger(self, next, "turn_end", {}, events)
		for intent: Dictionary in current:
			if intent.get("type", "") == "attack":
				predicted_damage += int(intent.get("net_total", int(intent.get("amount", 0)) * int(intent.get("times", 1))))
		predicted_damage = maxi(0, predicted_damage)
		_enemy_phase(next, events)
		_finalize(next, events)
	var incoming: int = 0
	var damage: int = 0
	var hp_loss: int = 0
	for event: Dictionary in events:
		if event.get("type", "") == "damage" and event.get("target", null) is String and event["target"] == "player":
			incoming += int(event.get("amount", 0))
			damage += int(event.get("amount", 0)) - int(event.get("blocked", 0))
			hp_loss += int(event.get("hp_damage", 0))
	var next_intents: Array = []
	if has_item(state, "relics", "relic.spyglass") and int(param("relics", "relic.spyglass", "lookahead", 1)) > 0 and next["status"] == "player":
		next["turn"] += 1
		next["turn_flags"]["first_attacker"] = -1
		next_intents = _intent_views(next)
	# damage is unblocked resolved danger, never silently capped at current HP.
	# predicted_damage is public all-intent pressure before retaliation/early
	# defeat, not a claim that interrupted attacks actually execute.
	return {"damage": damage, "resolved_damage": damage, "predicted_damage": predicted_damage, "hp_loss": hp_loss, "prediction_stops_at_defeat": next["status"] == "defeat", "prediction_basis": "live_intents_before_retaliation", "incoming": incoming, "hp_after": next["player"]["hp"], "guard_after": next["player"]["guard"], "intents": current, "next_intents": next_intents, "warnings": _warnings(state), "events": events}

func _intent_views(state: Dictionary, include_future: bool = true) -> Array:
	var result: Array = []
	var lookaheads: Dictionary = {}
	var furthest: int = 0
	for slot: int in living_slots(state):
		var intent: Dictionary = Enemies.raw_intent(self, state, slot)
		intent["enemy"] = slot
		intent["id"] = state["enemies"][slot]["id"]
		if intent.get("type", "") == "attack":
			intent["raw_amount"] = attack_amount(state, slot, intent)
			intent["times"] = int(intent.get("times", 1))
			intent["canceled"] = bool(state["enemies"][slot]["first_attack_pending"])
			var remaining: int = int(state["enemies"][slot]["binds"])
			var hits: Array = []
			var net_total: int = 0
			for hit: int in range(intent["times"]):
				var raw: int = 0 if intent["canceled"] else int(intent["raw_amount"])
				var blocked: int = mini(raw, maxi(0, remaining - int(intent.get("ignore_binds", 0))))
				remaining -= blocked
				hits.append(raw - blocked)
				net_total += raw - blocked
			intent["amount"] = hits[0] if not hits.is_empty() else 0
			intent["hit_amounts"] = hits
			intent["net_total"] = net_total
		var lookahead: int = maxi(int(state["enemies"][slot].get("lookahead", 0)), int(param("relics", "relic.spyglass", "lookahead", 1)) if has_item(state, "relics", "relic.spyglass") else 0)
		intent["future_intents"] = []
		lookaheads[slot] = lookahead
		furthest = maxi(furthest, lookahead)
		result.append(intent)
	if include_future and furthest > 0:
		var projected: Dictionary = projected_intents(state, furthest)
		for intent: Dictionary in result:
			var slot: int = int(intent["enemy"])
			intent["future_intents"] = projected.get(state["enemies"][slot]["uid"], []).slice(0, int(lookaheads[slot]))
	return result

func projected_intents(state: Dictionary, count: int) -> Dictionary:
	# Conditional on no further player actions. Use stable UIDs and real turn
	# execution so one-shot phases, swaps, idle, summoning and consumption agree.
	var future: Dictionary = {}
	for slot: int in living_slots(state): future[state["enemies"][slot]["uid"]] = []
	if state.get("status", "") != "player": return future
	var projected: Dictionary = state.duplicate(true)
	for step: int in range(maxi(0, count)):
		var ignored_events: Array = []
		Hooks.trigger(self, projected, "turn_end", {}, ignored_events)
		_enemy_phase(projected, ignored_events)
		_finalize(projected, ignored_events)
		if projected["status"] != "player": break
		_begin_turn(projected, ignored_events)
		for uid: String in future:
			var intent: Dictionary = {"type": "defeated", "amount": 0}
			for slot: int in living_slots(projected):
				if projected["enemies"][slot]["uid"] == uid:
					intent = Enemies.raw_intent(self, projected, slot)
					break
			future[uid].append(intent)
	return future

func _warnings(state: Dictionary) -> Array:
	var result: Array = []
	for slot: int in living_slots(state):
		var enemy: Dictionary = state["enemies"][slot]
		if bool(enemy.get("phase_triggered", false)) and not bool(enemy.get("phase_done", false)):
			if bool(enemy.get("idle_override", false)) and bool(Enemies.raw_intent(self, state, slot).get("phase_attack", false)):
				continue
			var mechanics: Dictionary = definition("enemies", enemy["id"]).get("mechanics", {})
			var turns: int = maxi(1, int(enemy["phase_first_response_turn"]) + int(mechanics.get("phase_warning_turns", 2)) - int(state["turn"]))
			var amount: int = int(mechanics.get("phase_damage", 16))
			result.append({"enemy": slot, "turns": turns, "amount": amount, "text": "%d 回合后：大缠绕 %d" % [turns, amount]})
	return result

func _refresh_intents(state: Dictionary, events: Array) -> void:
	state["warnings"] = _warnings(state)
	for intent: Dictionary in _intent_views(state):
		var slot: int = int(intent["enemy"])
		state["enemies"][slot]["intent"] = intent.duplicate(true)
		events.append({"type": "intent", "enemy": slot, "intent": intent.duplicate(true)})
	for index: int in range(state["enemies"].size()):
		if not enemy_alive(state, index):
			state["enemies"][index]["intent"] = {"type": "defeated", "amount": 0}

func bind_enemy(state: Dictionary, slot: int, amount: int, events: Array, source: String = "player") -> void:
	if not enemy_alive(state, slot) or amount <= 0: return
	var enemy: Dictionary = state["enemies"][slot]
	var total: int = (amount + int(state.get("bind_bonus", 0))) * int(state["turn_flags"].get("bind_multiplier", 1))
	var actual: int = mini(limit("bind_cap", 12) - int(enemy["binds"]), total)
	enemy["binds"] += actual
	events.append({"type": "bind", "enemy": slot, "amount": actual, "binds": enemy["binds"], "source": source})
	Hooks.trigger(self, state, "bind_applied", {"target": slot, "amount": actual}, events)

func partner_slot(state: Dictionary, slot: int) -> int:
	if slot < 0 or slot >= state["enemies"].size(): return -1
	var uid: String = str(state["enemies"][slot].get("tie", ""))
	if uid.is_empty(): return -1
	for other: int in living_slots(state):
		if state["enemies"][other]["uid"] == uid: return other
	return -1

func untie(state: Dictionary, slot: int) -> void:
	var uid: String = str(state["enemies"][slot]["uid"])
	for enemy: Dictionary in state["enemies"]:
		if enemy.get("tie", "") == uid: enemy["tie"] = ""
	state["enemies"][slot]["tie"] = ""

func tie_enemies(state: Dictionary, first: int, second: int, events: Array, any_pair: bool = false) -> void:
	if first == second or not enemy_alive(state, first) or not enemy_alive(state, second): return
	untie(state, first)
	untie(state, second)
	state["enemies"][first]["tie"] = state["enemies"][second]["uid"]
	state["enemies"][second]["tie"] = state["enemies"][first]["uid"]
	state["enemies"][first]["tie_any_pair"] = any_pair
	state["enemies"][second]["tie_any_pair"] = any_pair
	var context: Dictionary = {"target": first, "second_target": second, "choices": {"second_target": second}}
	events.append({"type": "tie_made", "target": first, "second_target": second})
	Hooks.trigger(self, state, "tie_made", context, events)

func wilted(enemy: Dictionary, threshold: float = 0.0) -> bool:
	var ratio: float = threshold if threshold > 0.0 else float(enemy.get("pair_threshold", 0.5))
	return int(enemy["hp"]) <= int(ceil(int(enemy["max_hp"]) * ratio))

func check_pairs(state: Dictionary, events: Array, threshold: float = 0.0) -> void:
	if state["status"] == "defeat": return
	var override: float = maxf(threshold, float(state["turn_flags"].get("pair_threshold", 0.0)))
	for first: int in living_slots(state):
		if not enemy_alive(state, first): continue
		var second: int = partner_slot(state, first)
		if second < 0 or second < first: continue
		var a: Dictionary = state["enemies"][first]
		var b: Dictionary = state["enemies"][second]
		var peaceful: bool = false
		for pair: Array in [[a, b], [b, a]]:
			var mechanics: Dictionary = definition("enemies", pair[0]["id"]).get("mechanics", {})
			if mechanics.has("peace_pair_tag") and pair[1].get("pair_tag", "") == mechanics["peace_pair_tag"] and wilted(pair[0], float(mechanics.get("peace_threshold", 0.3))): peaceful = true
		var same: bool = not str(a.get("pair_tag", "")).is_empty() and a.get("pair_tag", "") == b.get("pair_tag", "")
		if not peaceful and not ((same or bool(a.get("tie_any_pair", false)) or bool(b.get("tie_any_pair", false))) and wilted(a, override if same else 0.0) and wilted(b, override if same else 0.0)): continue
		a["departed"] = "paired"
		b["departed"] = "paired"
		untie(state, first)
		untie(state, second)
		state["battle_flags"]["pairs"] += 1
		events.append({"type": "pair_formed", "enemies": [first, second], "pairs": state["battle_flags"]["pairs"], "peaceful": peaceful})
		Hooks.trigger(self, state, "pair_formed", {"target": first, "second_target": second, "pair_number": state["battle_flags"]["pairs"]}, events)
		if peaceful:
			state["battle_flags"]["peaceful"] = true
			for enemy: Dictionary in state["enemies"]:
				if int(enemy["hp"]) > 0: enemy["departed"] = "paired"
	if living_slots(state).is_empty(): state["battle_flags"]["victory_pending"] = true

func shake_card(state: Dictionary, hand_index: int) -> Array:
	if state.get("status", "") != "player": return _invalid("not_player_turn")
	if not str(state.get("tutorial", {}).get("locked_uid", "")).is_empty(): return _invalid("tutorial_locked")
	if hand_index < 0 or hand_index >= state["hand"].size(): return _invalid("invalid_hand_index")
	if int(state["turn_flags"].get("shakes_used", 0)) >= limit("shakes_per_turn", 1) + int(state["turn_flags"].get("extra_shakes", 0)): return _invalid("no_shakes_left")
	var card: Dictionary = state["hand"].pop_at(hand_index)
	state["discard"].append(card)
	state["turn_flags"]["shakes_used"] += 1
	var events: Array = [{"type": "shake_card", "card": card.duplicate(true)}]
	draw(state, 1, events)
	Hooks.trigger(self, state, "shake_card", {"shake_number": state["turn_flags"]["shakes_used"]}, events)
	return events

func shake_off(state: Dictionary, slot: int, mode: String, events: Array) -> int:
	var enemy: Dictionary = state["enemies"][slot]
	var amount: int = int(enemy["binds"])
	if mode == "half": amount = int(floor(amount * 0.5))
	if item_rule(state, "shake_off_half", false): amount = mini(amount, int(floor(int(enemy["binds"]) * 0.5)))
	enemy["binds"] -= amount
	events.append({"type": "enemy_shake_off", "enemy": slot, "amount": amount})
	Hooks.trigger(self, state, "enemy_shake_off", {"target": slot, "amount": amount}, events)
	return amount

func use_keepsake(state: Dictionary, id: String, target_index: int = -1, choices: Dictionary = {}) -> Array:
	if state.get("status", "") != "player": return _invalid("not_player_turn")
	if not has_item(state, "keepsakes", id): return _invalid("unowned_keepsake")
	if bool(state["battle_flags"]["keepsake_uses"].get(id, false)): return _invalid("keepsake_used")
	var data: Dictionary = definition("keepsakes", id)
	if data.is_empty(): return _invalid("unknown_keepsake")
	if data.get("target", "") in ["enemy", "two_enemies"]:
		if not enemy_alive(state, target_index): return _invalid("invalid_target")
		if data["target"] == "two_enemies" and living_slots(state).size() > 1:
			var second: int = int(choices.get("second_target", -1))
			if second == target_index or not enemy_alive(state, second): return _invalid("invalid_second_target")
	elif target_index != -1: return _invalid("unexpected_target")
	state["battle_flags"]["keepsake_uses"][id] = true
	var events: Array = [{"type": "keepsake_proc", "id": id, "active": true, "line": data.get("get_line", ""), "target": target_index}]
	var operations: Array = data.get("fallback_ops", []) if data.get("target", "") == "two_enemies" and living_slots(state).size() == 1 else data.get("ops", [])
	apply_ops(state, operations, {"source": id, "target": target_index, "choices": choices.duplicate(true)}, events)
	check_pairs(state, events)
	_finalize(state, events)
	_refresh_intents(state, events)
	return events

func apply_action(state: Dictionary, action: Dictionary) -> Array:
	match str(action.get("type", "")):
		"play_card": return play_card(state, int(action.get("hand_index", -1)), int(action.get("target_index", -1)), action.get("choices", {}))
		"shake_card": return shake_card(state, int(action.get("hand_index", -1)))
		"use_keepsake": return use_keepsake(state, str(action.get("id", "")), int(action.get("target_index", -1)), action.get("choices", {}))
		"end_turn": return end_turn(state)
	return _invalid("unknown_action")
