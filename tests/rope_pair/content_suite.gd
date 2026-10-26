extends RefCounted
const Rules = preload("res://scripts/core/battle_rules.gd")
const RunRules = preload("res://scripts/core/run_rules.gd")

var passed: int = 0
var failures: Array = []
var defs: Dictionary
var rules: RefCounted
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failures.append(label)
var _catalog: Node
func run(catalog: Node, tables: Dictionary = {}) -> Dictionary:
	_catalog = catalog
	defs = _catalog.definitions() if tables.is_empty() else tables
	rules = Rules.new(defs)
	check(_catalog.valid, "content unique IDs")
	var starter: Array = defs["meta"][0]["starter_deck"]
	check(starter.count("card.bind") == 3 and starter.count("card.tie") == 2 and not starter.has("card.brace"), "new starter deck")
	check(defs["cards"].filter(func(c: Dictionary) -> bool: return c.get("pool", "") == "reward").size() == 16, "sixteen reward cards")
	check(rules.has_method("use_keepsake"), "active keepsake API")
	if rules.has_method("use_keepsake"): active_tests()
	var run_rules: RefCounted = RunRules.new(defs)
	var meta: Dictionary = run_rules.new_meta()
	var run: Dictionary = run_rules.start_run(meta, ["keepsake.ring"], 42)["run"]
	run_rules.choose_path(run, 0)
	var s: Dictionary = run_rules.start_battle(run, rules)["state"]
	for enemy: Dictionary in s["enemies"]: enemy["departed"] = "paired"
	s["battle_flags"]["pairs"] = 1
	s["status"] = "victory"
	var completed: Array = run_rules.complete_battle(run, meta, s, [{"type": "victory"}])
	check(completed[0].get("type", "") != "invalid", "paired hp accepted by run bridge")
	if run["phase"] == "reward":
		check(run["rewards"].size() == 3 and run["rewards"][0]["kind"] == "card", "normal reward three cards")
		run_rules.choose_reward(run, -1)
		check(run["phase"] == "reward" and run["rewards"].size() == 2 and run["rewards"][0]["kind"] == "relic", "skip card preserves thanks reward")
		if run["phase"] == "reward":
			run_rules.choose_reward(run, 0)
			check(run["phase"] == "path" and run["segment"] == 2, "thanks choice advances once")
	boss_swap_test()
	relic_and_tutorial_tests()
	validate_references(defs)
	card_combo_tests()
	replay_and_reuse_tests()
	var save: Node = load("res://scripts/services/save_service.gd").new()
	check(save.SAVE_VERSION == 2, "save version two")
	check(save.has_method("migrate_state"), "migration API exists")
	if save.has_method("migrate_state"):
		var old_meta: Dictionary = run_rules.new_meta()
		old_meta["runs_started"] = 3
		old_meta["once_events"]["old_flag"] = true
		var old: Dictionary = {"version": 1, "meta": old_meta, "settings": {"tutorial_complete": true}, "run": {"keepsakes": ["keepsake.ring"], "wishes": {"keepsake.ring": true}}}
		var migrated: Dictionary = save.migrate_state(old, defs)
		check(migrated["version"] == 2 and migrated["run"] == null, "migration ends old trip")
		check(migrated["meta"]["once_events"]["old_flag"] and migrated["meta"]["runs_started"] == 3, "migration preserves permanent progress")
		check("keepsake.ring" in migrated["meta"]["returned"] and "card.vow_plus" in migrated["meta"]["replica_cards"], "migration returns acquired keepsakes with wishes")
		check(not migrated["settings"].get("tutorial_complete", false), "migration resets tutorial checkpoint")
		check(old["version"] == 1 and old["meta"]["returned"].is_empty(), "migration pure")
	var disk_state: Dictionary = save.default_state()
	disk_state["version"] = 1
	disk_state["meta"] = run_rules.new_meta()
	disk_state["meta"]["runs_started"] = 2
	var file: FileAccess = FileAccess.open("user://d2-debug.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(disk_state))
	file.close()
	var loaded: Dictionary = save.load_state("user://d2-debug.json")
	check(loaded["ok"] and loaded["state"]["version"] == 2 and loaded["state"]["meta"]["runs_started"] == 2, "old save actual disk load migrates")
	check(save.save_state(loaded["state"], "user://d2-debug.json") == OK, "migrated save writes safely to debug path")
	check(save.load_state("user://d2-debug.json")["ok"], "new save reloads")
	var first_meta: Dictionary = run_rules.new_meta()
	var first: Dictionary = run_rules.start_first_run(first_meta, 66)["run"]
	run_rules.choose_path(first, 0)
	var teaching: Dictionary = run_rules.start_battle(first, rules)["state"]
	for enemy: Dictionary in teaching["enemies"]: enemy["departed"] = "paired"
	teaching["battle_flags"]["pairs"] = 1
	teaching["status"] = "victory"
	run_rules.complete_battle(first, first_meta, teaching, [{"type": "victory"}])
	var checkpoint: Dictionary = run_rules.safe_checkpoint(first, first_meta)
	var saved: Dictionary = save.default_state()
	saved["meta"] = checkpoint["meta"]
	saved["run"] = checkpoint["run"]
	check(save.save_state(saved, "user://d2-debug.json") == OK, "first route card reward with queued thanks saves")
	run_rules.choose_reward(first, -1)
	checkpoint = run_rules.safe_checkpoint(first, first_meta)
	saved["run"] = checkpoint["run"]
	check(first.get("reward_kind", "") == "thanks", "reward kind persists thanks stage")
	check(save.save_state(saved, "user://d2-debug.json") == OK, "first route thanks saves")
	var restored: Dictionary = save.load_state("user://d2-debug.json")
	check(restored["ok"] and restored["state"]["run"].get("reward_kind", "") == "thanks", "first route thanks restored with title kind")
	save.free()
	return {"passed": passed, "failed": failures.size(), "failures": failures}
func active_tests() -> void:
	var s: Dictionary = rules.start({"enemies": ["enemy.wet_sock", "enemy.lint_bug"]}, {"keepsakes": ["keepsake.ring", "keepsake.mianmian", "keepsake.letter"]}, 77)["state"]
	rules.tie_enemies(s, 0, 1, [])
	rules.apply_ops(s, [{"op": "swap_intent_with_partner"}], {"target": 0}, [])
	var energy: int = s["energy"]
	rules.use_keepsake(s, "keepsake.ring")
	check(s["enemies"][0]["binds"] == _op_amount("keepsakes", "keepsake.ring", "bind_all") and s["enemies"][1]["binds"] == _op_amount("keepsakes", "keepsake.ring", "bind_all") and s["energy"] == energy, "ring zero cost binds all")
	check(rules.use_keepsake(s, "keepsake.ring")[0].get("type") == "invalid_action", "ring once per battle")
	rules.use_keepsake(s, "keepsake.mianmian", 0)
	check(rules.forecast(s)["intents"][0]["type"] == "idle", "mianmian idles selected attack")
	s["enemies"][0]["hp"] = 1
	s["enemies"][1]["hp"] = 1
	rules.use_keepsake(s, "keepsake.letter", 0, {"second_target": 1})
	check(s["status"] == "victory" and s["battle_flags"]["pairs"] == 1, "letter immediately pairs wilted different kinds")

func boss_swap_test() -> void:
	var s: Dictionary = rules.start({"enemies": ["boss.sock_snake", "enemy.sock_kid"]}, {}, 44)["state"]
	s["turn"] = 1 + int(rules.definition("enemies", "boss.sock_snake")["mechanics"]["phase_warning_turns"])
	s["enemies"][0]["phase_triggered"] = true
	s["enemies"][0]["phase_first_response_turn"] = 2
	rules.tie_enemies(s, 0, 1, [])
	rules.apply_ops(s, [{"op": "swap_intent_with_partner"}], {"target": 0}, [])
	rules.end_turn(s)
	check(s["enemies"][0]["phase_done"], "swapped phase attack consumes boss once-only phase")
	check(not rules.Enemies.raw_intent(rules, s, 0).get("phase_attack", false), "boss does not repeat swapped phase next turn")

func validate_references(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value:
			if not key in ["art", "portrait"]: validate_references(value[key])
	elif value is Array:
		for child: Variant in value: validate_references(child)
	elif value is String:
		for prefix: String in ["card.", "enemy.", "elite.", "boss.", "relic.", "keepsake.", "enc.", "tutorial.", "ui.", "story."]:
			if value.begins_with(prefix):
				check(_catalog.has_entry(value), "content reference " + value)
				break

func battle(relics: Array = [], enemy_ids: Array = ["enemy.wet_sock", "enemy.wet_sock"]) -> Dictionary:
	return rules.start({"enemies": enemy_ids}, {"relics": relics}, 123)["state"]
func relic_and_tutorial_tests() -> void:
	var s: Dictionary = battle(["relic.open_ink"])
	check(s["hand"].size() == int(rules.definition("relics", "relic.open_ink")["rules"]["hand_size"]), "ink configured refill")
	s = battle(["relic.empty_frame"])
	check(rules.forecast(s)["intents"][0]["type"] == "idle" and rules.forecast(s)["intents"][1]["type"] == "attack", "frame idles only leftmost")
	s = battle(["relic.crooked_compass"])
	check(rules.partner_slot(s, 0) == 1, "compass auto ties matching pair")
	s = battle(["relic.spyglass"])
	check(rules.forecast(s)["intents"][0]["future_intents"].size() == 1, "spyglass public lookahead")
	s = battle(["relic.lost_kite"])
	rules.tie_enemies(s, 0, 1, [])
	check(s["enemies"][0]["hp"] == int(s["enemies"][0]["max_hp"]) - _op_amount("relics", "relic.lost_kite", "damage_both") and s["enemies"][1]["hp"] == int(s["enemies"][1]["max_hp"]) - _op_amount("relics", "relic.lost_kite", "damage_both"), "kite configured damage on both ends without propagation")
	s = battle(["relic.leaky_balloon"])
	rules.bind_enemy(s, 0, 7, [])
	rules.shake_off(s, 0, "all", [])
	check(s["enemies"][0]["binds"] == 4, "balloon limits full escape to floor half")
	s = battle(["relic.bookmark"])
	rules.shake_card(s, 0)
	check(s["hand"].size() == mini(int(defs["balance"][0]["hand_limit"]), int(defs["balance"][0]["hand_size"]) + _op_amount("relics", "relic.bookmark", "draw")), "bookmark first shake extra draw")
	s = battle(["relic.shedding_brush"])
	rules.bind_enemy(s, 0, 1, [])
	rules.damage_enemy(s, 0, 5, {"source": "card.knock", "is_attack_card": true}, [])
	check(s["enemies"][0]["hp"] == maxi(0, int(s["enemies"][0]["max_hp"]) - 5 - int(rules.definition("relics", "relic.shedding_brush")["rules"]["bound_attack_bonus"])), "brush configured bound attack bonus")
	s = battle(["relic.odd_button"], ["enemy.wet_sock"])
	rules.damage_enemy(s, 0, 5, {"source": "card.knock", "is_attack_card": true}, [])
	check(s["enemies"][0]["hp"] == maxi(0, int(s["enemies"][0]["max_hp"]) - 5 - int(rules.definition("relics", "relic.odd_button")["rules"]["lone_attack_bonus"])), "button configured lone attack bonus")
	s = battle(["relic.tangled_earbuds"])
	s["hand"] = [rules.new_card(s, "card.tie"), rules.new_card(s, "card.tie")]
	s["energy"] = 10
	rules.play_card(s, 0, 0, {"second_target": 1})
	check(s["energy"] == 10 and rules.card_cost(s, rules.definition("cards", "card.tie")) == int(rules.definition("cards", "card.tie")["cost"]), "earbuds only first tie free")
	var ball_damage: int = int(rules.definition("relics", "relic.flat_ball")["rules"]["scattered_partner_damage"])
	var linked_loss: int = int(floor(12 * float(defs["balance"][0]["link_ratio"])))
	for armored: bool in [false, true]:
		s = battle(["relic.flat_ball"])
		_set_enemy_hp(s, 0, 12)
		_set_enemy_hp(s, 1, 100)
		rules.tie_enemies(s, 0, 1, [])
		if armored: s["enemies"][1]["guard"] = ball_damage + 3
		rules.damage_enemy(s, 0, 12, {"source": "card.knock", "is_attack_card": true}, [])
		check(s["enemies"][1]["hp"] == 100 - linked_loss - (0 if armored else ball_damage), "ball configured damage and direct linked HP loss armored=%s" % str(armored))
		if armored: check(s["enemies"][1]["guard"] == 3, "ball ordinary damage consumes armor")
	s = battle(["relic.lone_glove", "relic.half_biscuit"])
	s["hand"] = []
	s["player"]["hp"] = 10
	s["player"]["max_hp"] = 100
	var pair_energy: int = s["energy"]
	s["enemies"][0]["hp"] = 1
	s["enemies"][1]["hp"] = 1
	rules.tie_enemies(s, 0, 1, [])
	rules.check_pairs(s, [])
	check(s["hand"].size() == _op_amount("relics", "relic.lone_glove", "draw") and s["energy"] == pair_energy + _op_amount("relics", "relic.lone_glove", "gain_energy") and s["player"]["hp"] == 10 + _op_amount("relics", "relic.half_biscuit", "heal"), "glove and biscuit pair hooks")
	rules.check_pairs(s, [])
	check(s["energy"] == pair_energy + _op_amount("relics", "relic.lone_glove", "gain_energy") and s["player"]["hp"] == 10 + _op_amount("relics", "relic.half_biscuit", "heal"), "pair hooks once per formed pair")
	s = battle(["relic.offkey_harmonica"])
	s["energy"] = 2
	var hp_before: int = s["player"]["hp"]
	var attack: Dictionary = rules.definition("enemies", "enemy.wet_sock")["intents"][0]
	var pressure: int = int(attack["amount"]) * int(attack.get("times", 1))
	var bound: int = mini(int(defs["balance"][0]["bind_cap"]), 2 * _op_amount("relics", "relic.offkey_harmonica", "bind_threat"))
	rules.end_turn(s)
	check(s["player"]["hp"] == hp_before - pressure - maxi(0, pressure - bound), "harmonica configured leftover-energy threat reduction")
	s = battle([], ["boss.sock_snake", "enemy.sock_kid"])
	s["enemies"][0]["hp"] = int(ceil(int(s["enemies"][0]["max_hp"]) * float(rules.definition("enemies", "boss.sock_snake")["mechanics"]["peace_threshold"])))
	s["hand"] = [rules.new_card(s, "card.tie")]
	rules.play_card(s, 0, 0, {"second_target": 1})
	check(s["status"] == "victory" and s["battle_flags"].get("peaceful", false), "boss thirty percent peaceful victory")
	s = battle([], ["enemy.sock_kid", "enemy.sock_kid"])
	s["hand"] = [rules.new_card(s, "card.tie")]
	rules.play_card(s, 0, 0, {"second_target": 1})
	check(s["status"] == "victory", "full health kids pair immediately")
	s = rules.start_tutorial({}, 17)["state"]
	check(not s.is_empty() and rules.tutorial_status(s)["allowed_card_uid"] != "", "tutorial starts locked knock")
	check(rules.end_turn(s)[0].get("type") == "invalid_action", "tutorial force first before ending")
	rules.play_card(s, 0, 0)
	rules.end_turn(s)
	check(s["turn"] == 2 and s["hand"][0]["id"] == "card.bind", "tutorial second turn bind")
	rules.play_card(s, 0, 0)
	check(rules.forecast(s)["damage"] == maxi(0, int(rules.definition("tutorial", "tutorial.wet_sock")["enemy"]["intents"][1]["amount"]) - _op_amount("cards", "card.bind", "bind")), "tutorial configured bind reduces published attack")
	check(rules.is_tutorial_state_valid(s), "new bound tutorial checkpoint valid")
	var corrupt: Dictionary = s.duplicate(true)
	corrupt["enemies"][0].erase("binds")
	check(not rules.is_tutorial_state_valid(corrupt), "tutorial rejects missing new bind field")
	_finish_tutorial_turn(s)
	check(s["turn"] == 3 and rules.forecast(s)["intents"][0].get("shake_off", "") == "all", "tutorial third turn visible escape")
	s = rules.start_tutorial({}, 17, "tutorial.pair")["state"]
	check(s["enemies"].size() == 2 and s["hand"][0]["id"] == "card.tie", "pair tutorial two enemies and forced tie")
	rules.play_card(s, 0, 0, {"second_target": 1})
	rules.play_card(s, 0, 0)
	rules.play_card(s, 0, 1)
	check(s["status"] == "victory" and s["battle_flags"]["pairs"] == 1, "pair tutorial real tie damage and victory")

func card_combo_tests() -> void:
	var s: Dictionary = battle([], ["enemy.lonely_sock"])
	rules.bind_enemy(s, 0, 1, [])
	s["hand"] = [rules.new_card(s, "card.double_tap")]
	rules.play_card(s, 0, 0)
	check(s["enemies"][0]["hp"] == maxi(0, int(s["enemies"][0]["max_hp"]) - _op_amount("cards", "card.double_tap", "damage") * int(_op("cards", "card.double_tap", "damage").get("times", 1)) - _op_amount("cards", "card.double_tap", "bonus_hit_if_bound")), "bound double tap configured hits plus bonus")
	s = battle([], ["enemy.wet_sock"])
	s["hand"] = [rules.new_card(s, "card.dust_off")]
	rules.play_card(s, 0, 0)
	check(s["enemies"][0]["hp"] == maxi(0, int(s["enemies"][0]["max_hp"]) - _op_amount("cards", "card.dust_off", "damage_if_wilted")), "dust off configured healthy damage")
	_set_enemy_hp(s, 0, 100)
	s["enemies"][0]["hp"] = 50
	s["enemies"][0]["pair_threshold"] = 0.5
	s["hand"] = [rules.new_card(s, "card.dust_off")]
	rules.play_card(s, 0, 0)
	check(s["enemies"][0]["hp"] == 50 - int(_op("cards", "card.dust_off", "damage_if_wilted")["wilted_amount"]), "dust off configured wilted damage")
	s = battle()
	s["hand"] = [rules.new_card(s, "card.whisper_plus")]
	rules.play_card(s, 0, 0)
	check(s["enemies"][0]["binds"] == mini(int(defs["balance"][0]["bind_cap"]), _op_amount("cards", "card.whisper_plus", "bind")) and rules.forecast(s)["intents"][0]["future_intents"].size() == _op_amount("cards", "card.whisper_plus", "reveal_intents"), "whisper plus configured bind and lookahead")
	s = battle()
	for slot: int in [0, 1]:
		_set_enemy_hp(s, slot, 100)
		s["enemies"][slot]["pair_threshold"] = 0.5
		s["enemies"][slot]["hp"] = int(floor(100 * float(_op("cards", "card.deliver", "free_play_other")["pair_threshold"])))
	s["energy"] = 10
	s["hand"] = [rules.new_card(s, "card.deliver"), rules.new_card(s, "card.tie")]
	rules.play_card(s, 0, -1, {"other_uid": s["hand"][1]["uid"], "other_target_index": 0, "other_choices": {"second_target": 1}})
	check(s["status"] == "victory" and s["energy"] == 10 - int(rules.definition("cards", "card.deliver")["cost"]), "deliver free tie configured threshold")
	s = rules.start({"enemies": ["enemy.wet_sock", "enemy.lint_bug"]}, {"keepsakes": ["keepsake.letter"]}, 12)["state"]
	rules.use_keepsake(s, "keepsake.letter", 0, {"second_target": 1})
	s["enemies"][0]["hp"] = 1
	s["enemies"][1]["hp"] = 1
	rules.check_pairs(s, [])
	check(s["battle_flags"]["pairs"] == 0, "letter any-kind pair exception only immediate")

func replay_and_reuse_tests() -> void:
	var s: Dictionary = battle(["relic.lone_glove"])
	for slot: int in [0, 1]:
		_set_enemy_hp(s, slot, 100)
		s["enemies"][slot]["pair_threshold"] = 0.5
		s["enemies"][slot]["hp"] = int(floor(100 * float(_op("cards", "card.deliver", "free_play_other")["pair_threshold"])))
	s["energy"] = 10
	s["hand"] = [rules.new_card(s, "card.deliver"), rules.new_card(s, "card.deliver_plus"), rules.new_card(s, "card.tie")]
	var choices: Dictionary = {"other_uid": s["hand"][1]["uid"], "other_target_index": -1, "other_choices": {"other_uid": s["hand"][2]["uid"], "other_target_index": 0, "other_choices": {"second_target": 1}}}
	var snapshot: Dictionary = s.duplicate(true)
	var preview: Dictionary = rules.preview(s, 0, -1, choices)
	check(s == snapshot, "nested deliver preview leaves source and RNG untouched")
	var events: Array = rules.play_card(s, 0, -1, choices)
	check(events == preview["events"] and s == preview["state"], "nested dual target delivery preview equals live state and events")
	check(s["status"] == "victory" and s["battle_flags"]["cards_played"] == 3, "nested deliver resolves three cards and pair")
	s = battle()
	s["discard"] = s["draw_pile"] + s["hand"]
	s["draw_pile"] = []
	s["hand"] = []
	var copy: Dictionary = s.duplicate(true)
	var first_events: Array = []
	var second_events: Array = []
	var draws: int = s["rng"]["shuffle"]["draws"]
	rules.draw(s, 7, first_events)
	rules.draw(copy, 7, second_events)
	check(s == copy and first_events == second_events and int(s["rng"]["shuffle"]["draws"]) > draws, "discard reshuffle deterministic state events and RNG advancement")
	s = battle([], ["enemy.wet_sock", "enemy.wet_sock", "enemy.lint_bug"])
	var old_uid: String = s["enemies"][0]["uid"]
	s["enemies"][0]["hp"] = 1
	s["enemies"][1]["hp"] = 1
	s["hand"] = [rules.new_card(s, "card.tie")]
	rules.play_card(s, 0, 0, {"second_target": 1})
	var slot: int = rules.spawn_enemy(s, "enemy.lint_bug", [])
	check(slot == 0 and s["enemies"][0]["uid"] != old_uid and rules.partner_slot(s, 0) == -1, "paired slot reuse has fresh UID and no old link")
	rules.damage_enemy(s, 0, 3, {"source": "card.knock", "is_attack_card": true}, [])
	check(s["enemies"][1]["hp"] == 1, "reused slot does not damage departed old partner")
	s["hand"] = [rules.new_card(s, "card.tie")]
	var before: Dictionary = s.duplicate(true)
	var invalid: Array = rules.play_card(s, 0, 0, {"second_target": 1})
	check(invalid[0].get("reason", "") == "invalid_second_target" and s == before, "departed second target rejected without mutation")
	var Bot = preload("res://scripts/core/policy_bot.gd")
	var left: Dictionary = battle()
	var right: Dictionary = battle()
	var a: RefCounted = Bot.new(defs)
	var b: RefCounted = Bot.new(defs)
	var left_log: Array = []
	var right_log: Array = []
	for step: int in range(50):
		if left["status"] != "player": break
		left_log.append_array(rules.apply_action(left, a.choose_action(left, rules)))
		if right["status"] == "player": right_log.append_array(rules.apply_action(right, b.choose_action(right, rules)))
	check(left["status"] != "player" and left == right and left_log == right_log, "full same-seed battle replay identical terminal state and events")

func _op(category: String, id: String, name: String) -> Dictionary:
	for op: Dictionary in rules.definition(category, id).get("ops", []):
		if op.get("op", "") == name: return op
	check(false, "required configured operation " + id + ":" + name)
	return {}
func _op_amount(category: String, id: String, name: String) -> int:
	return int(_op(category, id, name).get("amount", 0))
func _set_enemy_hp(state: Dictionary, slot: int, maximum: int) -> void:
	# Explicit local fixture for damage arithmetic; never changes shipped content.
	state["enemies"][slot]["max_hp"] = maximum
	state["enemies"][slot]["hp"] = maximum

func _finish_tutorial_turn(state: Dictionary) -> void:
	# Honor the data plan's forced remainder (e.g. two binds), not a fixed hand count.
	for step: int in range(10):
		if rules.tutorial_status(state)["can_end_turn"]:
			rules.end_turn(state)
			return
		var played: bool = false
		for action: Dictionary in rules.legal_actions(state):
			if action["type"] == "play_card":
				rules.apply_action(state, action)
				played = true
				break
		if not played: break
	check(false, "tutorial scripted remainder can complete before end turn")
