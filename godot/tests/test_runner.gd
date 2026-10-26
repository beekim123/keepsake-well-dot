extends SceneTree
## Self-contained headless D0 tests. Any failed assertion exits nonzero.

const Rules = preload("res://scripts/core/damage_rules.gd")
const FONT_PATH: String = "res://resources/fonts/fusion-pixel-12px/fusion-pixel-12px-proportional-zh_hans.otf.woff2"
var _passed: int = 0
var _failed: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	_test_damage_rules()
	_test_catalogs()
	_test_save_service()
	_test_audio_service()
	_test_font_coverage()
	await _test_title_flow()
	root.get_node("AudioService").stop_all()
	# Let the audio mixer release stopped playback before the engine exits.
	await create_timer(0.15).timeout
	print("D0_TEST_RESULT: " + JSON.stringify({"passed": _passed, "failed": _failed, "scope": "foundation only; D1 battle and expedition tests not implemented"}))
	quit(0 if _failed == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS " + label)
	else:
		_failed += 1
		printerr("FAIL " + label)

func _test_damage_rules() -> void:
	var original: Dictionary = {"hp": 12, "guard": 4, "id": "test.target"}
	var result: Dictionary = Rules.apply_damage(original, 6)
	_check(result["state"]["hp"] == 10 and result["state"]["guard"] == 0, "shield absorbs damage before HP")
	_check(original == {"hp": 12, "guard": 4, "id": "test.target"}, "damage does not mutate the input state")
	_check(result["events"][0]["blocked"] == 4 and result["events"][0]["hp_damage"] == 2, "damage emits actual guard and HP loss")
	result = Rules.apply_damage({"hp": 12, "guard": 8}, 6)
	_check(result["state"] == {"hp": 12, "guard": 2}, "remaining guard is retained")
	result = Rules.apply_damage({"hp": 3, "guard": 2}, 99)
	_check(result["state"] == {"hp": 0, "guard": 0}, "overkill cannot make HP negative")
	result = Rules.apply_damage(original, -5)
	_check(result["state"] == original, "negative incoming damage does not heal")
	_check(Rules.apply_damage(original, 6) == Rules.apply_damage(original, 6), "pure rule result is deterministic")

func _test_catalogs() -> void:
	var art: Node = root.get_node("AssetCatalog")
	var content: Node = root.get_node("ContentCatalog")
	_check(art.valid, "art-manifest/1 loaded")
	_check(content.valid, "content/1 registry loaded")
	_check(art.texture("char.asui") != null, "Asui sheet is an imported texture")
	_check(art.frame_size("char.asui") == Vector2i(48, 64), "Asui frame size 48x64")
	var frames: SpriteFrames = art.frames("char.asui", "idle")
	_check(frames != null and frames.get_frame_count("idle") >= 4, "Asui idle consumes manifest frame sequence")
	_check(art.anchor("char.asui") == Vector2(24, 60), "sprite anchor reads from manifest")
	var panel: StyleBoxTexture = art.nine_slice("ui.panel.default")
	_check(panel.texture != null and panel.get_texture_margin(SIDE_LEFT) == 4.0, "nine-slice panel consumes manifest margins")
	_check(content.text("ui.game_title") == "拾遗井", "title string loaded from content")
	_check(content.table("cards").size() == 4, "D0 has four starter card definitions, not a full D1 content claim")

func _test_save_service() -> void:
	var saves: Node = root.get_node("SaveService")
	var path: String = "user://d0-test-save.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var result: Dictionary = saves.load_state(path)
	_check(result["ok"] and result["state"]["version"] == 1, "missing save returns versioned defaults")
	var state: Dictionary = saves.default_state()
	state["settings"]["music"] = 0.25
	_check(saves.save_state(state, path) == OK, "atomic save writes valid schema")
	result = saves.load_state(path)
	_check(result["ok"] and result["state"]["settings"]["music"] == 0.25, "saved settings round-trip")
	state["settings"]["music"] = 0.5
	_check(saves.save_state(state, path) == OK and saves.load_state(path)["state"]["settings"]["music"] == 0.5, "atomic save safely replaces previous file")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	result = saves.load_state(path)
	_check(not result["ok"] and result["recovered"] and FileAccess.file_exists(result["backup"]), "corrupt save is quarantined and defaults returned")
	_check(not FileAccess.file_exists(path), "corrupt original is not left at the active save path")
	if result["recovered"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(result["backup"]))
	state["version"] = 99
	_check(saves.save_state(state, path) == ERR_INVALID_DATA, "unknown save version cannot be written")
	_check(not saves.load_state("res://project.godot")["ok"], "save API refuses non-user paths")
	_check(saves.save_state(saves.default_state(), "user://../escape.json") == ERR_INVALID_DATA, "save API refuses path traversal")

func _test_audio_service() -> void:
	var audio: Node = root.get_node("AudioService")
	_check(audio.valid, "audio-manifest/1 loaded")
	var info: Dictionary = audio.diagnostics()
	_check(info["sfx_voices"] == 6 and info["music_voices"] == 2, "six SFX and two music players allocated")
	_check(not audio.is_unlocked(), "audio starts locked before user gesture")
	_check(not audio.play("sfx.ui_click"), "SFX cannot autoplay before gesture")
	_check(audio.play_music("music.title") and audio.diagnostics()["pending_music"] == "music.title", "title music waits for first gesture")
	audio.unlock()
	_check(audio.is_unlocked() and audio.diagnostics()["music"] == "music.title", "first gesture starts queued music")
	_check(audio.play("sfx.ui_click") and audio.play("sfx.card_play_attack"), "both D0 SFX can play by semantic ID")
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("UI") >= 0, "Music, SFX, UI buses exist")
	audio.set_focused(false)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")) and not audio.play("sfx.ui_click"), "focus loss mutes and suspends new SFX")
	audio.set_focused(true)
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "focus return restores playback")
	audio.set_muted(true)
	audio.set_focused(false)
	audio.set_focused(true)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "focus return preserves user mute preference")
	audio.set_muted(false)

func _test_font_coverage() -> void:
	var font: FontFile = load(FONT_PATH) as FontFile
	_check(font != null, "bundled Fusion Pixel WOFF2 imports")
	if font == null:
		return
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/registry.json"))
	var missing: Dictionary = {}
	for item: Dictionary in registry["files"]:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + str(item["target"])))
		_check_glyphs(data, font, missing)
	_check(missing.is_empty(), "Fusion Pixel covers all content strings; missing=" + str(missing.keys()))

func _check_glyphs(value: Variant, font: FontFile, missing: Dictionary) -> void:
	if value is Dictionary:
		for child: Variant in value.values():
			_check_glyphs(child, font, missing)
	elif value is Array:
		for child: Variant in value:
			_check_glyphs(child, font, missing)
	elif value is String:
		for index: int in range(value.length()):
			var codepoint: int = value.unicode_at(index)
			if codepoint > 32 and not font.has_char(codepoint):
				missing[String.chr(codepoint)] = true

func _test_title_flow() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_check(scene != null, "main scene can load")
	if scene == null:
		return
	var title: Control = scene.instantiate() as Control
	root.add_child(title)
	await process_frame
	_check(title.get_node("TitlePanel").visible and not title.get_node("NotebookPanel").visible, "launch shows title, not fictional playable expedition")
	var button: Button = title.get_node("TitlePanel/ui_new_game") as Button
	var back: Button = title.get_node("NotebookPanel/ui_back") as Button
	button.pressed.emit()
	_check(title.get_node("NotebookPanel").visible and not title.get_node("TitlePanel").visible, "start opens notebook preview")
	back.pressed.emit()
	_check(title.get_node("TitlePanel").visible and not title.get_node("NotebookPanel").visible, "back returns to title")
	for iteration: int in range(5):
		button.pressed.emit()
		back.pressed.emit()
	_check(title.get_node("TitlePanel").visible, "repeated open/close remains usable")
	button.pressed.emit()
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	title._unhandled_key_input(escape)
	_check(title.get_node("TitlePanel").visible, "Escape safely closes notebook")
	_check(title.theme.default_font.antialiasing == TextServer.FONT_ANTIALIASING_NONE and title.theme.default_font.hinting == TextServer.HINTING_NONE, "UI font disables antialiasing and hinting")
	title.queue_free()
	await process_frame
