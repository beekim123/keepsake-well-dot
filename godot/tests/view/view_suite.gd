extends RefCounted
## Integration uses real public rules and the actual app controls, never force-wins.
const Bot = preload("res://scripts/core/policy_bot.gd")
const Story = preload("res://scripts/story/story_player.gd")
var passed: int = 0
var failed: int = 0
var tree: SceneTree
var app: Control
var saves: Node
var catalog: Node
var bot: RefCounted

func run_suite(scene_tree: SceneTree) -> Dictionary:
	tree = scene_tree
	saves = tree.root.get_node("SaveService")
	catalog = tree.root.get_node("ContentCatalog")
	bot = Bot.new(catalog.definitions())
	_test_save()
	_test_story()
	_check(catalog.format_text("ui.d1.hp", {"hp": 40.0, "max": 40.0}) == catalog.format_text("ui.d1.hp", {"hp": 40, "max": 40}), "loaded JSON whole-number stats display without decimal suffixes")
	var scene: PackedScene = load("res://scenes/main.tscn")
	app = scene.instantiate()
	tree.root.add_child(app)
	await _frames()
	app._save_path = "user://view-integration.json"
	app.meta = app.run_rules.new_meta()
	app.run = {}
	app.settings["intro_seen"] = false
	app._debug_seed = 147
	_check(app.screen == "title", "launch retains title entry point")
	_check(app.theme.default_font.antialiasing == TextServer.FONT_ANTIALIASING_NONE and app.theme.default_font.hinting == TextServer.HINTING_NONE and app.theme.default_font.subpixel_positioning == TextServer.SUBPIXEL_POSITIONING_DISABLED, "native pixel font disables antialiasing, hinting and subpixel positioning")
	app._title_continue()
	await _frames()
	_check(app.screen == "story" and app._story.pages.size() == 4, "new journey shows four original intro beats")
	var enter: InputEventKey = _key(KEY_ENTER)
	app._unhandled_key_input(enter)
	app._unhandled_key_input(enter)
	_check(app._story.index == 1, "same-frame Enter cannot skip two story pages")
	while app.screen == "story":
		await _frames()
		app._unhandled_key_input(_key(KEY_SPACE))
	_check(app.screen == "book", "intro reaches the chapter book")
	await _frames()
	app._continue_game()
	_check(app.screen == "hut", "unlocked chapter enters hut")
	app._show_prepare()
	_check(app.selected_commissions == ["keepsake.ring"], "first departure selects only the ring commission")
	app._start_run()
	_check(app.screen == "path" and app.run["segment"] == 1, "departure produces a real segment-one path")
	app._choose_path(0)
	await _frames()
	_check(app.screen == "battle" and app.battle["encounter"]["id"] == "enc.tutorial", "first path opens actual tutorial BattleRules state")
	var start: Dictionary = app.battle.duplicate(true)
	app._unhandled_key_input(_key(KEY_8))
	_check(app.battle == start, "out-of-range hand key is a no-op")
	app._unhandled_key_input(_key(KEY_1))
	_check(app._battle_view.selected == 0, "keyboard 1 selects the first instance")
	app._unhandled_key_input(_key(KEY_ESCAPE))
	_check(app._battle_view.selected == -1 and app._overlay == null, "Escape first cancels card selection")
	app._unhandled_key_input(_key(KEY_ESCAPE))
	_check(app._overlay != null, "second Escape opens pause")
	await _frames()
	app._unhandled_key_input(_key(KEY_ESCAPE))
	_check(app._overlay == null, "Escape dismisses pause without stale action")
	app._unhandled_key_input(_key(KEY_D))
	_check(app._overlay != null, "D opens the real draw pile")
	await _frames()
	app._unhandled_key_input(_key(KEY_ESCAPE))
	var legal: Array = app.battle_rules.legal_actions(app.battle)
	var chosen: Dictionary = {}
	for action: Dictionary in legal:
		if action.get("type") == "play_card":
			chosen = action
			break
	if not chosen.is_empty():
		app._battle_command(chosen)
		await _frames()
		if app.screen == "battle":
			app._pause_to_title()
			await _frames()
			app._continue_game()
			await _frames()
			_check(JSON.parse_string(JSON.stringify(app.battle)) == JSON.parse_string(JSON.stringify(start)), "continue restores exact original battle including random streams")
	# Intentionally lose by legal end turns, then exercise real retry assistance.
	var guard: int = 0
	while app.screen == "battle" and guard < 80:
		app._battle_command({"type": "end_turn", "keep_index": -1})
		guard += 1
		await tree.process_frame
	_check(app.screen == "defeat", "ending turns without defense reaches real defeat screen")
	if app.screen == "defeat":
		app._retry_battle()
		await _frames()
		_check(app.screen == "battle" and app.battle["retry_attempt"] == 1, "retry button creates assisted fresh battle")
	var reached_reward: bool = false
	for step: int in range(100):
		if app.screen != "battle": break
		app._battle_command(bot.choose_action(app.battle, app.battle_rules))
		await tree.process_frame
		if app.screen == "reward": reached_reward = true
	_check(reached_reward, "legal combat reaches first three-way reward")
	if app.screen == "reward":
		var offers: Array = app.run_rules.reward_choices(app.run)
		_check(offers[0]["id"] == "relic.lone_glove", "tutorial reward really includes fixed glove")
		app._choose_reward(0)
		_check("relic.lone_glove" in app.run["relics"] and app.screen == "path", "reward selection applies core relic and advances")
	await _finish_trip()
	_check("keepsake.ring" in app.meta["returned"], "actual first path returns ring permanently")
	_check("card.vow_plus" in app.meta["replica_cards"], "resting with ring yields actual plus replica")
	var returned_before: Array = app.meta["returned"].duplicate()
	var replicas_before: Array = app.meta["replica_cards"].duplicate()
	app._checkpoint()
	var loaded: Dictionary = saves.load_state(app._save_path)
	_check(loaded["ok"] and loaded["state"]["meta"]["returned"] == returned_before, "hut progress saves as version-one meta")
	_check(loaded["state"]["meta"]["replica_cards"] == replicas_before, "save reload does not duplicate permanent rewards")
	for trip: int in range(3):
		if app.meta.get("ending_seen", false): break
		app.selected_commissions = app.run_rules.available_commissions(app.meta).slice(0, 2)
		app._debug_seed = 148 + trip
		app._show_prepare()
		app._start_run()
		await _finish_trip()
	_check(app.meta["returned"].size() == 3 and app.meta["boss_defeated"], "actual path campaign obtains three returns and a boss victory")
	_check(app.meta["ending_seen"] and app.screen == "hut", "conditional ending story completes back to hut")
	var before_reset: Dictionary = app.meta.duplicate(true)
	app._show_title()
	app._confirm_reset()
	_check(app.meta == before_reset and app._overlay != null, "new-game reset requires explicit confirmation")
	app._close_overlay()
	_check(app.meta == before_reset, "canceling reset preserves all progress")
	await _test_text_layout()
	await _test_picker_and_layout()
	await _test_pointer_drag()
	await _test_pickup()
	await _test_reward_replacement()
	await _test_trade()
	app.queue_free()
	await _frames()
	_remove("user://view-integration.json")
	return {"passed": passed, "failed": failed, "scope": "D1 real app inputs, exact saves, real battle retry, two-commission path and ending"}

func _finish_trip() -> void:
	var steps: int = 0
	while app.screen != "hut" and steps < 1600:
		steps += 1
		match app.screen:
			"departure": app._choose_departure(0)
			"path":
				var paths: Array = app.run_rules.path_choices(app.run)
				var chosen: int = 0
				var best: int = -100
				for index: int in range(paths.size()):
					var node: Dictionary = paths[index]
					var score: int = node.get("star_ids", []).size() * 20 + node.get("heart_ids", []).size() * 10
					if node["type"] == "campfire": score += 4
					if node["type"] == "event": score += 2
					if score > best:
						best = score
						chosen = index
				app._choose_path(chosen)
			"battle": app._battle_command(bot.choose_action(app.battle, app.battle_rules, "defensive"))
			"defeat":
				if int(app.run.get("battle_attempt", 0)) >= 4:
					app._end_run("defeat")
				else:
					app._retry_battle()
			"reward": app._choose_reward(bot.choose_reward(app.run_rules.reward_choices(app.run), app.run))
			"replacement": app._replace_card(0)
			"node":
				var choices: Array = app.run_rules.node_choices(app.run)
				var chosen: String = str(choices[0]["id"])
				for choice: Dictionary in choices:
					for op: Dictionary in choice.get("ops", []):
						if op["op"] == "complete_wish": chosen = choice["id"]
				app._choose_node(chosen)
			"story": app._skip_story()
			"reveal": app._route_phase()
			_: break
		await tree.process_frame
	_check(steps < 1600 and app.screen == "hut", "a complete actual UI trip terminates at hut")

func _test_story() -> void:
	var player: RefCounted = Story.new()
	var sequence: Dictionary = catalog.entry("story.return.ring")
	player.begin(sequence, {"wishes": {"keepsake.ring": false}})
	_check(player.pages.size() == 3, "ring story hides wish page when actual wish is false")
	player.begin(sequence, {"wishes": {"keepsake.ring": true}, "card_id": "card.vow_plus"})
	_check(player.pages.size() == 4 and player.stamp() == "card.vow_plus", "wish page and plus stamp follow core context")
	player.skip()
	_check(player.finished(), "story skip is terminal")

func _test_save() -> void:
	var path: String = "user://view-save-test.json"
	_remove(path)
	var state: Dictionary = saves.default_state()
	_check(saves.save_state(state, path) == OK and saves.load_state(path)["ok"], "version-one save roundtrips")
	state["settings"]["music"] = "loud"
	_check(saves.save_state(state, path) == ERR_INVALID_DATA, "invalid settings are rejected safely")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var recovered: Dictionary = saves.load_state(path)
	_check(recovered["recovered"] and FileAccess.file_exists(recovered["backup"]), "corrupt save preserved as backup")
	_remove(recovered.get("backup", ""))
	var future: String = "user://view-future-test.json"
	file = FileAccess.open(future, FileAccess.WRITE)
	file.store_string('{"version":99,"meta":{},"run":null,"settings":{}}')
	file.close()
	var original: String = FileAccess.get_file_as_string(future)
	var result: Dictionary = saves.load_state(future)
	_check(result.get("readonly", false) and not result["recovered"], "future save is read-only not quarantined")
	_check(saves.save_state(saves.default_state(), future) == ERR_UNAVAILABLE and FileAccess.get_file_as_string(future) == original, "future save cannot be overwritten by defaults")
	_remove(future)
	var failed_backup: Dictionary = saves._recover("user://view-nonexistent-backup.json", "invalid_save")
	_check(failed_backup.get("readonly", false) and saves.save_state(saves.default_state(), "user://view-nonexistent-backup.json") == ERR_UNAVAILABLE, "failed backup never permits overwriting the only unpreserved copy")

func _frames() -> void:
	await tree.process_frame
	await tree.process_frame

func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func _remove(path: String) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS view: " + label)
	else:
		failed += 1
		printerr("FAIL view: " + label)

func _test_picker_and_layout() -> void:
	var BattleViewScript: Script = load("res://scripts/view/battle_view.gd")
	var fixture: Dictionary = {"hp": 40, "max_hp": 40, "deck": catalog.table("meta")[0]["starter_deck"].duplicate(), "relics": ["relic.crooked_compass", "relic.open_ink", "relic.bookmark"], "keepsakes": []}
	var encounter: Dictionary = {"id": "debug.layout", "enemies": ["boss.sock_snake", "enemy.sock_kid", "enemy.sock_kid", "enemy.sock_kid"]}
	var state: Dictionary = app.battle_rules.start(encounter, fixture, 324)["state"]
	var view: Control = BattleViewScript.new()
	var commands: Array = []
	view.theme = app.theme
	view.configure(app.battle_rules, state, func(command: Dictionary) -> void: commands.append(command), func(_kind: String) -> void: pass, func() -> void: pass)
	tree.root.add_child(view)
	await _frames()
	_check(view._hand_buttons.size() == 8 and view._enemy_buttons.size() == 4, "actual rules fixture renders eight hands and four enemies")
	var text_overflow: Array[String] = []
	_audit_text(view, text_overflow)
	_check(text_overflow.is_empty(), "four-enemy/eight-hand actual font paragraphs fit: " + str(text_overflow))
	var fit: bool = true
	for index: int in range(view._hand_buttons.size()):
		var rectangle: Rect2 = view._hand_buttons[index].get_rect()
		fit = fit and rectangle.size == Vector2(56, 76) and rectangle.end.x <= 640
		if index > 0:
			fit = fit and not rectangle.intersects(view._hand_buttons[index - 1].get_rect())
	_check(fit, "all eight 56x76 hands fit without overlap")
	view.select_card(0)
	_check(view._large.size == Vector2(112, 152), "hover large card is exactly112x152")
	var original: Dictionary = state.duplicate(true)
	view._update_preview()
	_check(state == original, "UI hover forecast leaves state and randomness untouched")
	view.request_end_turn()
	_check(view._chooser != null and view._picker_actions.size() == 9, "bookmark picker offers no-keep plus every legal hand instance")
	var keep: Dictionary = view._picker_actions[1]
	view._commit(keep)
	_check(commands.size() == 1 and commands[0] == keep, "bookmark control submits the actual legal keep command")
	view.queue_free()
	await _frames()
	# Deliver has several real choices; no first-target or first-card guess.
	fixture["deck"] = ["card.deliver_plus", "card.knock", "card.brace", "card.pocket", "card.deliver_plus", "card.knock", "card.brace", "card.pocket"]
	fixture["relics"] = ["relic.crooked_compass", "relic.open_ink"]
	state = app.battle_rules.start({"id": "debug.free", "enemies": ["enemy.lonely_sock", "enemy.wet_sock"]}, fixture, 72)["state"]
	view = BattleViewScript.new()
	view.theme = app.theme
	commands.clear()
	view.configure(app.battle_rules, state, func(command: Dictionary) -> void: commands.append(command), func(_kind: String) -> void: pass, func() -> void: pass)
	tree.root.add_child(view)
	await _frames()
	var deliver: int = -1
	for index: int in range(state["hand"].size()):
		if state["hand"][index]["id"] == "card.deliver_plus": deliver = index
	view.select_card(deliver)
	view.confirm_selection()
	_check(view._chooser != null and view._picker_actions.size() > 1 and commands.is_empty(), "free-play opens explicit legal choice controls without auto-targeting")
	var legal_choices: bool = true
	for action: Dictionary in view._picker_actions:
		legal_choices = legal_choices and app.battle_rules.legal_actions(state).has(action)
	_check(legal_choices, "every picker option comes from BattleRules legal_actions")
	view.cancel_selection()
	_check(commands.is_empty() and view.selected == -1, "canceling nested choice issues no card command")
	view.queue_free()
	await _frames()
	# Malformed typed progress is quarantined before the app sees it.
	var path: String = "user://view-malformed.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string('{"version":1,"meta":{"returned":4},"run":null,"settings":{}}')
	file.close()
	var recovered: Dictionary = saves.load_state(path)
	_check(recovered.get("recovered", false), "malformed meta shape cannot reach UI core calls")
	_remove(recovered.get("backup", ""))

func _test_pickup() -> void:
	var fixture: Dictionary = {"hp": 40, "max_hp": 40, "deck": ["card.pick_up", "card.knock", "card.brace", "card.pocket", "card.pick_up", "card.knock", "card.brace", "card.pocket"], "relics": ["relic.crooked_compass", "relic.open_ink"], "keepsakes": []}
	var state: Dictionary = app.battle_rules.start({"id": "debug.pickup", "enemies": ["elite.hungry_drawer"]}, fixture, 4)["state"]
	for wanted: String in ["card.knock", "card.brace"]:
		for action: Dictionary in app.battle_rules.legal_actions(state):
			if action.get("type") == "play_card" and state["hand"][int(action["hand_index"])]["id"] == wanted:
				app.battle_rules.play_card(state, action["hand_index"], action.get("target_index", -1), action.get("choices", {}))
				break
	var view: Control = load("res://scripts/view/battle_view.gd").new()
	var commands: Array = []
	view.theme = app.theme
	view.configure(app.battle_rules, state, func(command: Dictionary) -> void: commands.append(command), func(_kind: String) -> void: pass, func() -> void: pass)
	tree.root.add_child(view)
	await _frames()
	for index: int in range(state["hand"].size()):
		if state["hand"][index]["id"] == "card.pick_up":
			view.select_card(index)
			break
	view.confirm_selection()
	_check(view._chooser != null and view._picker_actions.size() == 2, "pick-up explicitly offers both actual discard instances")
	var action: Dictionary = view._picker_actions[1]
	view._commit(action)
	view._commit(action)
	_check(commands.size() == 1 and commands[0]["choices"].has("discard_uid"), "same-frame picker activation submits exactly one UID command")
	var instance: String = commands[0]["choices"]["discard_uid"]
	app.battle_rules.play_card(state, commands[0]["hand_index"], commands[0]["target_index"], commands[0]["choices"])
	_check(app.battle_rules.find_card(state["hand"], instance) >= 0, "chosen discard instance actually returns to hand")
	view.queue_free()
	await _frames()

func _test_reward_replacement() -> void:
	app.meta = app.run_rules.new_meta()
	app.selected_commissions = ["keepsake.ring"]
	app._debug_seed = 990
	app._start_run()
	# Explicit test-only twelve-card deck fixture, still won through legal actions.
	app.run["deck"].append_array(["card.knock", "card.knock"])
	app._choose_path(0)
	for step: int in range(100):
		if app.screen != "battle": break
		app._battle_command(bot.choose_action(app.battle, app.battle_rules))
		await tree.process_frame
	var card_index: int = -1
	for index: int in range(app.run.get("rewards", []).size()):
		if app.run["rewards"][index]["kind"] == "card": card_index = index
	_check(card_index >= 0, "real victory supplies a card reward for replacement fixture")
	if card_index < 0: return
	var before: Array = app.run["deck"].duplicate()
	app._choose_reward(card_index)
	_check(app.screen == "replacement" and app.run["deck"] == before, "full deck opens replacement without premature mutation")
	app._cancel_replace()
	_check(app.screen == "reward" and app.run["deck"] == before, "replacement cancel returns to original reward and deck")
	var awarded: String = app.run["rewards"][card_index]["id"]
	app._choose_reward(card_index)
	app._replace_card(0)
	_check(app.run["deck"].size() == 12 and app.run["deck"][0] == awarded and app.screen == "path", "chosen replacement commits exactly one real card and advances")

func _test_trade() -> void:
	var selected_seed: int = -1
	for seed_value: int in range(1, 30):
		var probe: Dictionary = app.run_rules.start_run(app.run_rules.new_meta(), ["keepsake.ring"], seed_value)
		for node: Dictionary in probe["run"]["path"][2]:
			if node["type"] == "trade": selected_seed = seed_value
		if selected_seed >= 0: break
	_check(selected_seed >= 0, "a deterministic real route offers the exchange stall")
	if selected_seed < 0: return
	app.meta = app.run_rules.new_meta()
	app.selected_commissions = ["keepsake.ring"]
	app._debug_seed = selected_seed
	app._start_run()
	app._choose_path(0)
	for step: int in range(100):
		if app.screen != "battle": break
		app._battle_command(bot.choose_action(app.battle, app.battle_rules))
		await tree.process_frame
	app._choose_reward(0)
	var paths: Array = app.run_rules.path_choices(app.run)
	for index: int in range(paths.size()):
		if paths[index]["type"] == "event":
			app._choose_path(index)
			break
	app._choose_node(str(app.run_rules.node_choices(app.run)[0]["id"]))
	if app.screen == "story": app._skip_story()
	paths = app.run_rules.path_choices(app.run)
	for index: int in range(paths.size()):
		if paths[index]["type"] == "trade":
			app._choose_path(index)
			break
	_check(app.screen == "node" and app.run["current_node"]["type"] == "trade", "actual segment-three route opens exchange controls")
	var previous: Array = app.run["deck"].duplicate()
	app._prepare_trade("card", 0)
	var offers: Array = app.run_rules.trade_choices(app.run)
	_check(app.screen == "trade_offer" and offers.size() == 3, "exchange gives three real same-type card offers")
	app._show_trade()
	app._prepare_trade("card", 0)
	_check(app.run_rules.trade_choices(app.run) == offers and app.run["deck"] == previous, "cancel/reopen exchange neither mutates deck nor rerolls same item")
	app._choose_trade(0)
	_check(app.screen == "path" and app.run["deck"].size() == previous.size() and app.run["deck"][0] == offers[0], "exchange consumes one card and returns to real path")

func _test_text_layout() -> void:
	app.meta = app.run_rules.new_meta()
	app.selected_commissions = ["keepsake.ring"]
	for heading: String in ["book", "commissions", "prepare"]:
		match heading:
			"book": app._show_book()
			"commissions": app._show_commissions()
			"prepare": app._show_prepare()
		await _frames()
		var overflow: Array[String] = []
		_audit_text(app._content, overflow)
		_check(overflow.is_empty(), heading + " actual font layout stays within allocated paragraphs: " + str(overflow))
	# Worst-case reward/effect descriptions, with the actual synchronized font.
	var page: Control = Control.new()
	page.theme = app.theme
	tree.root.add_child(page)
	app._item_card(page, "card.push_back", Rect2(24, 66, 180, 208), func() -> void: pass)
	app._item_card(page, "relic.birthday_candle", Rect2(216, 66, 180, 208), func() -> void: pass)
	await _frames()
	var overflow: Array[String] = []
	_audit_text(page, overflow)
	_check(overflow.is_empty(), "worst-case reward text wraps inside its card: " + str(overflow))
	page.queue_free()
	await _frames()

func _audit_text(parent: Node, overflow: Array[String]) -> void:
	for child: Node in parent.get_children():
		if child is Label and child.has_meta("allocated_rect") and child.autowrap_mode != TextServer.AUTOWRAP_OFF:
			var allocated: Rect2 = child.get_meta("allocated_rect")
			var font: Font = child.get_theme_font("font")
			var font_size: int = child.get_theme_font_size("font_size")
			var lines: int = child.get_line_count()
			var required_height: float = font.get_height(font_size) * lines + child.get_theme_constant("line_spacing") * maxi(0, lines - 1)
			if child.size.x > allocated.size.x + 1 or required_height > allocated.size.y + 1:
				overflow.append(child.text + " [" + str(child.size) + "; lines=" + str(lines) + "; height=" + str(required_height) + "]")
		_audit_text(child, overflow)

func _test_pointer_drag() -> void:
	var fixture: Dictionary = {"hp": 40, "max_hp": 40, "deck": ["card.knock", "card.knock", "card.knock", "card.knock"], "relics": [], "keepsakes": []}
	var state: Dictionary = app.battle_rules.start({"id": "debug.pointer", "enemies": ["elite.hungry_drawer"]}, fixture, 11)["state"]
	var view: Control = load("res://scripts/view/battle_view.gd").new()
	var commands: Array = []
	view.theme = app.theme
	view.size = Vector2(640, 360)
	view.configure(app.battle_rules, state, func(command: Dictionary) -> void: commands.append(command), func(_kind: String) -> void: pass, func() -> void: pass)
	app.hide()
	tree.root.add_child(view)
	await _frames()
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(160, 295)
	press.global_position = press.position
	tree.root.push_input(press, true)
	await _frames()
	_check(view.selected == 0 and view._pressed_card == 0, "actual pointer press picks the first hand instance")
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.position = Vector2(207, 149)
	move.global_position = move.position
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	move.relative = Vector2(47, -146)
	tree.root.push_input(move, true)
	await _frames()
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = move.position
	release.global_position = move.position
	tree.root.push_input(release, true)
	await _frames()
	_check(commands.size() == 1 and commands[0].get("target_index", -1) == 0, "actual pointer press-motion-release submits one targeted legal command")
	view.queue_free()
	app.show()
	await _frames()
