class_name BattleRules
extends RefCounted
## Pure deterministic battle engine. Definitions are injected, never read from disk.
const Rng = preload("res://scripts/core/rng.gd")
const State = preload("res://scripts/core/battle_state.gd")
const Effects = preload("res://scripts/core/effects.gd")
const Hooks = preload("res://scripts/core/hooks.gd")
const Enemies = preload("res://scripts/core/enemy_ai.gd")
const Damage = preload("res://scripts/core/damage_rules.gd")
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
	return slot >= 0 and slot < state["enemies"].size() and int(state["enemies"][slot]["hp"]) > 0

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

func start(encounter_def: Dictionary, run_state: Dictionary, seed_value: int) -> Dictionary:
	var run: Dictionary = run_state.duplicate(true)
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
	_shuffle(state, state["draw_pile"])
	var events: Array = [{"type": "battle_start", "encounter": encounter.get("id", "custom"), "seed": seed_value}]
	for enemy: Variant in enemy_ids:
		spawn_enemy(state, item_id(enemy), events)
	Hooks.trigger(self, state, "battle_start", {}, events)
	_refresh_intents(state, events)
	_begin_turn(state, events)
	_finalize(state, events)
	_refresh_intents(state, events)
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
	return events

func resolve_card(state: Dictionary, hand_index: int, target_index: int, choices: Dictionary, free: bool, events: Array) -> void:
	if hand_index < 0 or hand_index >= state["hand"].size() or state["status"] == "defeat":
		return
	var instance: Dictionary = state["hand"][hand_index]
	var card: Dictionary = definition("cards", instance["id"])
	var cost: int = 0 if free else card_cost(state, card)
	var modifiers: Dictionary = Hooks.card_modifiers(self, state, card, events)
	state["hand"].remove_at(hand_index)
	state["energy"] -= cost
	state["resolution_depth"] += 1
	state["battle_flags"]["cards_played"] += 1
	state["turn_flags"]["cards_played"] += 1
	if card.get("type", "") == "special":
		state["turn_flags"]["special_played"] += 1
	var uses: Dictionary = state["battle_flags"]["uses"]
	uses[instance["id"]] = int(uses.get(instance["id"], 0)) + 1
	var card_number: int = int(state["turn_flags"]["cards_played"])
	events.append({"type": "card_played", "id": instance["id"], "uid": instance["uid"], "target": target_index, "cost": cost, "free": free, "card_number": card_number})
	var context: Dictionary = {"source": instance["id"], "target": target_index, "choices": choices.duplicate(true), "multiplier": modifiers["multiplier"], "is_attack_card": card.get("type", "") == "attack", "card_type": card.get("type", ""), "card_number": card_number}
	for repeat: int in range(int(modifiers["repeats"])):
		apply_ops(state, card.get("ops", []), context, events)
		if state["status"] == "defeat":
			break
	# Restore outer card's sequence for hooks: nested deliver counts as another play,
	# but cannot make both outer and inner cards trigger the third-card hook.
	context["card_number"] = card_number
	if state["status"] != "defeat":
		_trigger_card_hooks(state, context, events)
	state["discard"].append(instance)
	state["resolution_depth"] -= 1

func _trigger_card_hooks(state: Dictionary, context: Dictionary, events: Array) -> void:
	# Generic trigger reads the immutable card-number context, not nested final count.
	Hooks.trigger(self, state, "card_played", context, events)

func card_cost(state: Dictionary, card: Dictionary) -> int:
	if card.get("type", "") == "special" and has_item(state, "keepsakes", "keepsake.letter") and int(state["turn_flags"].get("special_played", 0)) < int(param("keepsakes", "keepsake.letter", "free_special_cards", 1)):
		return 0
	return maxi(0, int(card.get("cost", 0)))

func end_turn(state: Dictionary, keep_index: int = -1) -> Array:
	if state.get("status", "") != "player":
		return _invalid("not_player_turn")
	if keep_index < -1 or keep_index >= state["hand"].size():
		return _invalid("invalid_keep_index")
	if keep_index >= 0 and not has_item(state, "relics", "relic.bookmark"):
		return _invalid("no_bookmark")
	var events: Array = []
	var keep_uid: String = str(state["hand"][keep_index]["uid"]) if keep_index >= 0 else ""
	Hooks.trigger(self, state, "turn_end", {}, events)
	var kept: Array = []
	for card: Dictionary in state["hand"]:
		if str(card["uid"]) == keep_uid:
			kept.append(card)
		else:
			state["discard"].append(card)
	state["hand"] = kept
	events.append({"type": "turn_end", "turn": state["turn"], "kept_uid": keep_uid})
	_enemy_phase(state, events)
	_finalize(state, events)
	if state["status"] == "player":
		_begin_turn(state, events)
	_refresh_intents(state, events)
	return events

func _begin_turn(state: Dictionary, events: Array) -> void:
	state["status"] = "player"
	state["turn"] += 1
	state["turn_flags"] = {"cards_played": 0, "attack_played": false, "special_played": 0, "first_attacker": -1}
	state["guard_multiplier"] = 1
	state["retaliate"] = 0
	var retained: int = 0
	if has_item(state, "relics", "relic.leaky_balloon"):
		retained = int(floor(float(state["player"]["guard"]) * float(param("relics", "relic.leaky_balloon", "retention", 0.5))))
	state["player"]["guard"] = retained
	state["energy"] = limit("energy_per_turn", 3) + int(state["next_turn_energy"])
	state["next_turn_energy"] = 0
	events.append({"type": "turn_start", "turn": state["turn"], "energy": state["energy"], "guard": retained})
	# The event's promised start guard survives the first scheduled guard clear.
	if state["turn"] == 1:
		gain_guard(state, int(state["modifiers"].get("start_guard", 0)), events, "next_battle")
	Hooks.trigger(self, state, "turn_start", {}, events)
	var draw_count: int = limit("draw_per_turn", 4) - int(state["next_draw_penalty"])
	state["next_draw_penalty"] = 0
	if has_item(state, "relics", "relic.open_ink"):
		for op: Dictionary in definition("relics", "relic.open_ink").get("ops", []):
			if op.get("op", "") == "draw":
				draw_count += int(op.get("amount", 0))
	if state["turn"] == 1 and has_item(state, "relics", "relic.crooked_compass"):
		draw_count += int(param("relics", "relic.crooked_compass", "draw", 3))
	draw(state, maxi(0, draw_count), events)
	if state["turn"] == 1:
		Hooks.after_first_draw(self, state, events)

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

func gain_guard(state: Dictionary, amount: int, events: Array, source: String = "player") -> void:
	var actual: int = maxi(0, amount) * int(state["guard_multiplier"])
	if actual == 0:
		return
	state["player"]["guard"] += actual
	events.append({"type": "guard", "target": "player", "amount": actual, "source": source})

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
	if bool(context.get("is_attack_card", false)) and int(enemy["guard"]) > 0 and has_item(state, "relics", "relic.shedding_brush"):
		actual += int(param("relics", "relic.shedding_brush", "damage", 3))
		events.append({"type": "relic_proc", "id": "relic.shedding_brush", "enemy": slot})
	var result: Dictionary = Damage.apply_damage(enemy, actual)
	enemy["hp"] = result["state"]["hp"]
	enemy["guard"] = result["state"]["guard"]
	var event: Dictionary = result["events"][0]
	event.merge({"target": slot, "source": context.get("source", "player")})
	events.append(event)
	if int(enemy["hp"]) == 0:
		events.append({"type": "enemy_defeated", "enemy": slot, "id": enemy["id"]})
		Hooks.trigger(self, state, "enemy_defeated", {"target": slot}, events)
		if living_slots(state).is_empty():
			state["battle_flags"]["victory_pending"] = true
	else:
		var mechanics: Dictionary = definition("enemies", enemy["id"]).get("mechanics", {})
		if mechanics.has("phase_hp_below") and int(enemy["hp"]) < int(mechanics["phase_hp_below"]) and not bool(enemy.get("phase_triggered", false)):
			enemy["phase_triggered"] = true
			enemy["phase_first_response_turn"] = int(state["turn"]) + (1 if state["status"] == "enemy" else 0)
			events.append({"type": "boss_warning", "enemy": slot, "turns": int(mechanics.get("phase_warning_turns", 2)), "amount": int(mechanics.get("phase_damage", 16))})

func enemy_attack(state: Dictionary, slot: int, intent: Dictionary, events: Array) -> void:
	var enemy: Dictionary = state["enemies"][slot]
	var reduction: int = int(enemy["weaken"])
	if int(state["turn_flags"].get("first_attacker", -1)) == -1:
		state["turn_flags"]["first_attacker"] = slot
		if has_item(state, "keepsakes", "keepsake.mianmian"):
			reduction += int(param("keepsakes", "keepsake.mianmian", "reduction", 3))
			events.append({"type": "keepsake_proc", "id": "keepsake.mianmian", "enemy": slot})
	var canceled: bool = bool(enemy.get("first_attack_pending", false))
	enemy["first_attack_pending"] = false
	enemy["weaken"] = 0
	Hooks.trigger(self, state, "incoming_attack", {"target": slot}, events)
	for hit: int in range(int(intent.get("times", 1))):
		if state["status"] == "defeat" or not enemy_alive(state, slot):
			break
		var amount: int = 0 if canceled else maxi(0, int(intent.get("amount", 0)) - reduction)
		var guard_before: int = int(state["player"]["guard"])
		var hp_before: int = int(state["player"]["hp"])
		var result: Dictionary = Damage.apply_damage(state["player"], amount)
		state["player"] = result["state"]
		var guard_after_damage: int = int(state["player"]["guard"])
		var event: Dictionary = result["events"][0]
		event.merge({"target": "player", "source": slot, "hit": hit, "canceled": canceled})
		events.append(event)
		if int(state["player"]["hp"]) <= 0:
			if bool(state["spare_rope_available"]) and not bool(state["spare_rope_used"]):
				state["spare_rope_used"] = true
				state["player"]["hp"] = mini(int(state["player"]["max_hp"]), limit("spare_rope_hp", 1))
				# Rope prevents lethal loss; it is not a death followed by healing.
				event["hp_damage"] = maxi(0, hp_before - int(state["player"]["hp"]))
				event["prevented_lethal"] = true
				gain_guard(state, limit("spare_rope_guard", 10), events, "spare_rope")
				events.append({"type": "spare_rope"})
			else:
				state["status"] = "defeat"
				events.append({"type": "defeat"})
				return
		if guard_before > 0 and guard_after_damage == 0:
			Hooks.trigger(self, state, "guard_broken", {"target": slot}, events)
		if int(state["retaliate"]) > 0 and enemy_alive(state, slot):
			damage_enemy(state, slot, int(state["retaliate"]), {"source": "retaliate", "is_attack_card": false}, events)

func spawn_enemy(state: Dictionary, enemy_id: String, events: Array) -> int:
	if living_slots(state).size() >= limit("enemy_limit", 4):
		return -1
	var data: Dictionary = definition("enemies", enemy_id)
	if data.is_empty():
		return -1
	var reduction: float = minf(float(_balance.get("retry_enemy_hp_cap", 0.4)), int(state["retry_attempt"]) * float(_balance.get("retry_enemy_hp_step", 0.2)))
	var hp: int = maxi(1, int(ceil(int(data.get("hp", 1)) * (1.0 - reduction))))
	state["next_uid"] += 1
	var enemy: Dictionary = {"uid": "enemy_%d" % state["next_uid"], "id": enemy_id, "hp": hp, "max_hp": hp, "guard": 0, "cycle_index": 0, "guard_cycles": 0, "weaken": 0, "idle_override": false, "intent": {}, "phase_triggered": false, "phase_done": false, "first_attack_pending": bool(state["modifiers"].get("cancel_first_attack", state["modifiers"].get("first_attack_immune", false)))}
	var slot: int = state["enemies"].size()
	for index: int in range(state["enemies"].size()):
		if int(state["enemies"][index]["hp"]) == 0:
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
	if excluded.has(instance["uid"]):
		return "recursive_card_choice"
	var card: Dictionary = definition("cards", instance["id"])
	if card.is_empty():
		return "unknown_card"
	if card.has("uses_per_battle") and int(state["battle_flags"]["uses"].get(instance["id"], 0)) >= int(card["uses_per_battle"]):
		return "card_use_limit"
	if not free and card_cost(state, card) > int(state["energy"]):
		return "insufficient_energy"
	if card.get("target", "self") == "enemy":
		if not enemy_alive(state, target_index):
			return "invalid_target"
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
	for index: int in range(state["hand"].size()):
		for action: Dictionary in _card_actions(state, index, false, []):
			result.append(action)
	result.append({"type": "end_turn", "keep_index": -1})
	if has_item(state, "relics", "relic.bookmark"):
		for index: int in range(state["hand"].size()):
			result.append({"type": "end_turn", "keep_index": index})
	return result

func _card_actions(state: Dictionary, index: int, free: bool, excluded: Array) -> Array:
	var instance: Dictionary = state["hand"][index]
	if excluded.has(instance["uid"]):
		return []
	var card: Dictionary = definition("cards", instance["id"])
	if card.is_empty() or (not free and card_cost(state, card) > int(state["energy"])):
		return []
	if card.has("uses_per_battle") and int(state["battle_flags"]["uses"].get(instance["id"], 0)) >= int(card["uses_per_battle"]):
		return []
	var targets: Array = [-1]
	if card.get("target", "self") == "enemy":
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
				predicted_damage += int(intent.get("amount", 0)) * int(intent.get("times", 1))
		predicted_damage = maxi(0, predicted_damage - int(next["player"]["guard"]))
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

func _intent_views(state: Dictionary) -> Array:
	var result: Array = []
	var first_attacker: int = -1
	for slot: int in living_slots(state):
		var intent: Dictionary = Enemies.raw_intent(self, state, slot)
		intent["enemy"] = slot
		intent["id"] = state["enemies"][slot]["id"]
		if intent.get("type", "") == "attack":
			var reduction: int = int(state["enemies"][slot]["weaken"])
			if first_attacker == -1:
				first_attacker = slot
				if has_item(state, "keepsakes", "keepsake.mianmian"):
					reduction += int(param("keepsakes", "keepsake.mianmian", "reduction", 3))
			intent["raw_amount"] = int(intent.get("amount", 0))
			intent["amount"] = 0 if bool(state["enemies"][slot]["first_attack_pending"]) else maxi(0, int(intent.get("amount", 0)) - reduction)
			intent["times"] = int(intent.get("times", 1))
			intent["canceled"] = bool(state["enemies"][slot]["first_attack_pending"])
		result.append(intent)
	return result

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
