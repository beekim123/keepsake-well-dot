extends Control
## Skippable opening; phase clock is paused with this scene, never a stale timer.
signal descent_finished
const Juice = preload("res://scripts/view/remedy/juice.gd")
const SimpleUI = preload("res://scripts/view/remedy/simple_ui.gd")
var phase: String = "push"
var elapsed: float = 0.0
var first_rope_seconds: float = -1.0
var _total: float = 0.0
var _completed: bool = false
var _tween: Tween
var _rope_tween: Tween

func _ready() -> void:
	theme = SimpleUI.theme()
	$Hint.text = ContentCatalog.text("ui.r2.grab_rope")
	$Hint.add_theme_stylebox_override("normal", SimpleUI.style("ui.r3_simple_station"))
	$Stage/Aunt.visible = true
	$Stage/Aunt.position.x = -48.0
	$RopeTarget.pressed.connect(grab_rope)
	$Dialogue.finished.connect(_dialogue_finished)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property($Stage, "scale", Vector2(1.08, 1.08), 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property($Stage, "position", Vector2(-42, -18), 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property($Stage/Asui, "position:x", 420.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property($Stage/Aunt, "position:x", 340.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	$Dialogue.size = Vector2(248, 58)
	$Dialogue/Text.offset_left = 22.0
	$Dialogue/Text.offset_right = -22.0
	$Dialogue/Text.offset_top = 8.0
	$Dialogue/Text.offset_bottom = -12.0
	AudioService.play_music("music.hut")

func _process(delta: float) -> void:
	$Stage.talking = phase == "rope" and $Dialogue.visible
	_total += delta
	elapsed += delta
	match phase:
		"push":
			if elapsed >= 0.8: _aunt_line()
		"aunt":
			if elapsed >= 2.6: _rope_line()
		"descent":
			# Exactly one second from accepted grab to battle transition.
			if elapsed >= 1.0 and not _completed:
				_completed = true
				descent_finished.emit()

func _aunt_line() -> void:
	if phase != "push": return
	_finish_push()
	phase = "aunt"
	elapsed = 0.0
	$Dialogue.position = Vector2(142, 170)
	$Dialogue.say(ContentCatalog.text("ui.r2.aunt_opening"), "npc.mai_aunt")

func _rope_line() -> void:
	if phase not in ["push", "aunt"]: return
	if phase == "push": _finish_push()
	phase = "rope"
	elapsed = 0.0
	$Stage/Maye.visible = true
	$Stage/Maye.position.y = 124.0
	_rope_tween = create_tween()
	_rope_tween.tween_property($Stage/Maye, "position:y", 190.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	$Stage.rope_active = true
	$RopeTarget.disabled = false
	$RopeTarget.visible = true
	$Hint.visible = true
	first_rope_seconds = _total
	$Dialogue.position = Vector2(340, 108)
	$Dialogue.say(ContentCatalog.text("ui.r2.maye_opening"), "npc.maye", 3.0)
	AudioService.play("sfx.rope_creak")

func _finish_push() -> void:
	# Skipping the opening cannot leave its walk tween competing with descent.
	if _tween != null and _tween.is_valid(): _tween.kill()
	$Stage.scale = Vector2(1.08, 1.08)
	$Stage.position = Vector2(-42, -18)
	$Stage/Asui.position.x = 420.0
	$Stage/Aunt.position.x = 340.0

func _dialogue_finished() -> void:
	if phase == "aunt": _rope_line()

func grab_rope() -> void:
	if phase != "rope" or _completed: return
	phase = "descent"
	elapsed = 0.0
	$RopeTarget.disabled = true
	$RopeTarget.hide()
	$Hint.hide()
	$Dialogue.hide()
	$Stage.rope_active = false
	$Stage.descending = true
	if _rope_tween != null and _rope_tween.is_valid(): _rope_tween.kill()
	AudioService.play("sfx.rope_pull")
	var descent: Tween = create_tween()
	descent.tween_property($Stage/Asui, "position", Vector2(548, 262), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	descent.tween_property($Stage/Asui, "position:y", 430.0, 0.68).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	descent.parallel().tween_property($Stage/Maye, "position:y", 322.0, 0.68)
	descent.parallel().tween_property($Curtain, "color:a", 1.0, 0.36).set_delay(0.32)
	Juice.burst($Stage, Vector2(548, 262), "dust", 8)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if phase == "push": _aunt_line()
		elif phase == "aunt": _rope_line()
		else: return
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if phase == "push": _aunt_line()
		elif phase == "aunt": _rope_line()
		elif phase == "rope": grab_rope()
		get_viewport().set_input_as_handled()
