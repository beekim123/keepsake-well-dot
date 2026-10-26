extends Control
const SimpleUI = preload("res://scripts/view/remedy/simple_ui.gd")
signal start_requested
signal continue_requested
signal settings_requested
var has_progress: bool = false
var notice: String = ""

func _ready() -> void:
	theme = SimpleUI.theme()
	$Stage.texture = AssetCatalog.texture("board.r3_simple_town")
	$Asui.texture = AssetCatalog.texture("char.r3_simple_asui")
	$Asui.offset = -AssetCatalog.anchor("char.r3_simple_asui")
	SimpleUI.patch($Shade, "ui.r3_simple_station")
	$Title.text = ContentCatalog.text("ui.game_title")
	$Menu/Start.text = ContentCatalog.text("ui.r2.start")
	$Menu/Start.tooltip_text = ContentCatalog.text("ui.r2.start_hint")
	$Menu/Continue.text = ContentCatalog.text("ui.r2.continue")
	$Menu/Settings.text = ContentCatalog.text("ui.r2.settings")
	$Menu/Continue.visible = has_progress
	$Notice.text = notice
	$Menu/Start.pressed.connect(func() -> void: start_requested.emit())
	$Menu/Continue.pressed.connect(func() -> void: continue_requested.emit())
	$Menu/Settings.pressed.connect(func() -> void: settings_requested.emit())
	for button: Button in [$Menu/Start, $Menu/Continue, $Menu/Settings]:
		button.mouse_entered.connect(func() -> void: AudioService.play("sfx.ui_hover"))

	if not SimpleUI.ready():
		$Menu.hide()
		$Notice.text = ContentCatalog.text("ui.r2.no_assets")
		push_error("Approved low-detail UI pack is incomplete")
