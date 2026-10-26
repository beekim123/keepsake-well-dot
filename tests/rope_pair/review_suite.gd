extends RefCounted
const Rules = preload("res://scripts/core/battle_rules.gd")
const Bot = preload("res://scripts/core/policy_bot.gd")
var passed: int = 0
var failures: Array = []
var rules: RefCounted
var defs: Dictionary
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failures.append(label)
func run(catalog: Node) -> Dictionary:
	defs = catalog.definitions()
	rules = Rules.new(defs)
	letter_orders()
	future_phase_actions()
	no_active_pairs()
	malformed_legacy_saves()
	return {"passed": passed, "failed": failures.size(), "failures": failures}
func letter_orders() -> void:
	for first: int in [0, 1]:
		var s: Dictionary = rules.start({"enemies": ["enemy.wet_sock", "enemy.lint_bug"]}, {"keepsakes": ["keepsake.letter"]}, 41)["state"]
		for enemy: Dictionary in s["enemies"]: enemy["hp"] = 1
		var energy: int = s["energy"]
		rules.use_keepsake(s, "keepsake.letter", first, {"second_target": 1 - first})
		check(s["status"] == "victory" and s["battle_flags"]["pairs"] == 1, "letter any-kind symmetric order %d" % first)
		check(s["energy"] == energy and s["enemies"][0]["departed"] == "paired" and s["enemies"][1]["departed"] == "paired", "letter both leave without energy cost %d" % first)
func future_phase_actions() -> void:
	for mode: String in ["due", "idle", "swap", "swap_idle", "before_due"]:
		var s: Dictionary = rules.start({"enemies": ["boss.sock_snake", "enemy.sock_kid"]}, {"hp": 1000, "max_hp": 1000}, 42)["state"]
		var delay: int = int(rules.definition("enemies", "boss.sock_snake")["mechanics"]["phase_warning_turns"])
		s["turn"] = delay if mode != "before_due" else delay - 1
		s["enemies"][0]["phase_triggered"] = true
		s["enemies"][0]["phase_first_response_turn"] = 1
		s["enemies"][0]["lookahead"] = 2
		s["enemies"][1]["lookahead"] = 2
		if mode in ["swap", "swap_idle"]:
			rules.tie_enemies(s, 0, 1, [])
			rules.apply_ops(s, [{"op": "swap_intent_with_partner"}], {"target": 0}, [])
		if mode == "idle": s["enemies"][0]["idle_override"] = true
		if mode == "swap_idle": s["enemies"][1]["idle_override"] = true
		var before: Dictionary = s.duplicate(true)
		var views: Array = rules.forecast(s)["intents"]
		check(s == before, "phase lookahead pure " + mode)
		for offset: int in range(2):
			rules.end_turn(s)
			for view: Dictionary in views:
				var slot: int = int(view["enemy"])
				var actual: Dictionary = rules.Enemies.raw_intent(rules, s, slot) if s["enemies"][slot]["uid"] == before["enemies"][slot]["uid"] else {"type": "defeated", "amount": 0}
				var expected: Dictionary = view["future_intents"][offset]
				check(expected == actual, "future action equals real continuation %s slot%d +%d" % [mode, slot, offset + 1])
func no_active_pairs() -> void:
	for nested: bool in [false, true]:
		var s: Dictionary = rules.start({"enemies": ["enemy.wet_sock", "enemy.wet_sock"]}, {"relics": ["relic.crooked_compass"]}, 43)["state"]
		for enemy: Dictionary in s["enemies"]:
			enemy["max_hp"] = 20
			enemy["hp"] = 14
			enemy["pair_threshold"] = 0.5
		s["hand"] = [rules.new_card(s, "card.one_pair")]
		if nested: s["hand"].push_front(rules.new_card(s, "card.deliver_plus"))
		var bot: RefCounted = Bot.new(defs)
		var action: Dictionary = bot.choose_action(s, rules, "no_pairs")
		check(action["type"] != "play_card", "no_pairs rejects active threshold via nested=%s" % str(nested))
		var explicit: Dictionary = {"type": "play_card", "hand_index": 0, "target_index": -1, "choices": {}}
		if nested: explicit["choices"] = {"other_uid": s["hand"][1]["uid"], "other_target_index": -1, "other_choices": {}}
		rules.apply_action(s, explicit)
		check(s["status"] == "victory", "fixture can actively pair via nested=%s" % str(nested))
func malformed_legacy_saves() -> void:
	var save: Node = load("res://scripts/services/save_service.gd").new()
	var bad_values: Array = [
		{"version": 1, "meta": {"returned": 0}, "run": {"keepsakes": ["keepsake.ring"], "wishes": {}}, "settings": {}},
		{"version": 1, "meta": {}, "run": {"keepsakes": ["keepsake.ring"], "wishes": []}, "settings": {}},
		{"version": 1, "meta": {}, "run": {"keepsakes": 7, "wishes": {}}, "settings": {}},
		{"version": 1, "meta": {}, "run": {"keepsakes": ["keepsake.ring"], "wishes": {"keepsake.ring": "yes"}}, "settings": {}}]
	for index: int in range(bad_values.size()):
		var old: Dictionary = bad_values[index]
		var snapshot: Dictionary = old.duplicate(true)
		check(save.migrate_state(old, defs) == snapshot and old == snapshot, "malformed legacy migration rejects without mutation %d" % index)
		var bytes: String = JSON.stringify(old)
		var file: FileAccess = FileAccess.open("user://d2-debug.json", FileAccess.WRITE)
		file.store_string(bytes)
		file.close()
		var result: Dictionary = save.load_state("user://d2-debug.json")
		check(not result["ok"] and result["error"] == "invalid_save" and result["recovered"], "malformed legacy load safely recovers %d" % index)
		var backup: String = str(result.get("backup", ""))
		check(not backup.is_empty() and FileAccess.file_exists(backup) and FileAccess.get_file_as_string(backup) == bytes, "malformed legacy original preserved in backup %d" % index)
	save.free()
