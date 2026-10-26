extends Control
## Non-modal, skippable scene-space dialogue shared by opening and battle.
const GeneratedUI = preload("res://scripts/view/remedy/generated_ui.gd")
signal finished
var _text: String = ""
var _speaker: String = ""
var _elapsed: float = 0.0
var _duration: float = 0.0
var _voice_index: int = -1
var _serial: int = 0

func _ready() -> void:
	GeneratedUI.patch($Paper, "ui.r2_dialogue")
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_input)
	if _text.is_empty(): hide()
	else: _show_text()

func say(text: String, speaker: String = "", duration: float = 0.0) -> void:
	_serial += 1
	_text = text
	_speaker = speaker
	_duration = duration
	_elapsed = 0.0
	_voice_index = -1
	if is_node_ready(): _show_text()

func _show_text() -> void:
	$Text.text = _text
	$Text.visible_characters = 0
	visible = not _text.is_empty()

func dismiss() -> void:
	if not visible: return
	hide()
	finished.emit()

func _process(delta: float) -> void:
	if not visible: return
	_elapsed += delta
	var count: int = mini(_text.length(), int(_elapsed * 34.0))
	$Text.visible_characters = count
	if count > _voice_index and count % 3 == 0:
		_voice_index = count
		if not _speaker.is_empty(): AudioService.play_voice(_speaker, count)
	if _duration > 0 and _elapsed >= _duration: dismiss()

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		advance()
		accept_event()

func advance() -> void:
	if _elapsed*34.0 < _text.length(): reveal()
	else: dismiss()

func reveal() -> void:
	_elapsed = float(_text.length()) / 34.0
	if is_node_ready(): $Text.visible_characters = -1
