extends RefCounted
## Data-only tutorial scheduling. Damage, card costs, shields and enemy execution
## remain the ordinary battle engine's responsibility. No resources or scenes.

static func valid(rules: RefCounted, data: Dictionary) -> bool:
	if data.is_empty() or not data.get("enemy") is Dictionary or not data.get("player") is Dictionary:
		return false
	if not data.get("id") is String or not data.get("encounter_id") is String:
		return false
	if not data.get("deck") is Array or data["deck"].is_empty() or not data.get("turns") is Array or data["turns"].is_empty():
		return false
	if not data.get("prompts") is Dictionary or not data["enemy"].get("intents") is Array or data["enemy"]["intents"].is_empty():
		return false
	if rules.definition("enemies", str(data["enemy"].get("enemy_id", ""))).is_empty():
		return false
	if not _integer(data["enemy"].get("hp"), 1, 999) or not _integer(data["player"].get("hp"), 1, 999) or not _integer(data["player"].get("energy"), 1, 999):
		return false
	if data["deck"].size() > rules.limit("deck_limit", 12):
		return false
	for intent: Variant in data["enemy"]["intents"]:
		if not intent is Dictionary or not intent.get("type") is String or not intent.get("name") is String or not intent.get("type") in ["attack", "guard"] or not _integer(intent.get("amount"), 0, 999):
			return false
	var remaining: Array = data["deck"].duplicate()
	for card: Variant in remaining:
		if not card is String or rules.definition("cards", card).is_empty():
			return false
	for plan: Variant in data["turns"]:
		if not plan is Dictionary or not plan.get("hand") is Array or plan["hand"].is_empty():
			return false
		if plan["hand"].size() > rules.limit("hand_limit", 8) or not plan.get("force_first") is bool or not plan.get("end_requires_empty") is bool:
			return false
		for card: Variant in plan["hand"]:
			if not card is String or not remaining.has(card):
				return false
			remaining.erase(card)
		for key: String in ["prompt", "after_first_prompt", "empty_prompt"]:
			if plan.has(key) and not data["prompts"].has(plan[key]):
				return false
	for key: String in ["after_script_prompt", "victory_prompt", "defeat_prompt", "enemy_prompt"]:
		if not data["prompts"].has(data.get(key, "")):
			return false
	for prompt: Variant in data["prompts"].values():
		if not prompt is Dictionary or not prompt.get("text") is String or not prompt.get("guide") is String:
			return false
	return true

static func prepare_run(run: Dictionary, data: Dictionary) -> void:
	# A dedicated teaching encounter never inherits expedition hooks or penalties.
	run["hp"] = int(data["player"]["hp"])
	run["max_hp"] = int(data["player"]["hp"])
	run["deck"] = data["deck"].duplicate(true)
	run["relics"] = []
	run["keepsakes"] = []
	run["next_battle"] = {}
	run["spare_rope_available"] = false
	run["spare_rope_used"] = false

static func valid_saved_state(rules: RefCounted, value: Variant) -> bool:
	# Additional tutorial invariants, after the ordinary save/battle shape check.
	if not value is Dictionary or not _same(value.get("schema"), "battle/1") or not _same(value.get("status"), "player"):
		return false
	for key: String in ["tutorial", "player", "turn_flags", "battle_flags", "rng", "modifiers", "encounter", "start_snapshot"]:
		if not value.get(key) is Dictionary:
			return false
	for key: String in ["id", "locked_uid", "last_step"]:
		if not value["tutorial"].get(key) is String:
			return false
	var data: Dictionary = rules.definition("tutorial", value["tutorial"]["id"])
	if not valid(rules, data) or not _same(value["encounter"].get("tutorial_id"), data["id"]):
		return false
	if not _same(value["encounter"].get("id"), data["encounter_id"]) or not _same(value["encounter"].get("enemies"), data.get("enemies", [data["enemy"]["enemy_id"]])):
		return false
	if not _integer(value.get("turn"), 1, 1000000) or not _integer(value.get("energy"), 0, int(data["player"]["energy"])):
		return false
	if not _integer(value["turn_flags"].get("cards_played"), 0, 1000000):
		return false
	if not _integer(value["turn_flags"].get("special_played"), 0, 1000000) or not _integer(value["turn_flags"].get("first_attacker"), -1, rules.limit("enemy_limit", 4) - 1) or not value["turn_flags"].get("attack_played") is bool:
		return false
	if not _integer(value["battle_flags"].get("cards_played"), 0, 1000000) or not value["battle_flags"].get("uses") is Dictionary or not _same(value["battle_flags"].get("victory_pending"), false):
		return false
	for id: Variant in value["battle_flags"]["uses"]:
		if not id is String or not data["deck"].has(id) or not _integer(value["battle_flags"]["uses"][id], 0, 1000000):
			return false
	for key: String in ["seed", "next_uid", "next_turn_energy", "next_draw_penalty", "retaliate", "guard_multiplier", "retry_attempt", "resolution_depth"]:
		if not _integer(value.get(key), 0, 4294967295):
			return false
	if value["resolution_depth"] != 0 or value["next_uid"] != data["deck"].size() + data.get("enemies", [data["enemy"]["enemy_id"]]).size():
		return false
	for key: String in ["spare_rope_available", "spare_rope_used"]:
		if not value.get(key) is bool:
			return false
	for stream: String in ["shuffle", "battle"]:
		if not value["rng"].get(stream) is Dictionary:
			return false
		for key: String in ["seed", "state", "draws"]:
			if not _integer(value["rng"][stream].get(key), 0, 4294967295):
				return false
	for key: String in ["relics", "keepsakes"]:
		if not value.get(key) is Array or not value[key].is_empty():
			return false
	if not value["modifiers"].is_empty():
		return false
	if not _integer(value["player"].get("hp"), 1, int(data["player"]["hp"])) or not _same(value["player"].get("max_hp"), data["player"]["hp"]) or not _integer(value["player"].get("guard"), 0, 1000000):
		return false
	var remaining: Array = data["deck"].duplicate()
	var uids: Array = []
	for pile: String in ["hand", "draw_pile", "discard"]:
		if not value.get(pile) is Array:
			return false
		for card: Variant in value[pile]:
			if not card is Dictionary or not card.get("id") is String or not card.get("uid") is String:
				return false
			if not remaining.has(card["id"]) or uids.has(card["uid"]):
				return false
			remaining.erase(card["id"])
			uids.append(card["uid"])
	if not remaining.is_empty() or not value.get("enemies") is Array or value["enemies"].size() != data.get("enemies", [data["enemy"]["enemy_id"]]).size():
		return false
	for slot: int in range(value["enemies"].size()):
		var enemy: Variant = value["enemies"][slot]
		if not enemy is Dictionary or not _same(enemy.get("id"), data["enemy"]["enemy_id"]) or not _same(enemy.get("max_hp"), data["enemy"]["hp"]): return false
		if not _integer(enemy.get("hp"), 0, int(data["enemy"]["hp"])) or not _integer(enemy.get("binds"), 0, rules.limit("bind_cap", 12)): return false
		if not enemy.get("tie") is String or not enemy.get("departed") is String: return false
		if not _same(enemy.get("tutorial_intents"), data["enemy"]["intents"]): return false
		if not enemy.get("uid") is String or not enemy.get("intent") is Dictionary: return false
		for key: String in ["guard", "cycle_index", "guard_cycles", "weaken"]:
			if not _integer(enemy.get(key), 0, 1000000): return false
		for key: String in ["idle_override", "phase_triggered", "phase_done", "first_attack_pending"]:
			if not enemy.get(key) is bool: return false
	var expected_views: Array = rules._intent_views(value)
	for slot: int in range(value["enemies"].size()):
		if rules.enemy_alive(value, slot):
			var expected: Dictionary = {}
			for view: Dictionary in expected_views:
				if int(view["enemy"]) == slot: expected = view
			if not _same(value["enemies"][slot]["intent"], expected): return false
	var snapshot: Dictionary = value["start_snapshot"]
	if not snapshot.get("run") is Dictionary or not snapshot.get("encounter") is Dictionary or not _integer(snapshot.get("seed"), 0, 4294967295):
		return false
	if not _same(snapshot["encounter"].get("tutorial_id"), data["id"]) or not _same(snapshot["run"].get("deck"), data["deck"]):
		return false
	if not _same(snapshot["encounter"].get("id"), data["encounter_id"]) or not _same(snapshot["encounter"].get("enemies"), data.get("enemies", [data["enemy"]["enemy_id"]])):
		return false
	var plan: Dictionary = plan_for(data, int(value["turn"]))
	var locked: String = value["tutorial"]["locked_uid"]
	var must_lock: bool = bool(plan.get("force_first", false)) and int(value["turn_flags"]["cards_played"]) == 0
	if must_lock:
		var locked_index: int = rules.find_card(value["hand"], locked)
		if locked_index < 0 or value["hand"][locked_index]["id"] != plan["hand"][0]:
			return false
	elif not locked.is_empty():
		return false
	return true

# Godot cannot compare unrelated Variant types (Array != String raises).
# Save validation must reject those inputs, not throw then return default false.
static func _same(value: Variant, expected: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return false
	if (value is int or value is float) and (expected is int or expected is float):
		return is_finite(float(value)) and float(value) == float(expected)
	if typeof(value) != typeof(expected):
		return false
	if expected is Dictionary:
		if value.size() != expected.size():
			return false
		for key: Variant in expected:
			if not value.has(key) or not _same(value[key], expected[key], depth + 1):
				return false
		return true
	if expected is Array:
		if value.size() != expected.size():
			return false
		for index: int in range(expected.size()):
			if not _same(value[index], expected[index], depth + 1):
				return false
		return true
	return value == expected

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func plan_for(data: Dictionary, turn: int) -> Dictionary:
	var plans: Array = data.get("turns", [])
	return plans[turn - 1] if turn > 0 and turn <= plans.size() else {}

static func prepare_draw(state: Dictionary, data: Dictionary, fallback: int) -> int:
	var plan: Dictionary = plan_for(data, int(state["turn"]))
	if plan.is_empty():
		return fallback
	# Reorder existing instances only. The three scripted hands consume nine of
	# the existing ten starters; optional actions never create or erase cards.
	var ordered: Array = []
	for id: String in plan["hand"]:
		for index: int in range(state["draw_pile"].size()):
			if state["draw_pile"][index]["id"] == id:
				ordered.append(state["draw_pile"][index])
				state["draw_pile"].remove_at(index)
				break
	state["draw_pile"] = ordered + state["draw_pile"]
	return ordered.size()

static func after_draw(state: Dictionary, data: Dictionary) -> void:
	var plan: Dictionary = plan_for(data, int(state["turn"]))
	state["tutorial"]["locked_uid"] = ""
	if bool(plan.get("force_first", false)):
		for card: Dictionary in state["hand"]:
			if card["id"] == plan["hand"][0]:
				state["tutorial"]["locked_uid"] = card["uid"]
				break

static func status(state: Dictionary, data: Dictionary) -> Dictionary:
	if data.is_empty() or not state.has("tutorial"):
		return {"active": false, "step": "", "prompt_id": "", "text": "", "guide": "none", "allowed_card_uid": "", "can_end_turn": state.get("status", "") == "player", "show_shield": false, "completed": false}
	var plan: Dictionary = plan_for(data, int(state["turn"]))
	var locked: String = str(state["tutorial"].get("locked_uid", ""))
	var prompt: String = str(plan.get("prompt", data["after_script_prompt"]))
	if state["status"] == "victory":
		prompt = str(data["victory_prompt"])
	elif state["status"] == "defeat":
		prompt = str(data["defeat_prompt"])
	elif state["hand"].is_empty() and plan.has("empty_prompt"):
		prompt = str(plan["empty_prompt"])
	elif locked.is_empty() and plan.has("after_first_prompt"):
		prompt = str(plan["after_first_prompt"])
	var result: Dictionary = data["prompts"].get(prompt, {}).duplicate(true)
	result.merge({"active": true, "step": "%d:%s" % [int(state["turn"]), prompt], "prompt_id": str(data["id"]) + "." + prompt,
		"allowed_card_uid": locked, "can_end_turn": state["status"] == "player" and locked.is_empty() and (not bool(plan.get("end_requires_empty", false)) or state["hand"].is_empty()),
		"show_shield": false, "completed": state["status"] == "victory"}, true)
	return result

static func update_prompt(state: Dictionary, data: Dictionary, events: Array) -> void:
	var result: Dictionary = status(state, data)
	if not result["active"] or result["step"] == state["tutorial"].get("last_step", ""):
		return
	state["tutorial"]["last_step"] = result["step"]
	result["type"] = "tutorial_prompt"
	events.append(result)
