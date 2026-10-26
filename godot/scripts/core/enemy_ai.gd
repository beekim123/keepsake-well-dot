class_name EnemyAI
extends RefCounted
## Fixed cycles plus live swallow/boss phase intent; no hidden global randomness.
static func raw_intent(rules: RefCounted, state: Dictionary, slot: int, offset: int = 0) -> Dictionary:
	var enemy: Dictionary = state["enemies"][slot]
	if int(enemy["hp"]) <= 0:
		return {"type": "defeated", "amount": 0}
	var definition: Dictionary = rules.definition("enemies", enemy["id"])
	var mechanics: Dictionary = definition.get("mechanics", {})
	var phase_due: bool = bool(enemy.get("phase_triggered", false)) and not bool(enemy.get("phase_done", false)) and int(state["turn"]) + offset >= int(enemy.get("phase_first_response_turn", 999999)) + int(mechanics.get("phase_warning_turns", 2)) - 1
	if offset == 0 and bool(enemy.get("idle_override", false)):
		return {"type": "idle", "amount": 0, "phase_attack": phase_due}
	if phase_due:
		return {"type": "attack", "amount": int(mechanics.get("phase_damage", 16)), "times": 1, "phase_attack": true, "name": "大缠绕"}
	var intents: Array = definition.get("intents", [{"type": "idle", "amount": 0}])
	if intents.is_empty():
		return {"type": "idle", "amount": 0}
	var result: Dictionary = intents[(int(enemy["cycle_index"]) + offset) % intents.size()].duplicate(true)
	if result.has("growth"):
		result["amount"] = int(result.get("amount", 0)) + int(result["growth"]) * int(enemy.get("guard_cycles", 0))
	if result.get("type", "") == "consume_minion":
		var minion_id: String = str(result.get("enemy_id", mechanics.get("summon_enemy_id", "enemy.sock_kid")))
		if rules.minion_slots(state, minion_id).is_empty():
			result = {"type": "attack", "amount": int(result.get("fallback_damage", 10)), "times": 1, "swallow_fallback": true, "name": "吞袜扑空"}
	return result

static func execute(rules: RefCounted, state: Dictionary, slot: int, events: Array) -> void:
	var enemy: Dictionary = state["enemies"][slot]
	var intent: Dictionary = raw_intent(rules, state, slot)
	events.append({"type": "enemy_action", "enemy": slot, "intent": intent.duplicate(true)})
	match str(intent.get("type", "idle")):
		"attack":
			rules.enemy_attack(state, slot, intent, events)
			if state["status"] != "defeat" and rules.enemy_alive(state, slot):
				if int(intent.get("guard", 0)) > 0:
					rules.enemy_guard(state, slot, int(intent["guard"]), events)
				state["next_draw_penalty"] += int(intent.get("draw_penalty", 0))
		"guard":
			rules.enemy_guard(state, slot, int(intent.get("amount", 0)), events)
			if intent.has("growth"):
				enemy["guard_cycles"] += 1
		"guard_all":
			for target: int in rules.living_slots(state):
				rules.enemy_guard(state, target, int(intent.get("amount", 0)), events)
		"consume_minion":
			var definition: Dictionary = rules.definition("enemies", enemy["id"])
			var minions: Array = rules.minion_slots(state, str(intent.get("enemy_id", definition.get("mechanics", {}).get("summon_enemy_id", "enemy.sock_kid"))))
			if not minions.is_empty():
				var consumed: int = minions[0]
				state["enemies"][consumed]["hp"] = 0
				state["enemies"][consumed]["guard"] = 0
				var actual: int = mini(int(intent.get("heal", 0)), int(enemy["max_hp"]) - int(enemy["hp"]))
				enemy["hp"] += actual
				events.append({"type": "consume", "enemy": slot, "consumed": consumed, "heal": actual})
	if bool(intent.get("phase_attack", false)):
		enemy["phase_done"] = true
	else:
		enemy["cycle_index"] += 1
	enemy["idle_override"] = false

static func turn_start(rules: RefCounted, state: Dictionary, events: Array) -> void:
	for slot: int in rules.living_slots(state):
		state["enemies"][slot]["guard"] = 0
	for slot: int in rules.living_slots(state):
		var definition: Dictionary = rules.definition("enemies", state["enemies"][slot]["id"])
		var mechanics: Dictionary = definition.get("mechanics", {})
		if mechanics.has("guard_per_minion"):
			rules.enemy_guard(state, slot, rules.minion_slots(state, str(mechanics.get("summon_enemy_id", "enemy.sock_kid"))).size() * int(mechanics["guard_per_minion"]), events)

static func turn_end(rules: RefCounted, state: Dictionary, events: Array) -> void:
	# Snapshot actors so newborn minions never act on the turn they appear.
	for slot: int in rules.living_slots(state):
		var definition: Dictionary = rules.definition("enemies", state["enemies"][slot]["id"])
		var mechanics: Dictionary = definition.get("mechanics", {})
		if not mechanics.has("summon_enemy_id"):
			continue
		for count: int in range(int(mechanics.get("summon_per_turn", 1))):
			var minions: Array = rules.minion_slots(state, str(mechanics["summon_enemy_id"]))
			if rules.living_slots(state).size() >= rules.limit("enemy_limit", 4) or minions.size() >= int(mechanics.get("max_minions", 3)):
				rules.enemy_guard(state, slot, int(mechanics.get("full_board_guard", 3)), events)
			else:
				rules.spawn_enemy(state, str(mechanics["summon_enemy_id"]), events)
