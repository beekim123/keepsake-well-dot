extends SceneTree
const Rules = preload("res://scripts/core/battle_rules.gd")
var View: GDScript
var Controller: GDScript
var passed: int = 0
var failures: Array = []
var rules: RefCounted
var sent: Array = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failures.append(label)
func fixture(count: int = 2) -> Dictionary:
	var enemies: Array = []
	for index: int in range(count): enemies.append("enemy.lint_bug")
	return rules.start({"id": "qa.rope", "enemies": enemies}, {"deck": ["card.tie", "card.bind", "card.knock", "card.bind", "card.knock", "card.bind"], "keepsakes": ["keepsake.ring"]}, 147)["state"]
func view_for(state: Dictionary) -> Control:
	var view: Control = View.new()
	view.configure(rules, state, func(action: Dictionary) -> void: sent.append(action), func(_pile: String) -> void: pass, func() -> void: pass)
	root.add_child(view)
	view._input_ready_frame = 0
	return view
func _run() -> void:
	View = load("res://scripts/view/battle_view.gd")
	Controller = load("res://tests/rope_pair/view_controller_fixture.gd")
	var font: Font = load("res://resources/fonts/fusion-pixel-12px/fusion-pixel-12px-proportional-zh_hans.otf.woff2")
	var missing: Array[String] = []
	var visible_text: String = "♡↔→"
	for row: Dictionary in root.get_node("ContentCatalog").table("ui"):
		if str(row.get("id", "")).begins_with("ui.rope."): visible_text += str(row.get("text", ""))
	for index: int in range(visible_text.length()):
		var code: int = visible_text.unicode_at(index)
		if code > 32 and not font.has_char(code) and visible_text[index] not in missing: missing.append(visible_text[index])
	check(missing.is_empty(), "new rope text and symbols have font glyphs: " + "".join(missing))
	rules = Rules.new(root.get_node("ContentCatalog").definitions())
	# Wrong non-card dispatch must not turn a shake or keepsake into end-turn.
	var app: Control = Controller.new()
	root.add_child(app)
	app.battle_rules = rules
	app.presentation_fast = true
	app.screen = "battle"
	app.battle = fixture()
	var turn: int = app.battle["turn"]
	app._battle_command({"type": "shake_card", "hand_index": 0})
	check(app.battle["turn"] == turn and app.battle["turn_flags"]["shakes_used"] == 1, "controller dispatches shake without ending turn")
	app.battle = fixture()
	var active: Dictionary = {}
	for action: Dictionary in rules.legal_actions(app.battle):
		if action["type"] == "use_keepsake": active = action; break
	app._battle_command(active)
	check(app.battle["turn"] == 1 and app.battle["battle_flags"]["keepsake_uses"].get("keepsake.ring", false), "controller dispatches active keepsake")
	app.free()
	# A two-target card must never silently infer target 2, even with two enemies.
	var state: Dictionary = fixture()
	state["hand"] = [rules.new_card(state, "card.tie")]
	var view: Control = view_for(state)
	sent.clear()
	view.select_card(0)
	view._enemy_clicked(0)
	check(sent.is_empty(), "first target waits for second")
	view._enemy_clicked(0)
	check(sent.is_empty(), "same enemy cannot be second target")
	view._enemy_clicked(1)
	check(sent.size() == 1 and sent[0].get("target_index") == 0 and sent[0].get("choices", {}).get("second_target") == 1, "second click preserves ordered target pair")
	view.free()
	view = view_for(state)
	sent.clear()
	view.select_card(0)
	view._enemy_clicked(0)
	view.cancel_selection()
	view._enemy_clicked(1)
	check(sent.is_empty() and view.selected == -1, "cancel clears pending second target")
	view.select_card(0)
	view._enemy_clicked(1)
	view._enemy_clicked(0)
	check(sent.size() == 1 and sent[0].get("target_index") == 1, "selection after cancellation starts fresh")
	view.free()
	state = fixture(1)
	state["hand"] = [rules.new_card(state, "card.tie")]
	view = view_for(state)
	sent.clear()
	view.select_card(0)
	view._enemy_clicked(0)
	check(sent.size() == 1 and sent[0].get("choices", {}).is_empty(), "single living enemy uses fallback without second selection")
	view.free()
	state = fixture()
	state["enemies"][0]["departed"] = "paired"
	view = view_for(state)
	check(view._first_target() == 1 and view._enemy_buttons[0].disabled, "paired enemies with positive hp are not targetable")
	view.free()
	state = fixture()
	view = view_for(state)
	sent.clear()
	view.select_keepsake("keepsake.ring")
	check(sent.size() == 1 and sent[0].get("type") == "use_keepsake" and sent[0].get("target_index") == -1, "all-enemy keepsake fires directly without a spurious target")
	view.free()
	state = fixture(1)
	state["hand"] = [rules.new_card(state, "card.whisper_plus")]
	rules.play_card(state, 0, 0)
	view = view_for(state)
	check(state["enemies"][0].get("lookahead") == 2 and view._enemy_buttons[0].tooltip_text.contains("滚成团"), "playing whisper without spyglass exposes second future intent")
	view.free()
	state = rules.start({"id":"elite.hungry_drawer","enemies":["elite.hungry_drawer"]}, {"deck":["card.whisper_plus","card.bind","card.knock","card.tie","card.knock"]},147)["state"]
	state["hand"] = [rules.new_card(state,"card.whisper_plus")]
	view = view_for(state)
	view.on_command = func(action: Dictionary) -> void: rules.apply_action(state,action)
	view.select_card(0)
	view._enemy_clicked(0)
	view.free()
	view = view_for(state)
	check(state["relics"].is_empty() and view._enemy_buttons[0].tooltip_text.contains("打嗝 4×2"), "actual whisper on elite reveals both future attack hits without spyglass")
	view.free()
	rules.end_turn(state)
	rules.end_turn(state)
	state["hand"] = [rules.new_card(state,"card.whisper_plus")]
	rules.play_card(state,0,0)
	view = view_for(state)
	check(view._intent_amount(view._intent_for(0)) == "4×2 → 0+3", "current multi-hit intent preserves individually reduced hit amounts")
	view.free()
	for boss: bool in [false, true]:
		var viewport: SubViewport = SubViewport.new()
		viewport.size = Vector2i(640,360)
		root.add_child(viewport)
		state = rules.start({"id": "boss.sock_snake" if boss else "enc.tutorial", "enemies": ["boss.sock_snake" if boss else "enemy.wet_sock"]}, {"deck":["card.knock","card.bind","card.tie","card.knock","card.bind"]},147)["state"]
		view = View.new()
		view.size = Vector2(640,360)
		view.configure(rules,state,func(action: Dictionary) -> void: sent.append(action),func(_kind: String) -> void: pass,func() -> void: pass)
		viewport.add_child(view)
		await process_frame
		await process_frame
		sent.clear()
		var pointer: InputEventMouseMotion = InputEventMouseMotion.new()
		pointer.position = Vector2(220 if boss else 260,238)
		pointer.global_position = pointer.position
		viewport.push_input(pointer,true)
		await process_frame
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT
		click.position = pointer.position
		click.global_position = pointer.position
		click.pressed = true
		viewport.push_input(click,true)
		var release: InputEventMouseButton = click.duplicate()
		release.pressed = false
		release.button_mask = 0
		viewport.push_input(release,true)
		await process_frame
		check(sent.size() == 1 and sent[0].get("type") == "end_turn" and view.decoration_counts.is_empty(), ("boss" if boss else "normal") + " end-turn text receives real GUI mouse hit before decoration")
		viewport.free()
	# The tutorial must expose and operate both targets, not only enemy slot zero.
	var tutorial: Dictionary = rules.start_tutorial({}, 147, "tutorial.pair")["state"]
	var stage: Node = load("res://scenes/remedy/BattleScene.tscn").instantiate()
	stage.config = {"resume_state": tutorial, "instant_presentation": true}
	root.add_child(stage)
	await process_frame
	await process_frame
	var second: Node = stage.find_child("Enemy1", true, false)
	check(second != null and second.is_visible_in_tree(), "tutorial projects second enemy")
	check(stage.state["enemies"].size() == 2 and not stage.busy, "tutorial preserves two-enemy authority and settles")
	stage.command_play(0, 0, {"second_target": 1})
	check(stage.state["enemies"][0]["tie"] == stage.state["enemies"][1]["uid"], "tutorial dispatch applies the chosen second target")
	check(stage._status.get("guide") == "pair_hits" and stage.gesture.finish == stage._view._enemy_centers[0], "pair lesson asks for knocks after tying")
	stage.command_play(0, 0)
	check(stage.gesture.finish == stage._view._enemy_centers[1], "after the first knock the gesture points at the other healthier enemy")
	stage.command_play(0, 1)
	check(stage.state["status"] == "victory" and stage.state["battle_flags"]["pairs"] == 1, "pair lesson completes with tie and two real knocks")
	stage.free()
	state = fixture()
	state["hand"] = [rules.new_card(state, "card.deliver"), rules.new_card(state, "card.tie")]
	view = view_for(state)
	sent.clear()
	view.select_card(0)
	view.confirm_selection()
	check(view._chooser != null and sent.is_empty(), "deliver requires explicit nested target choice")
	var nested: Dictionary = view._picker_actions[0]
	check(view._action_text(nested).contains("↔") and nested.get("choices", {}).get("other_choices", {}).has("second_target"), "deliver picker identifies both nested targets")
	var cancel: InputEventMouseButton = InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	view._input(cancel)
	check(view._chooser == null and view.selected == -1 and sent.is_empty(), "right-click cancels nested picker without dispatch")
	view.select_card(1)
	view._enemy_clicked(0)
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	view.handle_key(escape)
	check(view.selected == -1 and view.first_target == -1 and sent.is_empty(), "escape cancels pending second target")
	view.free()
	state = fixture(3)
	state["hand"] = [rules.new_card(state, "card.deliver"), rules.new_card(state, "card.deliver_plus"), rules.new_card(state, "card.tie")]
	view = view_for(state)
	var deep_actions: Array = []
	for action: Dictionary in view._matching_actions(0):
		var choice: Dictionary = action.get("choices", {})
		if choice.get("other_uid") == state["hand"][1]["uid"] and choice.get("other_choices", {}).get("other_uid") == state["hand"][2]["uid"]: deep_actions.append(action)
	var labels_to_pairs: Dictionary = {}
	var unordered_pairs: Dictionary = {}
	var distinct_pairs_readable: bool = true
	for action: Dictionary in deep_actions:
		var inner: Dictionary = action["choices"]["other_choices"]
		var pair_first: int = int(inner["other_target_index"])
		var pair_second: int = int(inner["other_choices"]["second_target"])
		var pair_key: String = "%d:%d" % [mini(pair_first,pair_second),maxi(pair_first,pair_second)]
		var label: String = view._action_text(action)
		if labels_to_pairs.has(label) and labels_to_pairs[label] != pair_key: distinct_pairs_readable = false
		labels_to_pairs[label] = pair_key
		unordered_pairs[pair_key] = true
	check(deep_actions.size() == 6 and unordered_pairs.size() == 3 and distinct_pairs_readable, "all distinct unordered pairs of same-name enemies have distinct recursive deliver labels")
	sent.clear()
	view.on_command = func(action: Dictionary) -> void:
		sent.append(action)
		rules.apply_action(state, action)
	view._commit(deep_actions[1])
	check(sent.size() == 1 and sent[0] == deep_actions[1] and state["enemies"][0]["tie"] == state["enemies"][2]["uid"], "recursive deliver dispatches the specifically selected 1-to-3 pair")
	view.free()
	# Route first click reveals the hidden card; selection is a separate action.
	app = Controller.new()
	root.add_child(app)
	app._save_path = "user://d2-debug.json"
	app._build_background()
	app.run_rules = load("res://scripts/core/run_rules.gd").new(root.get_node("ContentCatalog").definitions())
	app.battle_rules = rules
	app.meta = app.run_rules.new_meta()
	app.run = app.run_rules.start_run(app.meta, ["keepsake.ring"], 147)["run"]
	app.presentation_fast = true
	app._show_path()
	app._ready_frame = 0
	var path_card: Button = app._content.find_child("Path0", true, false)
	var phase: String = str(app.run["phase"])
	path_card.pressed.emit()
	check(app.run["phase"] == phase and app.screen == "path", "first route click only reveals card")
	check(app._checkpoint(), "controller writes current save schema to debug checkpoint")
	app.free()
	# Migrated owners keep permanent progress while both new lessons run.
	app = Controller.new()
	root.add_child(app)
	app._save_path = "user://d2-debug.json"
	app._build_background()
	app.run_rules = load("res://scripts/core/run_rules.gd").new(root.get_node("ContentCatalog").definitions())
	app.battle_rules = rules
	app.meta = app.run_rules.new_meta()
	app.run_rules.meta_rules.grant_return(app.meta, root.get_node("ContentCatalog").entry("keepsake.ring"), true)
	var permanent: Dictionary = app.meta.duplicate(true)
	app.settings = {"rope_tutorial_pending": true}
	app.presentation_fast = true
	app._resume_r2_or_legacy()
	await process_frame
	await process_frame
	check(app.screen == "r2_battle" and app._remedy_scene.state.get("tutorial", {}).get("id") == "tutorial.wet_sock", "migrated player enters new lesson before hut")
	var bot: RefCounted = load("res://scripts/core/policy_bot.gd").new(root.get_node("ContentCatalog").definitions())
	app._remedy_scene._command(bot.choose_action(app._remedy_scene.state, rules))
	var checkpoint: Dictionary = app._remedy_scene.state.duplicate(true)
	var saved: Dictionary = root.get_node("SaveService").load_state("user://d2-debug.json")
	app.settings = saved.get("state", {}).get("settings", {}).duplicate(true)
	app._start_rope_refresher()
	await process_frame
	await process_frame
	# Godot JSON decodes whole numbers as floats; compare the full serialized state.
	check(app._remedy_scene.state == JSON.parse_string(JSON.stringify(checkpoint)), "refresher reload restores exact tutorial checkpoint")
	var lessons: Array[String] = []
	for step: int in range(120):
		if app.screen != "r2_battle": break
		var current: Node = app._remedy_scene
		if current.busy or current.state.is_empty(): await process_frame; continue
		var lesson: String = str(current.state["tutorial"]["id"])
		if lesson not in lessons: lessons.append(lesson)
		current._command(bot.choose_action(current.state, current.rules))
		await process_frame
		await process_frame
	check(app.screen == "hut" and not app.settings.get("rope_tutorial_pending", false) and "tutorial.pair" in lessons, "both refresher lessons finish before pending clears")
	check(app.meta == permanent and app.run.is_empty(), "refresher grants no extra meta rewards or expedition")
	app.free()
	print("ROPE_VIEW_RESULT: " + JSON.stringify({"passed": passed, "failed": failures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
