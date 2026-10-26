extends Control
## Pixel presentation over the accepted pure rules; views never grant outcomes.
const GeneratedUI = preload("res://scripts/view/remedy/generated_ui.gd")
const SimpleUI = preload("res://scripts/view/remedy/simple_ui.gd")
const TownScene = preload("res://scenes/remedy/TownScene.tscn")
const UI = preload("res://scripts/view/ui_factory.gd")
const BattleView = preload("res://scripts/view/battle_view.gd")
const StoryView = preload("res://scripts/view/story_view.gd")
const Actor = preload("res://scripts/view/pixel_actor.gd")
const Banter = preload("res://scripts/story/banter_director.gd")
const Story = preload("res://scripts/story/story_player.gd")
const Battle = preload("res://scripts/core/battle_rules.gd")
const Runs = preload("res://scripts/core/run_rules.gd")
const TutorialCheckpoint = preload("res://scripts/view/remedy/tutorial_checkpoint.gd")
const TitleScene = preload("res://scenes/remedy/TitleScene.tscn")
const OpeningScene = preload("res://scenes/remedy/OpeningScene.tscn")
const TutorialEndpoint = preload("res://scenes/remedy/TutorialEndpoint.tscn")
const FONT_PATH: String = "res://resources/fonts/fusion-pixel-12px/fusion-pixel-12px-proportional-zh_hans.otf.woff2"
var meta: Dictionary = {}
var run: Dictionary = {}
var settings: Dictionary = {}
var battle: Dictionary = {}
var run_rules: RefCounted
var battle_rules: RefCounted
var screen: String = "title"
var selected_commissions: Array = []
var _content: Control
var _overlay: Panel
var _battle_view: Control
var _story: RefCounted = Story.new()
var _story_done: Callable
var _story_record: Dictionary = {}
var _font: FontFile
var _ready_frame: int = 0
var _save_path: String = "user://save.json"
var _save_readonly: bool = false
var _notice: String = ""
var _debug_seed: int = -1
var _debug_mode: bool = false
var _last_events: Array = []
var _album_page: int = 0
var _story_view: Control
var _story_completed: bool = false
var _banter: RefCounted = Banter.new()
var _bubble: Panel
var _bubble_until: float = 0.0
var _clock: float = 0.0
var _lock_until: float = 0.0
var _idle_time: float = 0.0
var _focused: bool = true
var presentation_fast: bool = false
var _transition_serial: int = 0
var _decoration_counts: Dictionary = {}
var _modal_shield: Control
var _pending_terminal: bool = false
var _terminal_at: float = 0.0
var _terminal_serial: int = 0
var _intro_panel: Panel
var _intro_remaining: float = 0.0
var _story_token: int = 0
var _bubble_label: Label
var _bubble_message: Dictionary = {}
var _bubble_elapsed: float = 0.0
var _bubble_spoken: int = -1
var _stamp_node: TextureRect
var _stamp_time: float = 0.0
var _stamp_origin: Vector2 = Vector2.ZERO
var _stamp_id: String = ""
var _pending_return_id: String = ""
var _banter_pending: Array = []
var _banter_frame: int = -1
var _reveal_icon: TextureRect
var _reveal_origin: Vector2 = Vector2.ZERO
var _reveal_time: float = 0.0
var _remedy_scene: Node
var _tutorial_state: Dictionary = {}
var _tutorial_readonly: bool = false
var _r2_endpoint_layer: CanvasLayer
var _save_extra: Dictionary = {}
var _tutorial_terminal_events: Array = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_window().title = ContentCatalog.text("ui.game_title")
	_build_theme()
	_build_background()
	run_rules = Runs.new(ContentCatalog.definitions())
	battle_rules = Battle.new(ContentCatalog.definitions())
	for arg: String in OS.get_cmdline_user_args():
		if OS.is_debug_build() and (arg.begins_with("--seed=") or arg == "--shots" or arg.begins_with("--jump=") or arg.begins_with("--give=") or arg.begins_with("--meta=")):
			_debug_mode = true
		if arg.begins_with("--seed=") and OS.is_debug_build():
			_debug_seed = int(arg.trim_prefix("--seed="))
	if _debug_mode:
		_save_path = "user://d2-debug.json"
	var saved: Dictionary = SaveService.load_state(_save_path)
	var state: Dictionary = saved.get("state", SaveService.default_state())
	_save_extra = state.duplicate(true)
	meta = run_rules.normalize_meta(state.get("meta", {}))
	meta.merge(state.get("meta", {}), false)
	settings = state.get("settings", {}).duplicate(true)
	run = state["run"].duplicate(true) if state.get("run") is Dictionary else {}
	_save_readonly = bool(saved.get("readonly", false))
	if saved.get("error", "") in ["future_version", "future_route"]:
		_notice = t("future_save")
	elif bool(saved.get("recovered", false)):
		_notice = ContentCatalog.text("ui.save_recovered")
	elif not bool(saved.get("ok", false)):
		_notice = ContentCatalog.text("ui.save_unavailable")
	var tutorial_saved: Dictionary = TutorialCheckpoint.inspect(settings.get("r2_tutorial"), SaveService, battle_rules)
	_tutorial_state = tutorial_saved["state"]
	_tutorial_readonly = tutorial_saved["readonly"]
	if not tutorial_saved["ok"]:
		_notice = ContentCatalog.text("ui.r2.future_checkpoint" if _tutorial_readonly else "ui.r2.invalid_checkpoint")
	_banter.configure(ContentCatalog.table("banter"), settings.get("banter_once", {}), int(run.get("seed", 0)))
	if int(settings.get("banter_seed", -1)) == int(run.get("seed", -2)):
		_banter.run_once = settings.get("banter_run_once", {}).duplicate(true)
	presentation_fast = DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--shots")
	_apply_settings()
	if DisplayServer.get_name() != "headless" and not OS.has_feature("web"):
		get_window().size = Vector2i(640, 360) * int(settings.get("window_scale", 2))
		if settings.get("fullscreen", false): get_window().mode = Window.MODE_FULLSCREEN
	_music("music.title_full")
	_show_title()
	if _debug_mode:
		_start_debug.call_deferred()

func _start_debug() -> void:
	if not OS.is_debug_build():
		return
	var helper: RefCounted = load("res://scripts/debug/debug_session.gd").new()
	if OS.get_cmdline_user_args().has("--shots"):
		await helper.capture(self)
	else:
		helper.apply_arguments(self, OS.get_cmdline_user_args())

func t(key: String, values: Dictionary = {}) -> String:
	return ContentCatalog.format_text("ui.d1." + key, values)

func _build_theme() -> void:
	_font = load(FONT_PATH) as FontFile
	_font = _font.duplicate() as FontFile
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_font.hinting = TextServer.HINTING_NONE
	_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_font.multichannel_signed_distance_field = false
	_font.generate_mipmaps = false
	var pixel_theme: Theme = Theme.new()
	pixel_theme.default_font = _font
	pixel_theme.default_font_size = 12
	pixel_theme.set_color("font_color", "Label", UI.PAPER)
	pixel_theme.set_color("font_shadow_color", "Label", Color("1b1622"))
	pixel_theme.set_constant("shadow_offset_x", "Label", 1)
	pixel_theme.set_constant("shadow_offset_y", "Label", 1)
	pixel_theme.set_stylebox("panel", "Panel", AssetCatalog.nine_slice("ui.panel.wood" if AssetCatalog.has_asset("ui.panel.wood") else "ui.panel.default"))
	pixel_theme.set_stylebox("panel", "TooltipPanel", AssetCatalog.nine_slice("ui.panel.wood" if AssetCatalog.has_asset("ui.panel.wood") else "ui.panel.default"))
	for state_name: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var button_id: String = "ui.button." + ("hover" if state_name == "focus" else state_name)
		var style: StyleBoxTexture = AssetCatalog.nine_slice(button_id if AssetCatalog.has_asset(button_id) else "ui.panel.default")
		if state_name in ["hover", "focus"]:
			style.modulate_color = UI.WARM
		elif state_name == "pressed":
			style.modulate_color = Color("b9844e")
		pixel_theme.set_stylebox(state_name, "Button", style)
	pixel_theme.set_color("font_color", "Button", UI.WARM)
	pixel_theme.set_color("font_hover_color", "Button", UI.PAPER)
	pixel_theme.set_color("font_outline_color", "Button", Color("1b1622"))
	pixel_theme.set_constant("outline_size", "Button", 2)
	theme = pixel_theme

func _build_background() -> void:
	var background: TextureRect = TextureRect.new()
	background.name = "TitleBackground"
	background.texture = AssetCatalog.texture("board.title")
	background.size = Vector2(640, 360)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var asui: AnimatedSprite2D = AnimatedSprite2D.new()
	asui.name = "Asui"
	asui.sprite_frames = AssetCatalog.frames("char.asui", "idle")
	asui.centered = false
	asui.offset = -AssetCatalog.anchor("char.asui")
	asui.position = Vector2(394, 327)
	asui.scale = Vector2(2, 2)
	asui.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(asui)
	asui.play("idle")
	_content = Control.new()
	_content.name = "Screens"
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

func _begin_screen(id: String) -> void:
	var continuing_battle: bool = screen == "battle" and id == "battle"
	_transition_serial += 1
	screen = id
	var simple_screen: bool = id in ["title", "hut", "commissions", "prepare", "album", "reward", "replacement", "node", "defeat", "path", "story", "reveal", "stamp"]
	var legacy_visible: bool = not simple_screen and id not in ["opening", "r2_battle", "r2_complete", "battle"]
	$TitleBackground.visible = legacy_visible
	$Asui.visible = legacy_visible
	_remedy_scene = null
	_r2_endpoint_layer = null
	if AudioService.has_method("set_ambience"):
		AudioService.set_ambience("town" if id in ["title", "opening"] else "")
	_story_view = null
	_stamp_node = null
	_reveal_icon = null
	if not continuing_battle:
		_hide_bubble()
		_banter_pending.clear()
	_close_overlay()
	_battle_view = null
	UI.clear(_content)
	_content.theme = SimpleUI.theme() if simple_screen else null
	if simple_screen and id not in ["title", "hut"]:
		if id == "path":
			_scene_background("board.r3_simple_route" if AssetCatalog.has_asset("board.r3_simple_route") else "board.r2_sock_swamp_far")
		elif id in ["reward", "replacement", "defeat", "node", "reveal"]:
			for layer: String in ["far", "mid", "near"]: _scene_background("board.r2_sock_swamp_" + layer)
		else:
			_scene_background("board.r3_simple_town")
	_ready_frame = Engine.get_process_frames() + 1

func _button(parent: Node, label: String, rect: Rect2, callback: Callable, name: String = "") -> Button:
	return UI.button(parent, label, rect, _invoke.bind(callback), name)

func _invoke(callback: Callable) -> void:
	if not _focused or Engine.get_process_frames() < _ready_frame or (screen == "battle" and _overlay == null and not presentation_fast and _clock < _lock_until):
		return
	_ready_frame = Engine.get_process_frames() + 1
	AudioService.unlock()
	_cue("sfx.ui_click")
	_idle_time = 0.0
	callback.call()

func _page(heading: String) -> Panel:
	var page: Panel = UI.frame(_content, "Page", Rect2(12, 10, 616, 340))
	UI.label(page, heading, Rect2(28, 22, 540, 32) if _uses_simple_ui() else Rect2(16, 12, 540, 32), UI.INK if _uses_simple_ui() else UI.WARM, 24)
	if _uses_simple_ui(): call_deferred("_simple_page_ink", page)
	return page

func _uses_simple_ui() -> bool:
	return screen in ["title", "hut", "commissions", "prepare", "album", "reward", "replacement", "node", "defeat", "path", "story", "reveal", "stamp"]

func _simple_page_ink(page: Control) -> void:
	if not is_instance_valid(page) or page.is_queued_for_deletion(): return
	for label: Node in page.find_children("*", "Label", true, false):
		if label.get_meta("simple_dark_plate", false): continue
		label.add_theme_color_override("font_color", UI.INK)
		label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		label.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
		label.add_theme_constant_override("outline_size", 0)
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 0)

func _show_title() -> void:
	_begin_screen("title")
	_music("music.title_full")
	var title: Control = TitleScene.instantiate()
	title.has_progress = _has_progress()
	title.notice = _notice
	title.start_requested.connect(_invoke.bind(_start_opening))
	title.continue_requested.connect(_invoke.bind(_resume_r2_or_legacy))
	title.settings_requested.connect(_invoke.bind(_show_settings))
	_content.add_child(title)
	_remedy_scene = title

func _start_opening() -> void:
	# Start never replaces an existing expedition, including pre-remedy saves.
	if not run.is_empty() and run.get("phase") != "hub":
		_resume_r2_or_legacy()
		return
	if _save_readonly or _tutorial_readonly:
		_show_title()
		return
	if not run_rules.requires_first_run(meta):
		_continue_game()
		return
	var seed_value: int = (_debug_seed if _debug_seed >= 0 else int(Time.get_unix_time_from_system()) + int(meta.get("runs_started", 0))) & 0xffffffff
	var result: Dictionary = run_rules.start_first_run(meta, seed_value)
	if not result.get("ok", false): return
	run = result["run"]
	battle = {}
	settings["first_run_flow"] = true
	_banter.begin_run(seed_value)
	_tutorial_state = {"version": 1, "phase": "opening", "seed": seed_value, "integrated": true}
	_save_tutorial()
	_show_opening()

func _show_opening() -> void:
	_begin_screen("opening")
	var opening: Control = OpeningScene.instantiate()
	var serial: int = _transition_serial
	opening.descent_finished.connect(func() -> void:
		if screen == "opening" and serial == _transition_serial: _launch_tutorial(false))
	_content.add_child(opening)
	_remedy_scene = opening

func _resume_r2_or_legacy() -> void:
	# Campaign snapshots are authoritative. The former optional R2 preview must
	# never hide, replace or rewind a saved seven-station expedition.
	if not run.is_empty() and run.get("phase") != "hub":
		if run_rules.is_first_run(run) and int(run.get("segment", 0)) == 1 and run.get("phase") == "path":
			_show_opening()
		else:
			_continue_game()
		return
	if _save_readonly or _tutorial_readonly:
		_show_title()
		return
	if not _tutorial_state.is_empty() and run_rules.requires_first_run(meta) and (int(meta.get("runs_started", 0)) == 0 or bool(settings.get("first_run_flow", false))):
		_migrate_tutorial()
		return
	_continue_game()

func _migrate_tutorial() -> void:
	# Old 'complete' stores only a boolean, not an authoritative terminal battle.
	# Replay the real lesson rather than manufacture victory/rewards. Active old
	# tutorials do contain a complete snapshot and can be adopted losslessly.
	var previous: Dictionary = _tutorial_state.duplicate(true)
	_start_opening()
	if previous.get("phase") != "battle" or not run_rules.is_first_run(run): return
	var original: Dictionary = previous.get("battle", {})
	if not battle_rules.is_tutorial_state_valid(original): return
	run_rules.choose_path(run, 0)
	var snapshot: Dictionary = original["start_snapshot"]
	run["battle_request"] = {"encounter": snapshot["encounter"].duplicate(true), "run_state": snapshot["run"].duplicate(true), "seed": int(snapshot["seed"])}
	run["battle_checkpoint"] = original.duplicate(true)
	run["resume_battle"] = original.duplicate(true)
	run["phase"] = "battle_ready"
	_checkpoint()
	_start_battle()

func _launch_tutorial(_resume_saved: bool = false) -> void:
	if not run_rules.is_first_run(run): return
	if run.get("phase") == "path" and int(run.get("segment", 0)) == 1:
		_last_events = run_rules.choose_path(run, 0)
	if run.get("phase") == "battle_ready":
		_start_battle()
	elif run.get("phase") == "battle":
		_show_integrated_tutorial()

func _show_integrated_tutorial() -> void:
	_begin_screen("r2_battle")
	var stage: Node = load("res://scenes/remedy/BattleScene.tscn").instantiate()
	var initial: Dictionary = battle_rules.start(battle["start_snapshot"]["encounter"], battle["start_snapshot"]["run"], int(battle["seed"]))
	stage.config = {"seed": int(battle["seed"]), "resume_state": battle.duplicate(true), "restart_state": initial.get("state", {}).duplicate(true), "instant_presentation": presentation_fast}
	_tutorial_terminal_events.clear()
	var serial: int = _transition_serial
	stage.command_finished.connect(func(events: Array) -> void:
		if screen == "r2_battle" and serial == _transition_serial:
			_tutorial_terminal_events = events.duplicate(true))
	stage.checkpoint.connect(func(state: Dictionary) -> void:
		if screen != "r2_battle" or serial != _transition_serial: return
		if not battle_rules.is_tutorial_state_valid(state): return
		battle = state.duplicate(true)
		run["battle_checkpoint"] = battle.duplicate(true)
		_tutorial_state = {"version": 1, "phase": "battle", "seed": int(state["seed"]), "battle": state.duplicate(true), "integrated": true}
		_save_tutorial())
	stage.tutorial_completed.connect(func(result: Dictionary) -> void:
		if screen != "r2_battle" or serial != _transition_serial: return
		var terminal: Dictionary = result.get("state", {})
		var events: Array = run_rules.complete_battle(run, meta, terminal, _tutorial_terminal_events)
		if events.is_empty() or events[0].get("type") == "invalid": return
		battle = terminal.duplicate(true)
		_tutorial_state = {"version": 1, "phase": "done", "seed": int(battle["seed"]), "won": battle.get("status") == "victory", "integrated": true}
		_save_tutorial()
		_last_events = events
		_route_phase())
	stage.exit_requested.connect(func() -> void:
		if serial == _transition_serial: _show_title())
	_content.add_child(stage)
	_remedy_scene = stage

func _save_tutorial() -> bool:
	if _tutorial_readonly or _save_readonly: return false
	var checked: Dictionary = TutorialCheckpoint.inspect(_tutorial_state, SaveService, battle_rules)
	if not checked["ok"]: return false
	var record: Dictionary = settings.get("r2_tutorial", {}).duplicate(true) if settings.get("r2_tutorial") is Dictionary else {}
	record.merge(_tutorial_state, true)
	if record.get("phase") != "battle": record.erase("battle")
	settings["r2_tutorial"] = record
	return _checkpoint()

func _show_tutorial_endpoint(won: bool = true, restore: bool = false) -> void:
	if restore:
		_begin_screen("r2_complete")
		var well: Node = load("res://scenes/remedy/WellStage.tscn").instantiate()
		_content.add_child(well)
	else:
		screen = "r2_complete"
		if is_instance_valid(_remedy_scene): _remedy_scene.process_mode = Node.PROCESS_MODE_DISABLED
	_r2_endpoint_layer = CanvasLayer.new()
	_r2_endpoint_layer.layer = 20
	_content.add_child(_r2_endpoint_layer)
	var endpoint: Control = TutorialEndpoint.instantiate()
	endpoint.theme = theme
	endpoint.won = won
	endpoint.replay_requested.connect(_invoke.bind(_replay_tutorial))
	endpoint.legacy_requested.connect(_invoke.bind(_tutorial_to_legacy))
	endpoint.title_requested.connect(_invoke.bind(_show_title))
	_r2_endpoint_layer.add_child(endpoint)

func _replay_tutorial() -> void:
	_tutorial_state = {"version": 1, "phase": "opening", "seed": int(_tutorial_state.get("seed", 1))}
	_save_tutorial()
	_launch_tutorial(false)

func _tutorial_to_legacy() -> void:
	_tutorial_state = {"version": 1, "phase": "done", "seed": int(_tutorial_state.get("seed", 1)), "won": bool(_tutorial_state.get("won", true))}
	settings["intro_seen"] = true
	_save_tutorial()
	_continue_game()

func _has_progress() -> bool:
	return not _tutorial_state.is_empty() or int(meta.get("runs_started", 0)) > 0 or not run.is_empty() or bool(settings.get("intro_seen", false))

func _title_continue() -> void:
	# Legacy campaign hook. New title buttons use _start_opening/_resume_r2_or_legacy.
	if not bool(settings.get("intro_seen", false)):
		_show_story({"id": "story.intro"}, _intro_done)
	else:
		_show_book()

func _intro_done() -> void:
	settings["intro_seen"] = true
	_checkpoint()
	_show_book()

func _show_book() -> void:
	_begin_screen("book")
	_scene_background("still.rope_hut")
	var cover: Panel = UI.frame(_content, "JournalCover", Rect2(20, 12, 600, 336))
	UI.label(cover, ContentCatalog.text("ui.book_title"), Rect2(18, 10, 564, 32), UI.WARM, 24)
	var left: Panel = UI.frame(cover, "LeftPaper", Rect2(12, 48, 282, 276))
	var right: Panel = UI.frame(cover, "RightPaper", Rect2(306, 48, 282, 276))
	if AssetCatalog.has_asset("ui.panel.paper"):
		left.add_theme_stylebox_override("panel", AssetCatalog.nine_slice("ui.panel.paper"))
		right.add_theme_stylebox_override("panel", AssetCatalog.nine_slice("ui.panel.paper"))
	UI.paragraph(left, ContentCatalog.text("ui.book_body"), Rect2(16, 16, 250, 92), UI.INK)
	if AssetCatalog.has_asset("event.shaft"): UI.texture(left, AssetCatalog, "event.shaft", Rect2(60, 112, 160, 90))
	UI.label(left, t("returned", {"count": meta.get("returned", []).size()}), Rect2(16, 214, 250, 20), UI.INK)
	_button(left, t("back"), Rect2(16, 240, 116, 26), _show_title)
	_button(right, t("chapter1"), Rect2(16, 18, 250, 66), _continue_game)
	var locked: Button = _button(right, t("chapter2"), Rect2(16, 118, 250, 66), func() -> void: pass)
	locked.disabled = true
	if AssetCatalog.has_asset("ui.icon.lock"): UI.texture(right, AssetCatalog, "ui.icon.lock", Rect2(134, 194, 16, 16))

func _continue_game() -> void:
	if run.is_empty() or run.get("phase") == "hub":
		_finish_first_return()
	else:
		_route_phase()

func _finish_first_return() -> void:
	# Reuse the existing Heqing memory after the first actual return, never in
	# front of the first playable action. Acknowledgment is saved independently
	# of the already committed ring/card transaction and can safely be resumed.
	if bool(settings.get("first_run_flow", false)) and "keepsake.ring" in meta.get("returned", []) and not bool(settings.get("first_return_story_seen", false)):
		_show_story({"id": "story.intro", "page_indices": [2]}, _first_return_story_done)
	else:
		_show_hut()

func _first_return_story_done() -> void:
	settings["first_return_story_seen"] = true
	settings["intro_seen"] = true
	_checkpoint()
	_show_hut()

func _show_hut() -> void:
	if run.get("phase", "") == "hub":
		run = {}
		battle = {}
	_begin_screen("hut")
	_music("music.hut")
	$TitleBackground.hide()
	$Asui.hide()
	var town: Control = TownScene.instantiate()
	town.commissions_requested.connect(_invoke.bind(_show_commissions))
	town.album_requested.connect(_invoke.bind(_show_album))
	town.prepare_requested.connect(_invoke.bind(_show_prepare))
	town.title_requested.connect(_invoke.bind(_show_title))
	town.settings_requested.connect(_invoke.bind(_show_settings))
	_content.add_child(town)
	# Preserve earned memories and knot callbacks without the old code-drawn
	# portrait frames. Nothing here changes or manufactures permanent progress.
	for index: int in range(meta.get("memorials", []).size()):
		var id: String = str(meta["memorials"][index])
		var memorial: Button = _button(town, str(ContentCatalog.entry(id).get("name", "")), Rect2(12 + index * 94, 326, 88, 24), _memorial.bind(id), "Memorial%d" % index)
		memorial.tooltip_text = "回看归还故事"
	if bool(meta.get("knot_found", false)):
		var knot: Button = _button(town, "绳结", Rect2(552, 326, 76, 24), _banter_event.bind("knot_hover", {}), "ReturnKnot")
		knot.tooltip_text = t("knot_hint")
	_banter_event("hub_enter", {"first_visit": not settings.get("hut_seen", false), "last_end": {"voluntary": "pull_home", "defeat": "pull_home", "boss": "boss_victory"}.get(str(meta.get("last_end_reason", "")), "")})
	settings["hut_seen"] = true
	_checkpoint()

func _memorial(id: String) -> void:
	if id.is_empty(): return
	var definition: Dictionary = ContentCatalog.entry(id)
	_show_story({"id": definition.get("return_story_id", ""), "keepsake_id": id, "wish": str(definition.get("replica_plus_card_id", "")) in meta.get("replica_cards", [])}, _show_hut)

func _hotspot(parent: Node, text: String, rect: Rect2, callback: Callable, node_name: String) -> Button:
	var button: Button = _button(parent, "", rect, callback, node_name)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.tooltip_text = text
	if not text.is_empty():
		var tag: Panel = UI.frame(button, "HotspotTag", Rect2(4, rect.size.y - 24, rect.size.x - 8, 24))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UI.label(tag, text, Rect2(6, 4, rect.size.x - 20, 18), UI.WARM)
	return button

func _scene_background(id: String) -> void:
	if AssetCatalog.has_asset(id):
		UI.texture(_content, AssetCatalog, id, Rect2(0, 0, 640, 360))

func _show_commissions() -> void:
	_begin_screen("commissions")
	var page: Panel = _page(t("commissions"))
	UI.paragraph(page, t("commission_hint"), Rect2(24, 50, 560, 36), UI.MUTED)
	var available: Array = run_rules.available_commissions(meta)
	if available.is_empty():
		UI.paragraph(page, t("no_commissions"), Rect2(24, 110, 550, 60))
	for index: int in range(available.size()):
		var id: String = str(available[index])
		var definition: Dictionary = ContentCatalog.entry(id)
		var card: Panel = UI.frame(page, "Commission%d" % index, Rect2(24 + index * 190, 86, 178, 200))
		card.add_theme_stylebox_override("panel", SimpleUI.style("ui.r3_simple_panel"))
		UI.label(card, str(definition.get("owner_name", "")), Rect2(26, 20, 126, 18), UI.INK)
		UI.label(card, str(definition.get("name", "")), Rect2(26, 42, 126, 18), UI.INK)
		UI.paragraph(card, str(definition.get("commission_text", "")), Rect2(26, 66, 126, 80), UI.INK)
		_button(card, t("selected") if id in selected_commissions else t("accept"), Rect2(22, 152, 134, 28), _toggle_commission.bind(id))
	_button(page, t("back"), Rect2(24, 294, 150, 28), _show_hut)
	_button(page, t("prepare"), Rect2(428, 294, 150, 28), _show_prepare)

func _toggle_commission(id: String) -> void:
	if id in selected_commissions:
		selected_commissions.erase(id)
	else:
		var max_count: int = 2 if "double_commission" in meta.get("services", []) else 1
		if selected_commissions.size() < max_count:
			selected_commissions.append(id)
	_show_commissions()

func _show_prepare() -> void:
	var available: Array = run_rules.available_commissions(meta)
	selected_commissions = selected_commissions.filter(func(id: String) -> bool: return id in available)
	if selected_commissions.is_empty() and not available.is_empty():
		selected_commissions = [available[0]]
	_begin_screen("prepare")
	var page: Panel = _page(t("prepare"))
	UI.paragraph(page, t("return_hint"), Rect2(24, 52, 544, 32), UI.MUTED)
	for index: int in range(selected_commissions.size()):
		var item: Dictionary = ContentCatalog.entry(str(selected_commissions[index]))
		var card: Panel = UI.frame(page, "Prepared%d" % index, Rect2(24 + index * 288, 94, 268, 132))
		card.add_theme_stylebox_override("panel", SimpleUI.style("ui.r3_simple_panel"))
		UI.label(card, str(item.get("owner_name", "")) + " · " + str(item.get("name", "")), Rect2(26, 20, 216, 22), UI.INK)
		UI.paragraph(card, str(item.get("commission_text", "")), Rect2(26, 48, 216, 40), UI.INK)
		UI.label(card, t("unknown_wish"), Rect2(26, 94, 216, 18), UI.INK)
	if selected_commissions.is_empty():
		UI.paragraph(page, t("no_commissions"), Rect2(24, 106, 550, 60))
	_button(page, t("commissions"), Rect2(24, 258, 162, 38), _show_commissions)
	_button(page, t("descend"), Rect2(402, 258, 176, 38), _start_run)

func _start_run() -> void:
	if bool(settings.get("first_run_flow", false)) and run_rules.requires_first_run(meta):
		_start_opening()
		return
	var seed_value: int = _debug_seed if _debug_seed >= 0 else int(Time.get_unix_time_from_system()) + int(meta.get("runs_started", 0))
	var result: Dictionary = run_rules.start_run(meta, selected_commissions, seed_value)
	if not result.get("ok", false):
		_notice = t("invalid")
		return
	run = result["run"]
	_banter.begin_run(seed_value)
	battle = {}
	_last_events = result.get("events", [])
	_route_phase()

func _route_phase() -> void:
	if run_rules.is_first_run(run): _checkpoint()
	while not _last_events.is_empty():
		var presentation: Dictionary = _last_events.pop_front()
		if presentation.get("type") == "story" and ContentCatalog.has_entry(str(presentation.get("id", ""))):
			_show_story({"id": presentation["id"]}, _route_phase)
			return
		if presentation.get("type") == "replica_unlocked":
			_show_stamp(str(presentation.get("id", "")))
			return
		if presentation.get("type") == "keepsake_returned":
			_pending_return_id = str(presentation.get("id", ""))
		if presentation.get("type") in ["keepsake_get", "wish_done"]:
			_show_reveal(presentation)
			return
	match str(run.get("phase", "hub")):
		"departure": _show_departure()
		"path":
			_checkpoint()
			_show_path()
		"battle_ready": _start_battle()
		"battle": _show_battle()
		"defeat": _show_defeat()
		"node": _show_node()
		"reward": _show_rewards()
		"replacement": _show_replacement()
		"return":
			_checkpoint()
			_show_return()
		_: _finish_first_return()

func _show_departure() -> void:
	_begin_screen("departure")
	var page: Panel = _page(t("departure"))
	var offers: Array = run.get("departure_offers", [])
	for index: int in range(offers.size()):
		_item_card(page, str(offers[index]), Rect2(70 + index * 260, 78, 216, 208), _choose_departure.bind(index))

func _choose_departure(index: int) -> void:
	_last_events = run_rules.choose_departure(run, index)
	_route_phase()

func _show_path() -> void:
	_begin_screen("path")
	_music("music.descent")
	_banter_event("path_open", {})
	var segment: int = int(run.get("segment", 1))
	var depth_count: int = run.get("path", []).size()
	var heading: Button = _button(_content, t("segment", {"segment": segment}).replace("/ 7", "/ " + str(depth_count)), Rect2(16, 12, 192, 28), func() -> void: pass, "MapHeading")
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# These controls enumerate the real route (four OR seven), independent of
	# the number of decorative landings painted in the model scene behind them.
	var row_step: float = 230.0 / float(maxi(1, depth_count - 1))
	for index: int in range(depth_count):
		var visited: bool = run.get("history", []).any(func(record: Dictionary) -> bool: return int(record.get("segment", 0)) == index + 1)
		var slot: Button = _button(_content, ("已" if visited else "") + str(index + 1), Rect2(300, 52 + index * row_step, 40, 24), func() -> void: pass, "Depth%d" % index)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if index + 1 == segment: slot.add_theme_stylebox_override("normal", SimpleUI.style("ui.r3_simple_button_hover"))
	var hero_position: Vector2 = Vector2(266, 40 + maxi(0, segment - 1) * row_step)
	var hero: TextureRect = UI.texture(_content, AssetCatalog, "char.r3_simple_asui", Rect2(hero_position, Vector2(32, 40)))
	hero.name = "MapAsui"
	hero.size = Vector2(32, 40)
	if not presentation_fast and segment > 1:
		hero.position.y -= row_step
		hero.create_tween().tween_property(hero, "position", hero_position, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var choices: Array = run_rules.path_choices(run)
	for index: int in range(choices.size()):
		var choice: Dictionary = choices[index]
		var column_x: float = 24 + index * 396
		_map_choice_art(choice, column_x, index)
		var card: Button = _button(_content, "", Rect2(column_x, 142, 196, 116), _choose_path.bind(index), "Path%d" % index)
		for state_name: String in ["normal", "hover", "pressed"]:
			var panel_skin: StyleBoxTexture = SimpleUI.style("ui.r3_simple_panel")
			if state_name == "hover": panel_skin.modulate_color = Color(1.08, 1.08, 1.08)
			card.add_theme_stylebox_override(state_name, panel_skin)
		var definition: Dictionary = ContentCatalog.entry(str(choice.get("id", "")))
		var type_name: String = _node_type_text(str(choice.get("type", "")))
		var heading_text: String = str(definition.get("name", type_name))
		var preview_text: String = str(choice.get("hint", ""))
		if preview_text == heading_text: preview_text = str(definition.get("description", "")).split("。")[0]
		UI.label(card, heading_text, Rect2(26, 20, 144, 20), UI.INK)
		UI.paragraph(card, preview_text, Rect2(26, 48, 144, 48), UI.INK)
		var marker_row: int = 0
		for kind: String in ["star_ids", "heart_ids"]:
			var names: Array[String] = []
			for id: String in choice.get(kind, []):
				var item: Dictionary = ContentCatalog.entry(id)
				names.append(str(item.get("owner_name" if kind == "star_ids" else "name", "")))
			if not names.is_empty():
				var marker: Button = _button(card, ("失物：" if kind == "star_ids" else "心愿：") + " / ".join(names), Rect2(0, 120 + marker_row * 24, 196, 24), func() -> void: pass, "RouteMarker%d" % marker_row)
				marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
				marker_row += 1
		card.tooltip_text = type_name + "\n" + _node_preview(choice) + "\n" + str(choice.get("hint", ""))
		var resting: Vector2 = card.position
		card.mouse_entered.connect(func() -> void: card.position = resting - Vector2(0, 3))
		card.mouse_exited.connect(func() -> void: card.position = resting)
	_run_bar(_content, 326)
	if not run_rules.is_first_run(run):
		_button(_content, t("home"), Rect2(480, 320, 144, 30), _end_run.bind("voluntary"))

func _map_choice_art(choice: Dictionary, column_x: float, choice_index: int) -> void:
	var scene_art: String = "board.r3_simple_soap_tub" if choice.get("id") == "event.soap_tub" else ("board.r3_simple_campfire" if choice.get("type") == "campfire" else "")
	if not scene_art.is_empty() and AssetCatalog.has_asset(scene_art):
		var thumbnail: TextureRect = UI.texture(_content, AssetCatalog, scene_art, Rect2(column_x, 44, 196, 110))
		thumbnail.name = "MapThumb%d" % choice_index
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# UI.texture sets its target size before expand mode. A large source can
		# leave a cached intrinsic size, so contract it explicitly afterwards.
		thumbnail.size = Vector2(196, 110)
		thumbnail.set_meta("allocated_rect", Rect2(column_x, 44, 196, 110))
		return
	var actors: Dictionary = {"enemy.wet_sock": "enemy.r3_simple_wet_sock", "enemy.lint_bug": "enemy.r3_simple_lint_bug", "elite.hungry_drawer": "elite.r3_simple_hungry_drawer"}
	var enemy_ids: Array = ContentCatalog.entry(str(choice.get("id", ""))).get("enemies", [])
	var side: float = 64.0 if enemy_ids.size() <= 2 else 40.0
	var total: float = enemy_ids.size() * side + maxi(0, enemy_ids.size() - 1) * 4
	for index: int in range(enemy_ids.size()):
		var art: String = str(actors.get(str(enemy_ids[index]), ""))
		if not art.is_empty() and AssetCatalog.has_asset(art):
			var rectangle: Rect2 = Rect2(column_x + (196 - total) / 2.0 + index * (side + 4), 132 - side, side, side)
			var actor: TextureRect = UI.texture(_content, AssetCatalog, art, rectangle)
			actor.name = "MapThumbEnemy%d_%d" % [choice_index, index]
			actor.size = rectangle.size
			actor.set_meta("allocated_rect", rectangle)

func _node_type_text(type_name: String) -> String:
	var key: String = {"battle": "battle", "elite": "elite", "boss": "boss", "event": "event", "campfire": "camp", "trade": "trade"}.get(type_name, "event")
	return t(key)

func _node_preview(node: Dictionary) -> String:
	var definition: Dictionary = ContentCatalog.entry(str(node.get("id", "")))
	if definition.has("enemies"):
		var names: Array[String] = []
		for enemy_id: String in definition["enemies"]:
			names.append(str(ContentCatalog.entry(enemy_id).get("name", "")))
		return " · ".join(names)
	return str(definition.get("name", node.get("hint", "")))

func _run_bar(parent: Node, y: int) -> void:
	UI.label(parent, t("hp", {"hp": run.get("hp", 0), "max": run.get("max_hp", 0)}), Rect2(24, y, 130, 18), UI.BLUE)
	var short_route: bool = run_rules.is_first_run(run)
	if not short_route or not run.get("relics", []).is_empty():
		var relic: Button = _button(parent, t("relics") + " " + str(run.get("relics", []).size()), Rect2(158, y - 5, 76, 28), _show_inventory.bind("relics"))
		relic.tooltip_text = _inventory_text("relics")
	if not short_route or not run.get("keepsakes", []).is_empty():
		var keepsake: Button = _button(parent, t("keepsakes") + " " + str(run.get("keepsakes", []).size()), Rect2(238, y - 5, 76, 28), _show_inventory.bind("keepsakes"))
		keepsake.tooltip_text = _inventory_text("keepsakes")
	if not short_route or int(run.get("stats", {}).get("battles", 0)) >= 2:
		_button(parent, t("deck"), Rect2(318, y - 5, 76, 28), _show_pile.bind("deck"))

func _choose_path(index: int) -> void:
	_cue("sfx.path_flip")
	_last_events = run_rules.choose_path(run, index)
	_route_phase()

func _start_battle() -> void:
	_checkpoint()
	var result: Dictionary = run_rules.start_battle(run, battle_rules)
	battle = result.get("state", {})
	_last_events = result.get("events", [])
	if battle.is_empty():
		_notice = t("invalid")
		_show_title()
		return
	_checkpoint()
	_banter.begin_battle()
	_show_battle()
	if screen != "r2_battle":
		_banter_events(_last_events)
		_show_enemy_intro()

func _show_battle() -> void:
	if run_rules.is_first_run(run) and not battle.get("tutorial", {}).is_empty():
		_show_integrated_tutorial()
		return
	_begin_screen("battle")
	_music("music.boss" if run.get("current_node", {}).get("type") == "boss" else "music.battle")
	var board: Control = Control.new()
	board.name = "BattleBoard"
	board.size = Vector2(640, 360)
	_content.add_child(board)
	var board_id: String = "board.sock_lair" if run.get("current_node", {}).get("type") == "boss" else "board.sock_swamp"
	if AssetCatalog.has_asset(board_id):
		UI.texture(board, AssetCatalog, board_id, Rect2(0, 0, 640, 360))
	_battle_view = BattleView.new()
	_battle_view.name = "BattleView"
	_battle_view.size = Vector2(640, 360)
	_battle_view.configure(battle_rules, battle, _battle_command, _show_pile, _show_pause)
	_battle_view.instant_presentation = presentation_fast
	_battle_view.first_run_presentation = run_rules.is_first_run(run)
	_battle_view.decoration_counts = _decoration_counts
	_battle_view.decoration_saved = settings.get("decoration_once", {})
	_battle_view.on_decoration = _decoration_event
	board.add_child(_battle_view)
	_battle_view.present_events(_last_events)

func _battle_command(action: Dictionary) -> void:
	if not _focused or screen != "battle" or _overlay != null or (not presentation_fast and _clock < _lock_until):
		return
	var legal: Array = battle_rules.legal_actions(battle)
	if not legal.has(action):
		return
	_banter_pending.clear()
	if action.get("type") == "play_card":
		_last_events = battle_rules.play_card(battle, int(action["hand_index"]), int(action.get("target_index", -1)), action.get("choices", {}))

	else:
		_last_events = battle_rules.end_turn(battle, int(action.get("keep_index", -1)))

	_idle_time = 0.0
	var events: Array = _last_events.duplicate(true)
	_show_battle()
	_banter_events(events)
	if battle.get("status") in ["victory", "defeat"]:
		_last_events = run_rules.complete_battle(run, meta, battle, events)
		if presentation_fast:
			_route_phase()
		else:
			_lock_until = maxf(_lock_until, _clock + _battle_view.presentation_duration)
			_pending_terminal = true
			_terminal_at = _clock + maxf(0.55, _battle_view.presentation_duration)
			_terminal_serial = _transition_serial
	elif not presentation_fast:
		_lock_until = maxf(_lock_until, _clock + _battle_view.presentation_duration)

func _show_defeat() -> void:
	_begin_screen("defeat")
	var page: Panel = _page(t("defeat"))
	UI.paragraph(page, ContentCatalog.text("ui.d1.defeat_hint") if ContentCatalog.has_entry("ui.d1.defeat_hint") else t("tutorial"), Rect2(64, 72, 486, 90))
	_button(page, t("retry"), Rect2(64, 204, 218, 52), _retry_battle)
	_button(page, t("home"), Rect2(326, 204, 218, 52), _end_run.bind("defeat"))

func _retry_battle() -> void:
	var result: Dictionary = run_rules.retry_battle(run, battle_rules, battle)
	if result.get("state", {}).is_empty(): return
	battle = result["state"]
	_last_events = result.get("events", [])
	_banter.begin_battle()
	_checkpoint()
	_show_battle()
	if screen != "r2_battle":
		_banter_events(_last_events)
		_banter_event("retry", {})

func _show_rewards() -> void:
	_begin_screen("reward")
	_cue("sting.reward")
	_banter_event("reward_open", {})
	var heading: Button = _button(_content, t("reward"), Rect2(252, 24, 136, 30), func() -> void: pass, "RewardHeading")
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var offers: Array = run_rules.reward_choices(run)
	for index: int in range(offers.size()):
		_item_card(_content, str(offers[index]["id"]), Rect2(24 + index * 200, 78, 192, 236), _choose_reward.bind(index))
	_button(_content, t("skip"), Rect2(504, 322, 112, 28), _choose_reward.bind(-1))
	call_deferred("_simple_page_ink", _content)

func _item_card(parent: Node, id: String, rect: Rect2, callback: Callable) -> void:
	var definition: Dictionary = ContentCatalog.entry(id)
	var card: Button = _button(parent, "", rect, callback)
	var model_art: String = SimpleUI.card_art(str(definition.get("art", ""))) if _uses_simple_ui() else ""
	if not model_art.is_empty() and definition.has("cost") and AssetCatalog.has_asset("ui.r3_v2_card"):
		for state_name: String in ["normal", "hover", "pressed"]:
			var paper: StyleBoxTexture = SimpleUI.style("ui.r3_v2_card")
			if state_name == "hover": paper.modulate_color = Color(1.04, 1.04, 1.04)
			card.add_theme_stylebox_override(state_name, paper)
		UI.label(card, str(int(definition["cost"])), Rect2(16, 12, 40, 34), UI.INK, 24)
		UI.label(card, t("type_" + str(definition.get("type", "special"))), Rect2(rect.size.x - 76, 18, 60, 20), UI.INK)
		UI.texture(card, AssetCatalog, model_art, Rect2((rect.size.x - 112) / 2.0, 48, 112, 78))
		UI.label(card, str(definition.get("name", "")), Rect2(18, 138, rect.size.x - 36, 24), UI.INK, 16)
		UI.paragraph(card, str(definition.get("text", "")), Rect2(18, 168, rect.size.x - 36, 60), UI.INK)
		card.tooltip_text = str(definition.get("text", ""))
		return
	if _uses_simple_ui():
		for state_name: String in ["normal", "hover", "pressed"]:
			var model_panel: StyleBoxTexture = SimpleUI.style("ui.r3_simple_panel")
			if state_name == "hover": model_panel.modulate_color = Color(1.08, 1.08, 1.08)
			card.add_theme_stylebox_override(state_name, model_panel)
	var item_illustration: String = SimpleUI.item_art(str(definition.get("art", ""))) if _uses_simple_ui() else ""
	if not definition.has("cost") and not item_illustration.is_empty():
		UI.paragraph(card, str(definition.get("name", "")), Rect2(26, 22, rect.size.x - 52, 22), UI.INK)
		UI.texture(card, AssetCatalog, item_illustration, Rect2((rect.size.x - 72) / 2.0, 48, 72, 72))
		UI.paragraph(card, str(definition.get("text", "")), Rect2(26, 128, rect.size.x - 52, 60), UI.INK)
		UI.paragraph(card, str(definition.get("flavor", "")), Rect2(26, 194, rect.size.x - 52, 24), UI.INK)
		card.tooltip_text = str(definition.get("text", ""))
		return
	var art: String = str(definition.get("art", ""))
	if not model_art.is_empty():
		UI.texture(card, AssetCatalog, model_art, Rect2((rect.size.x - 80) / 2.0, 50, 80, 56))
	elif not _uses_simple_ui() and AssetCatalog.has_asset(art):
		UI.texture(card, AssetCatalog, art, Rect2(rect.size.x - 40, 12, 24, 24) if not definition.has("cost") else Rect2(rect.size.x - 52, 10, 40, 28))
	UI.paragraph(card, str(definition.get("name", "")), Rect2(26, 22, rect.size.x - 52, 24 if not model_art.is_empty() else 38) if _uses_simple_ui() else Rect2(12, 12, rect.size.x - 64, 38), UI.WARM)
	if definition.has("cost"):
		UI.label(card, t("view_card", {"cost": definition["cost"], "type": t("type_" + str(definition.get("type", "special")))}), Rect2(26, 112 if not model_art.is_empty() else 50, rect.size.x - 52, 18) if _uses_simple_ui() else Rect2(12, 44, rect.size.x - 24, 18), UI.BLUE)
	UI.paragraph(card, str(definition.get("text", "")), Rect2(26, 140 if not model_art.is_empty() else 76, rect.size.x - 52, 68) if _uses_simple_ui() else Rect2(12, 70, rect.size.x - 24, 74))
	if not str(definition.get("flavor", "")).is_empty():
		UI.paragraph(card, str(definition.get("flavor", "")), Rect2(26, 156, rect.size.x - 52, 50) if _uses_simple_ui() else Rect2(12, 148, rect.size.x - 24, 46), UI.MUTED)

func _choose_reward(index: int) -> void:
	_last_events = run_rules.choose_reward(run, index)
	_route_phase()

func _show_replacement() -> void:
	_begin_screen("replacement")
	var page: Panel = _page(t("replace"))
	var deck: Array = run.get("deck", [])
	for index: int in range(deck.size()):
		var definition: Dictionary = ContentCatalog.entry(str(deck[index]))
		var button: Button = _button(page, str(definition.get("name", "")), Rect2(24 + (index % 4) * 142, 68 + int(index / 4) * 58, 132, 50), _replace_card.bind(index))
		button.tooltip_text = str(definition.get("text", ""))
	_button(page, t("cancel"), Rect2(428, 280, 150, 28), _cancel_replace)

func _replace_card(index: int) -> void:
	_last_events = run_rules.replace_card(run, index)
	_route_phase()

func _cancel_replace() -> void:
	_last_events = run_rules.cancel_replacement(run)
	_route_phase()

func _show_node() -> void:
	if run.get("current_node", {}).get("type") == "trade":
		_show_trade()
		return
	_begin_screen("node")
	var node: Dictionary = run.get("current_node", {})
	if node.get("type") == "campfire":
		_show_simple_campfire()
		return
	var definition: Dictionary = ContentCatalog.entry(str(node.get("id", "")))
	if node.get("id") == "event.soap_tub" and AssetCatalog.has_asset("board.r3_simple_soap_tub"):
		_show_simple_soap(definition)
		return
	var heading: Button = _button(_content, str(definition.get("name", _node_type_text(str(node.get("type", "event"))))), Rect2(220, 16, 200, 28), func() -> void: pass, "EventHeading")
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var description: Panel = UI.frame(_content, "EventDescription", Rect2(116, 58, 408, 116))
	UI.paragraph(description, str(definition.get("description", node.get("hint", ""))), Rect2(28, 24, 352, 68), UI.INK)
	var choices: Array = run_rules.node_choices(run)
	for index: int in range(choices.size()):
		var choice: Dictionary = choices[index]
		var button: Button = _button(_content, str(choice.get("text", "")), Rect2(56, 190 + index * 40, 528, 34), _choose_node.bind(str(choice["id"])), "EventChoice%d" % index)
		var preview: Dictionary = choice.get("preview", {})
		button.tooltip_text = t("hp", {"hp": preview.get("hp", run.get("hp", 0)), "max": preview.get("max_hp", run.get("max_hp", 0))})
	_run_bar(_content, 326)

func _show_simple_soap(definition: Dictionary) -> void:
	_scene_background("board.r3_simple_soap_tub")
	var heading: Button = _button(_content, str(definition.get("name", "")), Rect2(400, 12, 224, 28), func() -> void: pass, "EventHeading")
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var description: Panel = UI.frame(_content, "EventDescription", Rect2(16, 62, 216, 120))
	UI.paragraph(description, str(definition.get("description", "")), Rect2(26, 22, 164, 76), UI.INK)
	var choices: Array = run_rules.node_choices(run)
	for index: int in range(choices.size()):
		var choice: Dictionary = choices[index]
		var option: Button = _button(_content, str(choice.get("text", "")), Rect2(24 + index * 308, 286, 284, 68), _choose_node.bind(str(choice["id"])), "EventChoice%d" % index)
		option.clip_text = true
		# UI.button adds the control before this screen enables clipping; Godot
		# may already have expanded it to the original full-caption minimum.
		option.size = Vector2(284, 68)
		for state_name: String in ["normal", "hover", "pressed"]:
			var skin: StyleBoxTexture = SimpleUI.style("ui.r3_simple_panel")
			if state_name == "hover": skin.modulate_color = Color(1.08, 1.08, 1.08)
			option.add_theme_stylebox_override(state_name, skin)
		# Keep semantic Button.text for the existing input/capture contracts;
		# the independent label wraps its real caption inside the model panel.
		for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			option.add_theme_color_override(color_name, Color.TRANSPARENT)
		UI.paragraph(option, str(choice.get("text", "")), Rect2(26, 16, 232, 40), UI.INK)
		var preview: Dictionary = choice.get("preview", {})
		option.tooltip_text = t("hp", {"hp": preview.get("hp", run.get("hp", 0)), "max": preview.get("max_hp", run.get("max_hp", 0))})
	_run_bar(_content, 18)

func _show_simple_campfire() -> void:
	_scene_background("board.r3_simple_campfire")
	var heading: Button = _button(_content, _node_type_text("campfire"), Rect2(268, 16, 104, 28), func() -> void: pass, "CampfireHeading")
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hp: Button = _button(_content, t("hp", {"hp": run.get("hp", 0), "max": run.get("max_hp", 0)}), Rect2(16, 16, 132, 28), func() -> void: pass, "CampfireHealth")
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var choices: Array = run_rules.node_choices(run)
	for index: int in range(choices.size()):
		var choice: Dictionary = choices[index]
		var option: Button = _button(_content, str(choice.get("text", "")), Rect2(38 + index * 306, 278, 258, 66), _choose_node.bind(str(choice["id"])), "CampfireChoice%d" % index)
		for state_name: String in ["normal", "hover", "pressed"]:
			var skin: StyleBoxTexture = SimpleUI.style("ui.r3_simple_panel")
			if state_name == "hover": skin.modulate_color = Color(1.08, 1.08, 1.08)
			option.add_theme_stylebox_override(state_name, skin)
		for color_name: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			option.add_theme_color_override(color_name, UI.INK)
		var preview: Dictionary = choice.get("preview", {})
		option.tooltip_text = t("hp", {"hp": preview.get("hp", run.get("hp", 0)), "max": preview.get("max_hp", run.get("max_hp", 0))})
		if not run.get("keepsakes", []).is_empty() and choice.get("ops", []).any(func(op: Dictionary) -> bool: return op.get("op") == "complete_wish"):
			UI.texture(option, AssetCatalog, "ui.r3_simple_icon_heart", Rect2(120, -21, 18, 18))

func _choose_node(id: String) -> void:
	_last_events = run_rules.choose_node(run, id, meta)
	_route_phase()

func _end_run(reason: String) -> void:
	_last_events = run_rules.end_run(run, meta, reason)
	_route_phase()

func _show_return() -> void:
	var record: Dictionary = run_rules.pending_story(run)
	if record.is_empty():
		_route_phase()
		return
	_show_story(record, _return_story_done)

func _return_story_done() -> void:
	_last_events = run_rules.acknowledge_story(run, meta, str(_story_record.get("id", "")))
	_checkpoint()
	_route_phase()

func _show_story(record: Dictionary, done: Callable) -> void:
	_story_token += 1
	_story_completed = false
	_story_record = record.duplicate(true)
	_story_done = done
	var conditions: Dictionary = {"wishes": run.get("wishes", {}).duplicate(true), "card_id": record.get("card_id", "")}
	if record.has("keepsake_id"):
		conditions["wishes"][record["keepsake_id"]] = bool(record.get("wish", false))
	_music("music.ending" if record.get("id") == "story.ending" else ("music.title_full" if record.get("id") == "story.intro" else "music.return"))
	var definition: Dictionary = ContentCatalog.entry(str(record.get("id", "")))
	if record.has("page_indices"):
		var selected_pages: Array = []
		for index: int in record["page_indices"]:
			if index >= 0 and index < definition.get("pages", []).size(): selected_pages.append(definition["pages"][index])
		definition["pages"] = selected_pages
	_story.begin(definition, conditions)
	if _story.finished():
		done.call()
	else:
		_render_story()

func _render_story() -> void:
	_story_token += 1
	_begin_screen("story")
	_story_view = StoryView.new()
	_story_view.name = "IllustratedStory"
	_story_view.size = Vector2(640, 360)
	_story_view.configure(_story.current(), float(settings.get("text_speed", 30)), presentation_fast or bool(settings.get("instant_text", false)))
	_content.add_child(_story_view)
	_button(_content, t("skip"), Rect2(512, 12, 112, 28), _skip_story.bind(_story_token))
	UI.label(_content, str(_story.index + 1) + " / " + str(_story.pages.size()), Rect2(58, 324, 100, 20), UI.MUTED)

	_button(_content, t("next"), Rect2(456, 318, 128, 30), _next_story.bind(_story_token))

func _next_story(expected_token: int = -1) -> void:
	if _story_completed or (expected_token >= 0 and expected_token != _story_token): return
	if _story_view != null and not _story_view.revealed:
		_story_view.reveal()
		return
	_cue("sfx.page_turn")
	if _story.advance():
		_finish_story()
	else:
		_render_story()

func _skip_story(expected_token: int = -1) -> void:
	if _story_completed or screen != "story" or (expected_token >= 0 and expected_token != _story_token): return
	_story.skip()
	_finish_story()

func _finish_story() -> void:
	if _story_completed: return
	_story_completed = true
	var done: Callable = _story_done
	_story_done = Callable()
	if done.is_valid(): done.call()

func _show_album() -> void:
	_begin_screen("album")
	var page: Panel = _page(t("album"))
	var ids: Array = meta.get("replica_cards", []).duplicate()
	ids.append_array(meta.get("seen_relics", []))
	if ids.is_empty():
		UI.paragraph(page, t("empty_album"), Rect2(36, 92, 530, 80))
	var offset: int = _album_page * 6
	for index: int in range(mini(6, ids.size() - offset)):
		var id: String = str(ids[offset + index])
		var definition: Dictionary = ContentCatalog.entry(id)
		var card: Panel = UI.frame(page, "Album%d" % index, Rect2(24 + (index % 3) * 192, 60 + int(index / 3) * 118, 180, 112))
		var art: String = SimpleUI.item_art(str(definition.get("art", "")))
		var is_card: bool = definition.has("cost")
		if not art.is_empty():
			var illustration: TextureRect = UI.texture(card, AssetCatalog, art, Rect2(114 if is_card else 132, 18, 40 if is_card else 24, 24))
			illustration.size = Vector2(40 if is_card else 24, 24)
		UI.label(card, str(definition.get("name", "")), Rect2(26, 20, (82 if is_card else 102) if not art.is_empty() else 130, 20), UI.INK)
		var effect: Label = UI.paragraph(card, str(definition.get("text", "")), Rect2(26, 44, 130, 48), UI.INK)
		effect.add_theme_constant_override("line_spacing", 0)
		card.tooltip_text = str(definition.get("text", ""))
	_button(page, t("back"), Rect2(24, 294, 142, 28), _show_hut)
	if ids.size() > 6:
		_button(page, t("next"), Rect2(436, 294, 142, 28), func() -> void:
			_album_page = (_album_page + 1) % int(ceil(float(ids.size()) / 6.0))
			_show_album())

func _inventory_text(kind: String) -> String:
	var lines: Array[String] = []
	for id: String in run.get(kind, []):
		var item: Dictionary = ContentCatalog.entry(id)
		var line: String = str(item.get("name", "")) + " · " + str(item.get("text", ""))
		if kind == "keepsakes":
			line += "\n" + (t("wish_done") if run.get("wishes", {}).get(id, false) else str(item.get("wish", {}).get("text", "")))
		lines.append(line)
	return "\n\n".join(lines)

func _show_inventory(kind: String) -> void:
	_show_message(t(kind), _inventory_text(kind))

func _show_pile(kind: String) -> void:
	var pile: Array = run.get("deck", []) if kind == "deck" else battle.get(kind, [])
	var lines: Array[String] = []
	for instance: Variant in pile:
		var id: String = str(instance.get("id", "")) if instance is Dictionary else str(instance)
		var definition: Dictionary = ContentCatalog.entry(id)
		lines.append(str(definition.get("name", "")) + " · " + str(definition.get("text", "")))
	_show_message(t("deck") if kind == "deck" else t("discard_pile" if kind == "discard" else "draw_pile", {"count": pile.size()}), "\n".join(lines) if not lines.is_empty() else t("no_cards"))

func _modal(heading: String) -> Panel:
	_close_overlay()
	if _story_view != null: _story_view.suspend(true)
	if _content != null: _content.process_mode = Node.PROCESS_MODE_DISABLED
	_modal_shield = Control.new()
	_modal_shield.name = "ModalInputShield"
	_modal_shield.size = Vector2(640, 360)
	_modal_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal_shield)
	_overlay = UI.frame(self, "Modal", Rect2(66, 28, 508, 304))
	if _uses_simple_ui() or screen in ["opening", "r2_battle"]:
		_overlay.theme = SimpleUI.theme() if _uses_simple_ui() else GeneratedUI.theme()
		call_deferred("_r2_overlay_ink", _overlay)
	UI.label(_overlay, heading, Rect2(28 if _uses_simple_ui() else 18, 24 if _uses_simple_ui() else 16, 452, 24), UI.WARM)
	_ready_frame = Engine.get_process_frames() + 1
	return _overlay

func _r2_overlay_ink(panel: Panel) -> void:
	if not is_instance_valid(panel) or panel.is_queued_for_deletion(): return
	# Generated R2 panels have pale, quiet interiors. This local overlay-only
	# ink pass leaves every historical screen's own theme and logic untouched.
	for label: Node in panel.find_children("*", "Label", true, false):
		label.add_theme_color_override("font_color", Color("1b1622"))

func _show_message(heading: String, body: String) -> void:
	var modal: Panel = _modal(heading)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(28, 60) if _uses_simple_ui() else Vector2(18, 52)
	scroll.size = Vector2(452, 188) if _uses_simple_ui() else Vector2(472, 196)
	modal.add_child(scroll)
	var label: Label = Label.new()
	label.text = body
	label.custom_minimum_size = Vector2(428 if _uses_simple_ui() else 448, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("line_spacing", 6)
	scroll.add_child(label)
	_button(modal, t("close"), Rect2(346, 260, 144, 30), _close_overlay)

func _close_overlay() -> void:
	if _modal_shield != null:
		_modal_shield.queue_free()
		_modal_shield = null
	if _content != null and _focused: _content.process_mode = Node.PROCESS_MODE_INHERIT
	if _story_view != null: _story_view.suspend(false)
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null

func _show_pause() -> void:
	var modal: Panel = _modal(t("pause"))
	UI.label(modal, t("seed", {"seed": run.get("seed", "—")}), Rect2(18, 46, 472, 22), UI.MUTED)
	UI.paragraph(modal, t("exit_checkpoint"), Rect2(18, 72, 472, 38), UI.MUTED)
	_button(modal, t("resume"), Rect2(18, 122, 224, 38), _close_overlay)
	_button(modal, t("settings"), Rect2(266, 122, 224, 38), _show_settings)
	_button(modal, t("title"), Rect2(18, 180, 224, 38), _pause_to_title)
	if screen == "path" and not run_rules.is_first_run(run):
		_button(modal, t("home"), Rect2(266, 180, 224, 38), _end_run.bind("voluntary"))

func _pause_to_title() -> void:
	_checkpoint()
	# Restore the exact persisted checkpoint before continuing in this process too.
	var saved: Dictionary = SaveService.load_state(_save_path)
	if saved.get("ok", false):
		var snapshot: Dictionary = saved["state"]
		meta = run_rules.normalize_meta(snapshot["meta"])
		meta.merge(snapshot["meta"], false)
		run = snapshot["run"] if snapshot["run"] is Dictionary else {}
		battle = {}
	_show_title()

func _confirm_reset() -> void:
	var modal: Panel = _modal(t("new_game"))
	UI.paragraph(modal, t("reset_warning"), Rect2(18, 62, 472, 72))
	_button(modal, t("cancel"), Rect2(18, 218, 224, 40), _close_overlay)
	_button(modal, t("confirm"), Rect2(266, 218, 224, 40), _reset_confirmed)

func _reset_confirmed() -> void:
	if _save_readonly:
		return
	meta = run_rules.new_meta()
	run = {}
	battle = {}
	selected_commissions.clear()
	settings["intro_seen"] = false
	for key: String in ["banter_once", "banter_run_once", "decoration_once", "intro_enemies", "hut_seen", "first_run_flow", "first_return_story_seen"]: settings.erase(key)
	_banter.configure(ContentCatalog.table("banter"))
	_tutorial_state = {}
	settings.erase("r2_tutorial")
	_checkpoint()
	_start_opening()

func _show_settings() -> void:
	var modal: Panel = _modal(t("settings"))
	for index: int in range(3):
		var key: String = ["master", "music", "sfx"][index]
		UI.label(modal, t(key), Rect2(28, 48 + index * 40, 100, 22))
		var slider: HSlider = HSlider.new()
		slider.position = Vector2(132, 48 + index * 40)
		slider.size = Vector2(338, 22)
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = float(settings.get(key, 0.8))
		slider.value_changed.connect(func(value: float) -> void:
			settings[key] = value
			_apply_settings())
		modal.add_child(slider)
	UI.label(modal, ContentCatalog.text("ui.d2.text_speed"), Rect2(28, 174, 100, 22))
	for index: int in range(4):
		var speed: int = [15, 30, 60, 9999][index]
		var label: String = ContentCatalog.text(["ui.d2.text_slow", "ui.d2.text_normal", "ui.d2.text_fast", "ui.d2.text_instant"][index])
		_button(modal, label, Rect2(132 + index * 84, 170, 78, 28), func() -> void:
			settings["text_speed"] = speed
			settings["instant_text"] = speed == 9999
			if _story_view != null:
				_story_view.characters_per_second = float(speed)
				if speed == 9999: _story_view.reveal())
	_button(modal, t("window") + " ×" + str(int(settings.get("window_scale", 2))), Rect2(18, 220, 220, 30), func() -> void: _cycle_window_size())
	_button(modal, t("fullscreen"), Rect2(266, 220, 224, 30), func() -> void:
		settings["fullscreen"] = get_window().mode != Window.MODE_FULLSCREEN
		get_window().mode = Window.MODE_FULLSCREEN if settings["fullscreen"] else Window.MODE_WINDOWED)
	_button(modal, ContentCatalog.text("ui.r2.controls"), Rect2(18, 260, 144, 30), _show_control_help)
	_button(modal, t("close"), Rect2(346, 260, 144, 30), func() -> void:
		_checkpoint()
		_close_overlay())

func _show_control_help() -> void:
	_checkpoint()
	_show_message(ContentCatalog.text("ui.r2.controls"), ContentCatalog.text("ui.r2.controls_body"))

func _apply_settings() -> void:
	AudioService.set_bus_volume("Master", float(settings.get("master", 1.0)))
	AudioService.set_bus_volume("Music", float(settings.get("music", 0.7)))
	AudioService.set_bus_volume("SFX", float(settings.get("sfx", 0.8)))
	AudioService.set_bus_volume("UI", float(settings.get("sfx", 0.8)))

func _checkpoint() -> bool:
	if _save_readonly:
		return false
	var snapshot: Dictionary = {"ok": true, "meta": meta.duplicate(true), "run": null}
	if not run.is_empty():
		snapshot = run_rules.safe_checkpoint(run, meta)
	if not snapshot.get("ok", false):
		return false
	settings["banter_once"] = _banter.saved_once.duplicate(true)
	settings["banter_run_once"] = _banter.run_once.duplicate(true)
	settings["banter_seed"] = int(run.get("seed", -1))
	var data: Dictionary = _save_extra.duplicate(true)
	data.merge({"version": 1, "meta": snapshot["meta"], "run": snapshot["run"], "settings": settings.duplicate(true)}, true)
	var result: Error = SaveService.save_state(data, _save_path)
	if result != OK:
		_notice = t("save_failed")
	return result == OK

func _unhandled_key_input(event: InputEvent) -> void:
	if not _focused or not event is InputEventKey or not event.pressed or event.echo or Engine.get_process_frames() < _ready_frame:
		return
	if _overlay != null:
		if event.keycode == KEY_ESCAPE:
			_close_overlay()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F2 and OS.is_debug_build():
		settings["instant_text"] = not bool(settings.get("instant_text", false))
		if _story_view != null: _story_view.reveal()
	elif event.keycode == KEY_F1 and OS.is_debug_build():
		_show_message(t("debug"), t("seed", {"seed": run.get("seed", "—")}) + "\n" + t("graybox"))
	elif screen == "r2_battle":
		return # BattleScene owns its card/target/pause keyboard handling.
	elif screen == "opening":
		if event.keycode == KEY_ESCAPE: _show_pause()
		else: return # OpeningScene owns its skippable dialogue/rope shortcut.
	elif screen == "r2_complete":
		if event.keycode == KEY_ESCAPE: _show_title()
	elif screen == "battle" and _battle_view != null:
		_battle_view.handle_key(event)
	elif screen == "stamp" and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_invoke(_route_phase)
	elif screen == "story" and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_invoke(_next_story)
	elif event.keycode == KEY_ESCAPE:
		if screen == "book":
			_show_title()
		elif screen != "title":
			_show_pause()
	elif screen == "title" and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_invoke(_resume_r2_or_legacy if _has_progress() else _start_opening)
	get_viewport().set_input_as_handled()

func _show_reveal(event: Dictionary) -> void:
	_begin_screen("reveal")
	var item: Dictionary = ContentCatalog.entry(str(event.get("id", "")))
	var wished: bool = event.get("type") == "wish_done"
	_cue("sting.wish" if wished else "sting.keepsake")
	_banter_event(str(event.get("type", "")), {"keepsake_id": event.get("id", "")})
	var page: Panel = _page(t("wish_title" if wished else "acquired_title"))
	var keepsake_art: String = SimpleUI.item_art(str(event.get("id", "")))
	_reveal_time = 0.0
	if not keepsake_art.is_empty():
		_reveal_origin = Vector2(54, 66)
		_reveal_icon = UI.texture(page, AssetCatalog, keepsake_art, Rect2(_reveal_origin, Vector2(48, 48)))
	else:
		_reveal_origin = Vector2(36, 76)
		_reveal_icon = UI.texture(page, AssetCatalog, "ui.r3_simple_station", Rect2(_reveal_origin, Vector2(112, 28)))
		var badge: Label = UI.label(_reveal_icon, "心愿完成" if wished else "找到失物", Rect2(0, 0, 112, 28), UI.WARM)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.set_meta("simple_dark_plate", true)
	UI.label(page, str(item.get("owner_name", "")) + " · " + str(item.get("name", "")), Rect2(170, 74, 408, 30), UI.INK, 24)
	UI.paragraph(page, str(item.get("text", "")), Rect2(36, 124, 540, 44))
	UI.paragraph(page, t("wish_done") if wished else str(item.get("wish", {}).get("name", "")) + " · " + str(item.get("wish", {}).get("text", "")), Rect2(36, 184, 540, 50), UI.BLUE)
	_button(page, t("next"), Rect2(428, 272, 150, 34), _route_phase)

func _show_trade() -> void:
	_begin_screen("node")
	var page: Panel = _page(t("trade"))
	if AssetCatalog.has_asset("event.trade"): UI.texture(page, AssetCatalog, "event.trade", Rect2(24, 54, 160, 90))
	UI.paragraph(page, t("trade_give"), Rect2(204, 62, 374, 48), UI.MUTED)
	_button(page, t("trade_relic"), Rect2(24, 158, 264, 48), _trade_inventory.bind("relic"))
	_button(page, t("trade_card"), Rect2(314, 158, 264, 48), _trade_inventory.bind("card"))
	var choices: Array = run_rules.node_choices(run)
	for choice: Dictionary in choices:
		_button(page, str(choice.get("text", "")), Rect2(24, 216, 554, 38), _choose_node.bind(str(choice["id"])))
	_run_bar(page, 286)

func _trade_inventory(kind: String) -> void:
	var modal: Panel = _modal(t("trade_give"))
	var items: Array = run.get("relics", []) if kind == "relic" else run.get("deck", [])
	if items.is_empty():
		UI.label(modal, t("no_trade"), Rect2(18, 64, 470, 22))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(18, 52)
	scroll.size = Vector2(472, 196)
	modal.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.custom_minimum_size = Vector2(448, 0)
	scroll.add_child(list)
	for index: int in range(items.size()):
		var definition: Dictionary = ContentCatalog.entry(str(items[index]))
		var button: Button = _button(list, str(definition.get("name", "")), Rect2(0, 0, 448, 34), _prepare_trade.bind(kind, index))
		button.tooltip_text = str(definition.get("text", ""))
		button.custom_minimum_size = Vector2(448, 34)
	_button(modal, t("cancel"), Rect2(346, 260, 144, 30), _close_overlay)

func _prepare_trade(kind: String, index: int) -> void:
	_last_events = run_rules.prepare_trade(run, kind, index)
	_begin_screen("trade_offer")
	var page: Panel = _page(t("trade_offer"))
	var offers: Array = run_rules.trade_choices(run)
	for offer_index: int in range(offers.size()):
		_item_card(page, str(offers[offer_index]), Rect2(24 + offer_index * 192, 66, 180, 208), _choose_trade.bind(offer_index))
	_button(page, t("cancel"), Rect2(428, 280, 150, 28), _show_trade)

func _choose_trade(index: int) -> void:
	_last_events = run_rules.choose_trade(run, index)
	_route_phase()

func _cue(id: String) -> void:
	if AudioService.has_cue(id): AudioService.play(id)

func _music(id: String) -> void:
	if AudioService.has_cue(id): AudioService.play_music(id)

func _process(delta: float) -> void:
	if not _focused: return
	if _overlay == null:
		if _stamp_node != null:
			_stamp_time += delta
			_stamp_node.position = _stamp_origin - Vector2(0, maxi(0, 4 - int(_stamp_time * 24)))
		if _reveal_icon != null:
			_reveal_time += delta
			_reveal_icon.position = _reveal_origin + Vector2(0, [0, -1, -2, -1][int(_reveal_time * 8) % 4])
		_clock += delta
		_idle_time += delta
	if _bubble != null and _clock >= _bubble_until: _hide_bubble()
	if _bubble == null and not _banter_pending.is_empty():
		var queued: Dictionary = _banter_pending.pop_front()
		_banter_event(queued["event"], queued["extra"])
	if _bubble != null and _overlay == null and not presentation_fast:
		_bubble_elapsed += delta
		var count: int = mini(str(_bubble_message.get("text", "")).length(), int(_bubble_elapsed * 30.0))
		_bubble_label.visible_characters = count
		if int(count / 2) != _bubble_spoken:
			_bubble_spoken = int(count / 2)
			var speaker: String = str(_bubble_message.get("speaker", ""))
			if speaker != "elite.hungry_drawer" or str(_bubble_message.get("text", "")).contains("嚼"):
				AudioService.play_voice(speaker, count)
	if _pending_terminal and _overlay == null and _clock >= _terminal_at:
		_pending_terminal = false
		if screen == "battle" and _terminal_serial == _transition_serial: _route_phase()
	if is_instance_valid(_intro_panel) and _overlay == _intro_panel:
		_intro_remaining -= delta
		if _intro_remaining <= 0.0:
			_close_overlay()
			_intro_panel = null
	if screen == "battle" and _idle_time >= 20.0:
		_idle_time = 0.0
		_banter_event("idle", {})

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		if _content != null: _content.process_mode = Node.PROCESS_MODE_DISABLED
		if _story_view != null: _story_view.suspend(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		if _content != null: _content.process_mode = Node.PROCESS_MODE_INHERIT
		if _story_view != null: _story_view.suspend(_overlay != null)

func _hide_bubble() -> void:
	if _bubble != null:
		_bubble.queue_free()
		_bubble = null
	_bubble_label = null
	_bubble_message = {}

func _banter_event(event: String, extra: Dictionary = {}) -> void:
	if _bubble != null and _banter_frame == Engine.get_process_frames() and _bubble_message.get("priority", false):
		for record: Dictionary in _banter.records:
			if record.get("event") == event and record.get("priority", false) and _banter_pending.size() < 8:
				_banter_pending.append({"event": event, "extra": extra.duplicate(true)})
				break
		return
	var enemy_ids: Array = []
	var minions: int = 0
	for enemy: Dictionary in battle.get("enemies", []):
		enemy_ids.append(enemy.get("id", ""))
		if int(enemy.get("hp", 0)) > 0 and not str(enemy.get("id", "")).begins_with("boss."): minions += 1
	var context: Dictionary = {"encounter_id": battle.get("encounter", {}).get("id", ""), "turn": int(battle.get("turn", 0)), "keepsakes": run.get("keepsakes", []), "enemy_ids": enemy_ids, "minions": minions}
	context.merge(extra, true)
	var message: Dictionary = _banter.consider(event, context, _clock)
	if message.is_empty(): return
	_hide_bubble()
	var rectangle: Rect2 = Rect2(8 if screen == "stamp" else 16, 40, 128, 70) if screen in ["battle", "stamp"] else Rect2(220, 8, 290, 34)
	_bubble = UI.frame(self, "BanterBubble", rectangle)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _uses_simple_ui():
		_bubble.add_theme_stylebox_override("panel", SimpleUI.style("ui.r3_simple_dialogue"))
	elif AssetCatalog.has_asset("ui.panel.bubble"):
		_bubble.add_theme_stylebox_override("panel", AssetCatalog.nine_slice("ui.panel.bubble"))
	_bubble_label = UI.paragraph(_bubble, str(message["text"]), Rect2(20, 8, rectangle.size.x - 40, rectangle.size.y - 14) if _uses_simple_ui() else Rect2(8, 8, rectangle.size.x - 16, rectangle.size.y - 12), UI.INK)
	_bubble_label.visible_characters = -1 if presentation_fast else 0
	_bubble_message = message
	_banter_frame = Engine.get_process_frames()
	_bubble_elapsed = 0.0
	_bubble_spoken = -1
	_bubble_until = _clock + float(message["duration"])
	if not presentation_fast: _lock_until = maxf(_lock_until, _clock + float(message["lock_seconds"]))
	if message.get("once") == "save": _checkpoint()


func _banter_events(events: Array) -> void:
	var starting: bool = events.any(func(event: Dictionary) -> bool: return event.get("type") == "battle_start")
	var player_attacked: bool = false
	var player_hurt: bool = false
	for event: Dictionary in events:
		var kind: String = str(event.get("type", ""))
		if kind == "damage" and str(event.get("target", "")) == "player":
			player_attacked = true
			player_hurt = player_hurt or int(event.get("hp_damage", 0)) > 0
		var context: Dictionary = {}
		if event.has("id"):
			context["enemy_id"] = event["id"]
			context["keepsake_id"] = event["id"]
		if kind == "card_played": context["card_type"] = ContentCatalog.entry(str(event.get("id", ""))).get("type", "")
		if kind == "intent":
			kind = "enemy_intent"
			context["intent_name"] = event.get("intent", {}).get("name", "")
			var slot: int = int(event.get("enemy", -1))
			if slot >= 0 and slot < battle.get("enemies", []).size(): context["enemy_id"] = battle["enemies"][slot]["id"]
		if kind == "boss_warning": kind = "boss_phase"
		if kind == "spawn":
			if starting: continue
			kind = "boss_summon"
		_banter_event(kind, context)
		if kind == "damage" and str(event.get("target", "")) != "player" and int(event.get("amount", 0)) >= 12: _banter_event("big_hit", {})
	if player_attacked and not player_hurt: _banter_event("perfect_block", {})
	if not battle.is_empty() and battle.get("encounter", {}).get("id") == "enc.tutorial":
		var playable: bool = false
		for action: Dictionary in battle_rules.legal_actions(battle):
			if action.get("type") == "play_card": playable = true
		if not playable: _banter_event("tutorial_end_turn", {})
	if int(battle.get("player", {}).get("hp", 40)) < float(battle.get("player", {}).get("max_hp", 40)) * 0.3:
		_banter_event("player_low_hp", {})


func _show_enemy_intro() -> void:
	if presentation_fast or run.get("current_node", {}).get("type") not in ["elite", "boss"]: return
	var boss: bool = run.get("current_node", {}).get("type") == "boss"
	var id: String = "boss.sock_snake" if boss else "elite.hungry_drawer"
	var seen: Dictionary = settings.get("intro_enemies", {})
	var seconds: float = 1.5 if seen.get(id, false) else 4.0
	seen[id] = true
	settings["intro_enemies"] = seen
	var panel: Panel = _modal(ContentCatalog.text("ui.d2.boss_intro" if boss else "ui.d2.elite_intro"))
	var actor: AnimatedSprite2D = Actor.new()
	panel.add_child(actor)
	actor.setup("big.sock_snake" if boss else "big.hungry_drawer", Vector2(110, 202))
	UI.paragraph(panel, ContentCatalog.text("ui.d2.boss_line" if boss else "ui.d2.elite_line"), Rect2(210, 62, 270, 62), UI.WARM)
	UI.paragraph(panel, ContentCatalog.text("ui.d2.boss_reply" if boss else "ui.d2.elite_reply"), Rect2(210, 130, 270, 36))
	var definition: Dictionary = ContentCatalog.entry(id)
	UI.paragraph(panel, str(definition.get("rule_text", definition.get("mechanic_text", ""))), Rect2(20, 208, 468, 42), UI.BLUE)
	_button(panel, t("skip"), Rect2(346, 260, 144, 30), _close_overlay)
	_intro_panel = panel
	_intro_remaining = seconds

func _cycle_window_size() -> void:
	var scale_value: int = int(settings.get("window_scale", 2)) % 3 + 1
	settings["window_scale"] = scale_value
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(640, 360) * scale_value
	_show_settings()

func _decoration_event(id: String, secret: bool) -> void:
	if _battle_view != null:
		settings["decoration_once"] = _battle_view.decoration_saved.duplicate(true)
	if secret: _banter_event("table_secret", {"decoration_id": id})

func _show_stamp(card_id: String) -> void:
	# Only the actual replica_unlocked event may enter this screen. Its save
	# transaction has already completed, so skip/exit cannot duplicate a grant.
	_begin_screen("stamp")
	_stamp_id = card_id
	var page: Panel = UI.frame(_content, "ReturnedMemory", Rect2(140, 28, 360, 292))
	UI.label(page, ContentCatalog.text("ui.d2.stamp"), Rect2(28, 24, 304, 24), UI.INK)
	var definition: Dictionary = ContentCatalog.entry(card_id)
	UI.label(page, str(definition.get("name", "")), Rect2(28, 64, 304, 26), UI.INK)
	UI.paragraph(page, str(definition.get("text", "")), Rect2(28, 100, 304, 42), UI.INK)
	UI.paragraph(page, t("stamp", {"name": definition.get("name", "")}), Rect2(28, 196, 304, 38), UI.INK)
	_stamp_origin = Vector2(116, 150)
	_stamp_node = UI.texture(page, AssetCatalog, "ui.r3_simple_station", Rect2(_stamp_origin, Vector2(128, 32)))
	_stamp_time = 0.0
	var stamp_text: Label = UI.label(_stamp_node, "已归还", Rect2(0, 0, 128, 32), UI.WARM)
	stamp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cue("sting.stamp")
	if not _pending_return_id.is_empty():
		_banter_event("return_complete", {"keepsake_id": _pending_return_id})
		_pending_return_id = ""
	_button(page, t("next"), Rect2(216, 244, 124, 30), _route_phase)

func _flip_path(card: Button) -> void:
	if not AssetCatalog.has_asset("path.back"): return
	var faces: Array = card.get_children()
	for face: Node in faces:
		if face is CanvasItem: face.hide()
	card.disabled = true
	var flip: AnimatedSprite2D = Actor.new()
	card.add_child(flip)
	flip.setup("path.back", Vector2(38, 0) + AssetCatalog.anchor("path.back"), "flip")
	flip.animation_finished.connect(func() -> void:
		for face: Node in faces:
			if is_instance_valid(face) and face is CanvasItem: face.show()
		card.disabled = false
		flip.queue_free(), CONNECT_ONE_SHOT)
