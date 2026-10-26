extends Control
## Complete D1 greybox flow; rules own every gameplay mutation.
const UI = preload("res://scripts/view/ui_factory.gd")
const BattleView = preload("res://scripts/view/battle_view.gd")
const Story = preload("res://scripts/story/story_player.gd")
const Battle = preload("res://scripts/core/battle_rules.gd")
const Runs = preload("res://scripts/core/run_rules.gd")
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
		_save_path = "user://d1-debug.json"
	var saved: Dictionary = SaveService.load_state(_save_path)
	var state: Dictionary = saved.get("state", SaveService.default_state())
	meta = run_rules.normalize_meta(state.get("meta", {}))
	settings = state.get("settings", {}).duplicate(true)
	run = state["run"].duplicate(true) if state.get("run") is Dictionary else {}
	_save_readonly = bool(saved.get("readonly", false))
	if saved.get("error", "") == "future_version":
		_notice = t("future_save")
	elif bool(saved.get("recovered", false)):
		_notice = ContentCatalog.text("ui.save_recovered")
	elif not bool(saved.get("ok", false)):
		_notice = ContentCatalog.text("ui.save_unavailable")
	_apply_settings()
	AudioService.play_music("music.title")
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
	pixel_theme.set_stylebox("panel", "Panel", AssetCatalog.nine_slice("ui.panel.default"))
	pixel_theme.set_stylebox("panel", "TooltipPanel", AssetCatalog.nine_slice("ui.panel.default"))
	for state_name: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style: StyleBoxTexture = AssetCatalog.nine_slice("ui.panel.default")
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
	screen = id
	_close_overlay()
	_battle_view = null
	UI.clear(_content)
	_ready_frame = Engine.get_process_frames() + 1

func _button(parent: Node, label: String, rect: Rect2, callback: Callable, name: String = "") -> Button:
	return UI.button(parent, label, rect, _invoke.bind(callback), name)

func _invoke(callback: Callable) -> void:
	if Engine.get_process_frames() < _ready_frame:
		return
	_ready_frame = Engine.get_process_frames() + 1
	AudioService.unlock()
	AudioService.play("sfx.ui_click")
	callback.call()

func _page(heading: String) -> Panel:
	var page: Panel = UI.frame(_content, "Page", Rect2(12, 10, 616, 340))
	UI.label(page, heading, Rect2(16, 12, 540, 28), UI.WARM, 24)
	UI.label(page, t("graybox"), Rect2(16, 314, 580, 16), UI.MUTED)
	return page

func _show_title() -> void:
	_begin_screen("title")
	var panel: Panel = UI.frame(_content, "TitlePanel", Rect2(24, 38, 308, 273))
	UI.label(panel, ContentCatalog.text("ui.chapter"), Rect2(20, 20, 268, 20), UI.MUTED)
	UI.label(panel, ContentCatalog.text("ui.game_title"), Rect2(20, 49, 268, 36), UI.WARM, 24)
	UI.label(panel, ContentCatalog.text("ui.subtitle"), Rect2(20, 92, 268, 24))
	UI.paragraph(panel, ContentCatalog.text("ui.tagline"), Rect2(20, 126, 252, 48), UI.MUTED)
	_button(panel, t("continue") if _has_progress() else ContentCatalog.text("ui.new_game"), Rect2(20, 184, 268, 34), _title_continue, "Continue")
	if _has_progress() and not _save_readonly:
		_button(panel, t("new_game"), Rect2(20, 222, 128, 30), _confirm_reset)
	_button(panel, t("settings"), Rect2(160, 222, 128, 30), _show_settings)
	UI.label(_content, _notice, Rect2(24, 320, 580, 20), UI.WARM)
	if _debug_mode:
		UI.label(_content, t("debug"), Rect2(346, 10, 282, 18), UI.RED)

func _has_progress() -> bool:
	return int(meta.get("runs_started", 0)) > 0 or not run.is_empty() or bool(settings.get("intro_seen", false))

func _title_continue() -> void:
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
	var page: Panel = _page(ContentCatalog.text("ui.book_title"))
	UI.paragraph(page, ContentCatalog.text("ui.book_body"), Rect2(24, 64, 258, 116))
	_button(page, t("chapter1"), Rect2(318, 74, 260, 60), _continue_game)
	var locked: Button = _button(page, t("chapter2"), Rect2(318, 154, 260, 60), func() -> void: pass)
	locked.disabled = true
	UI.label(page, t("returned", {"count": meta.get("returned", []).size()}), Rect2(24, 205, 260, 20), UI.BLUE)
	_button(page, t("back"), Rect2(24, 260, 170, 34), _show_title)

func _continue_game() -> void:
	if run.is_empty() or run.get("phase") == "hub":
		_show_hut()
	else:
		_route_phase()

func _show_hut() -> void:
	if run.get("phase", "") == "hub":
		run = {}
		battle = {}
	_begin_screen("hut")
	_checkpoint()
	var page: Panel = _page(t("hut"))
	UI.paragraph(page, t("return_hint"), Rect2(24, 52, 350, 26), UI.MUTED)
	for index: int in range(meta.get("memorials", []).size()):
		var id: String = str(meta["memorials"][index])
		var item: Dictionary = ContentCatalog.entry(id)
		var frame: Panel = UI.frame(page, "Memorial%d" % index, Rect2(262 + index * 104, 88, 92, 84))
		UI.label(frame, t("frame"), Rect2(8, 7, 76, 18), UI.MUTED)
		UI.paragraph(frame, str(item.get("name", "")), Rect2(8, 30, 76, 44), UI.WARM)
	UI.label(page, t("returned", {"count": meta.get("returned", []).size()}), Rect2(24, 100, 220, 24), UI.BLUE)
	if bool(meta.get("knot_found", false)):
		var knot: Button = _button(page, t("boss_done"), Rect2(24, 136, 210, 32), func() -> void: pass)
		knot.tooltip_text = ContentCatalog.text("ui.d1.knot_hint") if ContentCatalog.has_entry("ui.d1.knot_hint") else t("return_hint")
	_button(page, t("commissions"), Rect2(24, 208, 174, 58), _show_commissions)
	_button(page, t("album"), Rect2(220, 208, 150, 58), _show_album)
	_button(page, t("prepare"), Rect2(392, 208, 186, 58), _show_prepare)
	_button(page, t("title"), Rect2(24, 278, 150, 30), _show_title)

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
		var card: Panel = UI.frame(page, "Commission%d" % index, Rect2(24 + index * 190, 92, 178, 176))
		UI.label(card, str(definition.get("owner_name", "")), Rect2(12, 12, 154, 18), UI.WARM)
		UI.label(card, str(definition.get("name", "")), Rect2(12, 38, 154, 18))
		UI.paragraph(card, str(definition.get("commission_text", "")), Rect2(12, 66, 154, 60), UI.MUTED)
		_button(card, t("selected") if id in selected_commissions else t("accept"), Rect2(12, 132, 154, 32), _toggle_commission.bind(id))
	_button(page, t("back"), Rect2(24, 276, 150, 30), _show_hut)
	_button(page, t("prepare"), Rect2(428, 276, 150, 30), _show_prepare)

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
		var card: Panel = UI.frame(page, "Prepared%d" % index, Rect2(24 + index * 288, 94, 268, 116))
		UI.label(card, str(item.get("owner_name", "")) + " · " + str(item.get("name", "")), Rect2(12, 12, 244, 22), UI.WARM)
		UI.paragraph(card, str(item.get("commission_text", "")), Rect2(12, 42, 244, 40))
		UI.label(card, t("unknown_wish"), Rect2(12, 88, 244, 18), UI.MUTED)
	if selected_commissions.is_empty():
		UI.paragraph(page, t("no_commissions"), Rect2(24, 106, 550, 60))
	_button(page, t("commissions"), Rect2(24, 258, 162, 38), _show_commissions)
	_button(page, t("descend"), Rect2(402, 258, 176, 38), _start_run)

func _start_run() -> void:
	var seed_value: int = _debug_seed if _debug_seed >= 0 else int(Time.get_unix_time_from_system()) + int(meta.get("runs_started", 0))
	var result: Dictionary = run_rules.start_run(meta, selected_commissions, seed_value)
	if not result.get("ok", false):
		_notice = t("invalid")
		return
	run = result["run"]
	battle = {}
	_last_events = result.get("events", [])
	_route_phase()

func _route_phase() -> void:
	while not _last_events.is_empty():
		var presentation: Dictionary = _last_events.pop_front()
		if presentation.get("type") == "story" and ContentCatalog.has_entry(str(presentation.get("id", ""))):
			_show_story({"id": presentation["id"]}, _route_phase)
			return
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
		_: _show_hut()

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
	var page: Panel = _page(t("path_title"))
	var segment: int = int(run.get("segment", 1))
	UI.label(page, t("segment", {"segment": segment}), Rect2(106, 54, 360, 24), UI.WARM)
	var shaft: Panel = UI.frame(page, "WellShaft", Rect2(24, 52, 58, 222))
	for index: int in range(7):
		var slot: Panel = UI.frame(shaft, "Depth%d" % index, Rect2(7, 7 + index * 30, 44, 27))
		UI.label(slot, ("◆ " if index + 1 == segment else "  ") + str(index + 1), Rect2(8, 4, 34, 18), UI.WARM if index + 1 == segment else UI.MUTED)
	var choices: Array = run_rules.path_choices(run)
	for index: int in range(choices.size()):
		var choice: Dictionary = choices[index]
		var card: Button = _button(page, "", Rect2(142 + index * 220, 94, 172, 164), _choose_path.bind(index), "Path%d" % index)
		var type_name: String = _node_type_text(str(choice.get("type", "")))
		UI.label(card, type_name, Rect2(12, 12, 148, 20), UI.WARM)
		UI.paragraph(card, str(choice.get("hint", "")), Rect2(12, 50, 148, 58))
		var marks: String = ""
		for id: String in choice.get("star_ids", []):
			marks += "✦ " + str(ContentCatalog.entry(id).get("owner_name", "")) + " "
		for id: String in choice.get("heart_ids", []):
			marks += "♥ " + str(ContentCatalog.entry(id).get("name", ""))
		UI.paragraph(card, marks, Rect2(12, 116, 148, 36), UI.BLUE)
		card.tooltip_text = type_name + "\n" + _node_preview(choice)
	_run_bar(page, 278)
	_button(page, t("home"), Rect2(438, 272, 140, 36), _end_run.bind("voluntary"))

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
	var relic: Button = _button(parent, t("relics") + " " + str(run.get("relics", []).size()), Rect2(158, y - 5, 76, 28), _show_inventory.bind("relics"))
	relic.tooltip_text = _inventory_text("relics")
	var keepsake: Button = _button(parent, t("keepsakes") + " " + str(run.get("keepsakes", []).size()), Rect2(238, y - 5, 76, 28), _show_inventory.bind("keepsakes"))
	keepsake.tooltip_text = _inventory_text("keepsakes")
	_button(parent, t("deck"), Rect2(318, y - 5, 76, 28), _show_pile.bind("deck"))

func _choose_path(index: int) -> void:
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
	_show_battle()

func _show_battle() -> void:
	_begin_screen("battle")
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
	board.add_child(_battle_view)
	_battle_view.present_events(_last_events)

func _battle_command(action: Dictionary) -> void:
	if screen != "battle" or _overlay != null:
		return
	var legal: Array = battle_rules.legal_actions(battle)
	if not legal.has(action):
		return
	if action.get("type") == "play_card":
		_last_events = battle_rules.play_card(battle, int(action["hand_index"]), int(action.get("target_index", -1)), action.get("choices", {}))
		AudioService.play("sfx.card_play_attack")
	else:
		_last_events = battle_rules.end_turn(battle, int(action.get("keep_index", -1)))
		AudioService.play("sfx.ui_click")
	if battle.get("status") in ["victory", "defeat"]:
		_last_events = run_rules.complete_battle(run, meta, battle, _last_events)
		_route_phase()
	else:
		_show_battle()

func _show_defeat() -> void:
	_begin_screen("defeat")
	var page: Panel = _page(t("defeat"))
	UI.paragraph(page, ContentCatalog.text("ui.d1.defeat_hint") if ContentCatalog.has_entry("ui.d1.defeat_hint") else t("tutorial"), Rect2(64, 72, 486, 90))
	_button(page, t("retry"), Rect2(64, 204, 218, 52), _retry_battle)
	_button(page, t("home"), Rect2(326, 204, 218, 52), _end_run.bind("defeat"))

func _retry_battle() -> void:
	var result: Dictionary = run_rules.retry_battle(run, battle_rules, battle)
	battle = result.get("state", {})
	_last_events = result.get("events", [])
	_checkpoint()
	_route_phase()

func _show_rewards() -> void:
	_begin_screen("reward")
	var page: Panel = _page(t("reward"))
	var offers: Array = run_rules.reward_choices(run)
	for index: int in range(offers.size()):
		_item_card(page, str(offers[index]["id"]), Rect2(24 + index * 192, 66, 180, 208), _choose_reward.bind(index))
	_button(page, t("skip"), Rect2(428, 280, 150, 28), _choose_reward.bind(-1))

func _item_card(parent: Node, id: String, rect: Rect2, callback: Callable) -> void:
	var definition: Dictionary = ContentCatalog.entry(id)
	var card: Button = _button(parent, "", rect, callback)
	UI.paragraph(card, str(definition.get("name", "")), Rect2(12, 12, rect.size.x - 24, 38), UI.WARM)
	if definition.has("cost"):
		UI.label(card, t("view_card", {"cost": definition["cost"], "type": t("type_" + str(definition.get("type", "special")))}), Rect2(12, 44, rect.size.x - 24, 18), UI.BLUE)
	UI.paragraph(card, str(definition.get("text", "")), Rect2(12, 70, rect.size.x - 24, 74))
	UI.paragraph(card, str(definition.get("flavor", "")), Rect2(12, 148, rect.size.x - 24, 46), UI.MUTED)

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
	var definition: Dictionary = ContentCatalog.entry(str(node.get("id", "")))
	var page: Panel = _page(str(definition.get("name", _node_type_text(str(node.get("type", "event"))))))
	UI.paragraph(page, str(definition.get("description", node.get("hint", ""))), Rect2(24, 58, 556, 52), UI.MUTED)
	var choices: Array = run_rules.node_choices(run)
	for index: int in range(choices.size()):
		var choice: Dictionary = choices[index]
		var button: Button = _button(page, str(choice.get("text", "")), Rect2(24, 120 + index * 36, 554, 32), _choose_node.bind(str(choice["id"])))
		var preview: Dictionary = choice.get("preview", {})
		button.tooltip_text = t("hp", {"hp": preview.get("hp", run.get("hp", 0)), "max": preview.get("max_hp", run.get("max_hp", 0))})
	_run_bar(page, 286)

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
	_story_record = record.duplicate(true)
	_story_done = done
	var conditions: Dictionary = {"wishes": run.get("wishes", {}).duplicate(true), "card_id": record.get("card_id", "")}
	if record.has("keepsake_id"):
		conditions["wishes"][record["keepsake_id"]] = bool(record.get("wish", false))
	_story.begin(ContentCatalog.entry(str(record.get("id", ""))), conditions)
	if _story.finished():
		done.call()
	else:
		_render_story()

func _render_story() -> void:
	_begin_screen("story")
	var page: Panel = _page(t("story_plain"))
	var current: Dictionary = _story.current()
	var picture: Panel = UI.frame(page, "D1TextFrame", Rect2(38, 56, 540, 176))
	UI.paragraph(picture, str(current.get("caption", "")), Rect2(20, 16, 500, 44), UI.MUTED)
	UI.paragraph(picture, str(current.get("text", "")), Rect2(20, 72, 500, 82), UI.PAPER)
	UI.label(page, str(_story.index + 1) + " / " + str(_story.pages.size()), Rect2(40, 246, 116, 22), UI.MUTED)
	var stamp: String = _story.stamp()
	if _story.index == _story.pages.size() - 1 and not stamp.is_empty():
		UI.label(page, t("stamp", {"name": ContentCatalog.entry(stamp).get("name", "")}), Rect2(40, 274, 500, 22), UI.WARM)
	_button(page, t("skip"), Rect2(328, 240, 110, 32), _skip_story)
	_button(page, t("next"), Rect2(450, 240, 128, 32), _next_story)

func _next_story() -> void:
	if _story.advance():
		_story_done.call()
	else:
		_render_story()

func _skip_story() -> void:
	_story.skip()
	_story_done.call()

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
		var card: Panel = UI.frame(page, "Album%d" % index, Rect2(24 + (index % 3) * 192, 60 + int(index / 3) * 110, 180, 102))
		UI.label(card, str(definition.get("name", "")), Rect2(12, 10, 156, 20), UI.WARM)
		UI.paragraph(card, str(definition.get("text", "")), Rect2(12, 36, 156, 54))
	_button(page, t("back"), Rect2(24, 282, 142, 28), _show_hut)
	if ids.size() > 6:
		_button(page, t("next"), Rect2(436, 282, 142, 28), func() -> void:
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
	_overlay = UI.frame(self, "Modal", Rect2(66, 28, 508, 304))
	UI.label(_overlay, heading, Rect2(18, 16, 472, 24), UI.WARM)
	_ready_frame = Engine.get_process_frames() + 1
	return _overlay

func _show_message(heading: String, body: String) -> void:
	var modal: Panel = _modal(heading)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(18, 52)
	scroll.size = Vector2(472, 196)
	modal.add_child(scroll)
	var label: Label = Label.new()
	label.text = body
	label.custom_minimum_size = Vector2(448, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_constant_override("line_spacing", 6)
	scroll.add_child(label)
	_button(modal, t("close"), Rect2(346, 260, 144, 30), _close_overlay)

func _close_overlay() -> void:
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
	if screen == "path":
		_button(modal, t("home"), Rect2(266, 180, 224, 38), _end_run.bind("voluntary"))

func _pause_to_title() -> void:
	_checkpoint()
	# Restore the exact persisted checkpoint before continuing in this process too.
	var saved: Dictionary = SaveService.load_state(_save_path)
	if saved.get("ok", false):
		var snapshot: Dictionary = saved["state"]
		meta = run_rules.normalize_meta(snapshot["meta"])
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
	_checkpoint()
	_title_continue()

func _show_settings() -> void:
	var modal: Panel = _modal(t("settings"))
	for index: int in range(3):
		var key: String = ["master", "music", "sfx"][index]
		UI.label(modal, t(key), Rect2(18, 58 + index * 46, 100, 22))
		var slider: HSlider = HSlider.new()
		slider.position = Vector2(132, 58 + index * 46)
		slider.size = Vector2(338, 22)
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = float(settings.get(key, 0.8))
		slider.value_changed.connect(func(value: float) -> void:
			settings[key] = value
			_apply_settings())
		modal.add_child(slider)
	_button(modal, t("window") + " ×2", Rect2(18, 210, 220, 32), func() -> void: get_window().size = Vector2i(1280, 720))
	_button(modal, t("fullscreen"), Rect2(266, 210, 224, 32), func() -> void:
		get_window().mode = Window.MODE_WINDOWED if get_window().mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN)
	_button(modal, t("close"), Rect2(346, 260, 144, 30), func() -> void:
		_checkpoint()
		_close_overlay())

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
	var data: Dictionary = {"version": 1, "meta": snapshot["meta"], "run": snapshot["run"], "settings": settings.duplicate(true)}
	var result: Error = SaveService.save_state(data, _save_path)
	if result != OK:
		_notice = t("save_failed")
	return result == OK

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or Engine.get_process_frames() < _ready_frame:
		return
	if _overlay != null:
		if event.keycode == KEY_ESCAPE:
			_close_overlay()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F1 and OS.is_debug_build():
		_show_message(t("debug"), t("seed", {"seed": run.get("seed", "—")}) + "\n" + t("graybox"))
	elif screen == "battle" and _battle_view != null:
		_battle_view.handle_key(event)
	elif screen == "story" and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_invoke(_next_story)
	elif event.keycode == KEY_ESCAPE:
		if screen == "book":
			_show_title()
		elif screen != "title":
			_show_pause()
	elif screen == "title" and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_invoke(_title_continue)
	get_viewport().set_input_as_handled()

func _show_reveal(event: Dictionary) -> void:
	_begin_screen("reveal")
	var item: Dictionary = ContentCatalog.entry(str(event.get("id", "")))
	var wished: bool = event.get("type") == "wish_done"
	var page: Panel = _page(t("wish_title" if wished else "acquired_title"))
	UI.label(page, str(item.get("owner_name", "")) + " · " + str(item.get("name", "")), Rect2(36, 74, 540, 30), UI.WARM, 24)
	UI.paragraph(page, str(item.get("text", "")), Rect2(36, 124, 540, 44))
	UI.paragraph(page, t("wish_done") if wished else str(item.get("wish", {}).get("name", "")) + " · " + str(item.get("wish", {}).get("text", "")), Rect2(36, 184, 540, 50), UI.BLUE)
	_button(page, t("next"), Rect2(428, 272, 150, 34), _route_phase)

func _show_trade() -> void:
	_begin_screen("node")
	var page: Panel = _page(t("trade"))
	UI.paragraph(page, t("trade_give"), Rect2(24, 62, 552, 34), UI.MUTED)
	_button(page, t("trade_relic"), Rect2(24, 128, 264, 58), _trade_inventory.bind("relic"))
	_button(page, t("trade_card"), Rect2(314, 128, 264, 58), _trade_inventory.bind("card"))
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
