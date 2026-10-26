extends Button
## Constrain long enemy rules and revealed futures to a readable tooltip width.
func _make_custom_tooltip(for_text: String) -> Object:
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	var label: Label = Label.new()
	var font: Font = get_theme_font("font")
	label.custom_minimum_size = Vector2(256, ceil(font.get_multiline_string_size(for_text, HORIZONTAL_ALIGNMENT_LEFT, 256, 12).y) + 4)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color("1b1622"))
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.add_theme_constant_override("outline_size",0)
	label.text = for_text
	margin.add_child(label)
	return margin
