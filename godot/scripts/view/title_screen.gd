extends Control
## D0 entry point: a real title and a short, explicitly scoped notebook preview.

const FONT_PATH: String = "res://resources/fonts/fusion-pixel-12px/fusion-pixel-12px-proportional-zh_hans.otf.woff2"
const PAPER: Color = Color("fffaf0")
const WARM: Color = Color("ffe08a")
const MUTED: Color = Color("ddb57a")
const INK: Color = Color("1b1622")
var _title_panel: Panel
var _book_panel: Panel
var _new_game: Button
var _back: Button
var _sound_label: Label
var _book_open: bool = false
var _font: FontFile

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_window().title = ContentCatalog.text("ui.game_title")
	_build_theme()
	_build_scene()
	AudioService.unlocked_changed.connect(_on_audio_unlocked)
	AudioService.play_music("music.title")
	var saved: Dictionary = SaveService.load_state()
	if bool(saved.get("recovered", false)):
		_label(self, "ui.save_recovered", Rect2(24, 320, 380, 16), 12, WARM)
	elif not bool(saved.get("ok", false)):
		_label(self, "ui.save_unavailable", Rect2(24, 320, 380, 16), 12, WARM)
	if OS.get_cmdline_user_args().has("--shots") and OS.is_debug_build():
		_capture_preview.call_deferred()

func _build_theme() -> void:
	_font = load(FONT_PATH) as FontFile
	if _font == null:
		push_error("TitleScreen: Fusion Pixel font missing; run sync")
		return
	_font = _font.duplicate() as FontFile
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_font.hinting = TextServer.HINTING_NONE
	_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	_font.multichannel_signed_distance_field = false
	_font.generate_mipmaps = false
	var pixel_theme: Theme = Theme.new()
	pixel_theme.default_font = _font
	pixel_theme.default_font_size = 12
	pixel_theme.set_color("font_color", "Label", PAPER)
	pixel_theme.set_color("font_shadow_color", "Label", INK)
	pixel_theme.set_constant("shadow_offset_x", "Label", 1)
	pixel_theme.set_constant("shadow_offset_y", "Label", 1)
	pixel_theme.set_stylebox("panel", "Panel", AssetCatalog.nine_slice("ui.panel.default"))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style: StyleBoxTexture = AssetCatalog.nine_slice("ui.panel.default")
		if state == "hover" or state == "focus":
			style.modulate_color = Color("ffe08a")
		elif state == "pressed":
			style.modulate_color = Color("b9844e")
		pixel_theme.set_stylebox(state, "Button", style)
	pixel_theme.set_color("font_color", "Button", WARM)
	pixel_theme.set_color("font_hover_color", "Button", PAPER)
	pixel_theme.set_color("font_pressed_color", "Button", WARM)
	pixel_theme.set_color("font_focus_color", "Button", PAPER)
	pixel_theme.set_color("font_outline_color", "Button", INK)
	pixel_theme.set_constant("outline_size", "Button", 2)
	theme = pixel_theme

func _build_scene() -> void:
	if AssetCatalog.has_asset("board.title"):
		var background: TextureRect = TextureRect.new()
		background.name = "TitleBackground"
		background.texture = AssetCatalog.texture("board.title")
		background.position = Vector2.ZERO
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
	_title_panel = _panel(self, "TitlePanel", Rect2(24, 38, 308, 273))
	_label(_title_panel, "ui.chapter", Rect2(20, 20, 268, 20), 12, MUTED)
	_label(_title_panel, "ui.game_title", Rect2(20, 49, 268, 36), 24, WARM)
	_label(_title_panel, "ui.subtitle", Rect2(20, 92, 268, 24), 12, PAPER)
	var tagline: Label = _label(_title_panel, "ui.tagline", Rect2(20, 132, 252, 48), 12, MUTED)
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_new_game = _button(_title_panel, "ui.new_game", Rect2(20, 195, 268, 38), _open_book)
	_label(_title_panel, "ui.version", Rect2(20, 245, 268, 16), 12, MUTED)
	_sound_label = _label(self, "ui.sound_hint", Rect2(398, 326, 218, 18), 12, MUTED)
	_sound_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_book_panel = _panel(self, "NotebookPanel", Rect2(56, 30, 528, 300))
	_label(_book_panel, "ui.book_title", Rect2(24, 22, 480, 36), 24, WARM)
	var body: Label = _label(_book_panel, "ui.book_body", Rect2(24, 76, 480, 96), 12, PAPER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_constant_override("line_spacing", 10)
	var scope: Label = _label(_book_panel, "ui.book_scope", Rect2(24, 180, 480, 48), 12, MUTED)
	scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scope.add_theme_constant_override("line_spacing", 6)
	_back = _button(_book_panel, "ui.back", Rect2(320, 244, 184, 34), _close_book)
	_book_panel.hide()

func _panel(parent: Node, node_name: String, rectangle: Rect2) -> Panel:
	var panel: Panel = Panel.new()
	panel.name = node_name
	panel.position = rectangle.position
	panel.size = rectangle.size
	parent.add_child(panel)
	return panel

func _label(parent: Node, key: String, rectangle: Rect2, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.name = key.replace(".", "_")
	label.text = ContentCatalog.text(key)
	label.position = rectangle.position
	label.size = rectangle.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, key: String, rectangle: Rect2, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.name = key.replace(".", "_")
	button.text = ContentCatalog.text(key)
	button.position = rectangle.position
	button.size = rectangle.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	button.mouse_entered.connect(func() -> void: button.position.y = rectangle.position.y - 1)
	button.mouse_exited.connect(func() -> void: button.position.y = rectangle.position.y)
	parent.add_child(button)
	return button

func _open_book() -> void:
	AudioService.unlock()
	AudioService.play("sfx.ui_click")
	_book_open = true
	_title_panel.hide()
	_book_panel.show()
	_back.grab_focus()

func _close_book() -> void:
	AudioService.unlock()
	AudioService.play("sfx.ui_click")
	_book_open = false
	_book_panel.hide()
	_title_panel.show()
	_new_game.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _book_open:
		_close_book()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not _book_open:
		_open_book()
		get_viewport().set_input_as_handled()

func _on_audio_unlocked(_is_unlocked: bool) -> void:
	_sound_label.text = ContentCatalog.text("ui.sound_on")

func _capture_preview() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Screenshots require an authorized visible launch, not headless rendering")
		get_tree().quit(1)
		return
	var folder: String = ProjectSettings.globalize_path("res://../artifacts/screenshots")
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(folder)
	if directory_error != OK:
		push_error("Screenshot directory unavailable")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var title_error: Error = get_viewport().get_texture().get_image().save_png(folder.path_join("d0-title.png"))
	_open_book()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var book_error: Error = get_viewport().get_texture().get_image().save_png(folder.path_join("d0-notebook.png"))
	if title_error != OK or book_error != OK:
		push_error("Screenshot save failed")
		get_tree().quit(1)
		return
	AudioService.stop_all()
	await get_tree().create_timer(0.15).timeout
	print("D0_SCREENSHOTS: artifacts/screenshots/d0-title.png, artifacts/screenshots/d0-notebook.png")
	get_tree().quit(0)
