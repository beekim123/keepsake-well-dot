extends Control
const GeneratedUI = preload("res://scripts/view/remedy/generated_ui.gd")
signal replay_requested
signal legacy_requested
signal title_requested
var won: bool = true

func _ready() -> void:
	theme = GeneratedUI.theme()
	GeneratedUI.patch($Panel, "ui.r2_panel")
	$Panel/Heading.text = ContentCatalog.text("ui.r2.endpoint_title" if won else "ui.r2.retry_title")
	$Panel/Body.text = ContentCatalog.text("ui.r2.endpoint_body" if won else "ui.r2.retry_body")
	$Panel/Replay.text = ContentCatalog.text("ui.r2.replay")
	$Panel/Legacy.text = ContentCatalog.text("ui.r2.legacy_continue")
	$Panel/Title.text = ContentCatalog.text("ui.r2.return_title")
	$Panel/Replay.pressed.connect(func() -> void: replay_requested.emit())
	$Panel/Legacy.pressed.connect(func() -> void: legacy_requested.emit())
	$Panel/Title.pressed.connect(func() -> void: title_requested.emit())
