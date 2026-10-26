extends RefCounted
## Fixed pixel controls; only AssetCatalog translates semantic art IDs.
const INK: Color = Color("1b1622")
const PAPER: Color = Color("fffaf0")
const WARM: Color = Color("ffe08a")
const MUTED: Color = Color("ddb57a")
const BLUE: Color = Color("7cd0cc")
const HEAL: Color = Color("c9e58a")
const RED: Color = Color("e8604c")

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
	_ink_style(result, color)
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
	_ink_style(result, color)
	result.add_theme_constant_override("line_spacing", 4)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.text = text
	parent.add_child(result)
	return result

static func _ink_style(label_node: Label, color: Color) -> void:
	# Paper already provides contrast. The dark-panel drop shadow otherwise
	# duplicates native 12px strokes and closes the counters of Chinese glyphs.
	if color != INK:
		return
	label_node.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label_node.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	label_node.add_theme_constant_override("shadow_offset_x", 0)
	label_node.add_theme_constant_override("shadow_offset_y", 0)
	label_node.add_theme_constant_override("outline_size", 0)

static func button(parent: Node, text: String, rect: Rect2, callback: Callable, name: String = "") -> Button:
	var result: Button = Button.new()
	result.name = name if not name.is_empty() else "Choice"
	result.text = text
	result.position = rect.position
	result.size = rect.size
	result.focus_mode = Control.FOCUS_NONE
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.mouse_entered.connect(func() -> void:
		var cue: String = "sfx.card_hover" if result.name.begins_with("Hand") else "sfx.ui_hover"
		if AudioService.has_cue(cue): AudioService.play(cue))
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

static func clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func texture(parent: Node, catalog: Node, id: String, rect: Rect2, pose: String = "") -> TextureRect:
	var image: TextureRect = TextureRect.new()
	# Set this before assigning a texture: Godot otherwise caches its intrinsic
	# minimum and expands a smaller requested rect (rope tiles/thumbs/heroes).
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var animations: Dictionary = catalog.metadata(id).get("animations", {})
	if animations.is_empty():
		image.texture = catalog.texture(id)
	else:
		var animation: String = pose if animations.has(pose) else ("idle" if animations.has("idle") else str(animations.keys()[0]))
		image.texture = catalog.frames(id, animation).get_frame_texture(animation, 0)
	image.position = rect.position
	image.size = rect.size
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image
