extends Control
## Scene art and hero are separate model assets; labels remain real controls.
const SimpleUI = preload("res://scripts/view/remedy/simple_ui.gd")
signal commissions_requested
signal album_requested
signal prepare_requested
signal title_requested
signal settings_requested

func _ready() -> void:
	theme = SimpleUI.theme()
	$Background.texture = AssetCatalog.texture("board.r3_simple_town")
	$Asui.texture = AssetCatalog.texture("char.r3_simple_asui")
	$Asui.offset = -AssetCatalog.anchor("char.r3_simple_asui")
	for pair: Array in [["CommissionBoard", "委托", commissions_requested], ["MemoryBook", "收藏", album_requested], ["Well", "下井", prepare_requested]]:
		var hotspot: Button = get_node(str(pair[0]))
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			hotspot.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var tag: Button = hotspot.get_node("Tag")
		tag.text = str(pair[1])
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var requested: Signal = pair[2]
		hotspot.pressed.connect(func() -> void: requested.emit())
		hotspot.mouse_entered.connect(_hover.bind(tag, true))
		hotspot.mouse_exited.connect(_hover.bind(tag, false))
		tag.set_meta("rest_position", tag.position)
	$TitleButton.pressed.connect(func() -> void: title_requested.emit())
	$SettingsButton.pressed.connect(func() -> void: settings_requested.emit())
	var breath: Tween = create_tween().set_loops()
	breath.tween_property($Asui, "scale:y", 1.018, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breath.tween_property($Asui, "scale:y", 1.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _hover(tag: Button, active: bool) -> void:
	if active: AudioService.play("sfx.ui_hover")
	var prior: Tween = tag.get_meta("hover_tween", null)
	if prior != null and prior.is_valid(): prior.kill()
	tag.add_theme_stylebox_override("normal", SimpleUI.style("ui.r3_simple_button_hover" if active else "ui.r3_simple_button"))
	var movement: Tween = create_tween()
	movement.tween_property(tag, "position", Vector2(tag.get_meta("rest_position")) + Vector2(0, -2 if active else 0), 0.12)
	tag.set_meta("hover_tween", movement)
