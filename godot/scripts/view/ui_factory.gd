extends RefCounted
## Every frame is the explicitly-labelled D1 PNG nine-slice, never substitute art.
const PAPER: Color = Color("fffaf0")
const WARM: Color = Color("ffe08a")
const MUTED: Color = Color("ddb57a")
const BLUE: Color = Color("91d4d0")
const RED: Color = Color("ff9b87")

static func frame(parent: Node, name: String, rect: Rect2) -> Panel:
	var panel: Panel = Panel.new()
	panel.name = name
	panel.position = rect.position
	panel.size = rect.size
	parent.add_child(panel)
	return panel

static func label(parent: Node, text: String, rect: Rect2, color: Color = PAPER, font_size: int = 12) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.set_meta("allocated_rect", rect)
	result.position = rect.position
	result.size = rect.size
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func paragraph(parent: Node, text: String, rect: Rect2, color: Color = PAPER) -> Label:
	# Wrapping must be configured before text/add_child. Otherwise Godot retains
	# the initial unwrapped minimum width during the deferred layout pass.
	var result: Label = Label.new()
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.position = rect.position
	result.size = rect.size
	result.set_meta("allocated_rect", rect)
	result.add_theme_font_size_override("font_size", 12)
	result.add_theme_color_override("font_color", color)
	result.add_theme_constant_override("line_spacing", 4)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.text = text
	parent.add_child(result)
	return result

static func button(parent: Node, text: String, rect: Rect2, callback: Callable, name: String = "") -> Button:
	var result: Button = Button.new()
	result.name = name if not name.is_empty() else "Choice"
	result.text = text
	result.position = rect.position
	result.size = rect.size
	result.focus_mode = Control.FOCUS_NONE
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

static func clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func texture(parent: Node, catalog: Node, id: String, rect: Rect2) -> TextureRect:
	var image: TextureRect = TextureRect.new()
	image.texture = catalog.texture(id)
	image.position = rect.position
	image.size = rect.size
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image
