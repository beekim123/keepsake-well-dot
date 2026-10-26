extends RefCounted
## The approved low-detail skin. All visible frames are admitted AI textures;
## code supplies only nine-slice layout, text, hit regions and interaction.
const PixelFont = preload("res://resources/fonts/fusion-pixel-12px/fusion-pixel-12px-proportional-zh_hans.otf.woff2")
const REQUIRED_ART: Array[String] = [
	"board.r3_simple_town", "char.r3_simple_asui", "ui.r3_simple_station",
	"ui.r3_simple_panel", "ui.r3_simple_dialogue", "ui.r3_simple_button",
	"ui.r3_simple_button_hover", "ui.r3_simple_button_pressed", "ui.r3_simple_button_disabled",
	"ui.r3_simple_icon_energy"
]
const INK: Color = Color("20263d")
const PAPER: Color = Color("ffe4b6")
static func card_art(id: String) -> String:
	# Only the approved, separately admitted thin-paper V2 family is eligible.
	# Missing later-batch illustrations stay blank; rejected simple/legacy art
	# is never used as a visual fallback.
	const SUFFIXES: Array[String] = ["knock", "brace", "rope_lasso", "tug", "double_tap", "big_hammer", "dust_off", "wring", "yank", "curl_up", "clothesline", "push_back", "blanket", "pocket", "deep_breath", "knot", "shake_rope", "pick_up", "vow", "whisper", "deliver"]
	if not id.begins_with("cardart."): return ""
	var suffix: String = id.trim_prefix("cardart.")
	if suffix not in SUFFIXES: return ""
	var result: String = "cardart.r3_v2_" + suffix
	return result if AssetCatalog.has_asset(result) else ""

static func item_art(id: String) -> String:
	if id.begins_with("cardart."): return card_art(id)
	const RELICS: Array[String] = ["lone_glove", "spyglass", "lost_kite", "open_ink", "half_biscuit", "offkey_harmonica", "empty_frame", "leaky_balloon", "crooked_compass", "bookmark", "shedding_brush", "tangled_earbuds", "flat_ball", "birthday_candle", "odd_button"]
	var result: String = ""
	if id.begins_with("relic.") and id.trim_prefix("relic.") in RELICS:
		result = "relic.r3_simple_" + id.trim_prefix("relic.")
	elif id.begins_with("keepsake."):
		var suffix: String = id.trim_prefix("keepsake.").trim_suffix("_large")
		if suffix in ["ring", "mianmian", "letter"]: result = "keepsake.r3_simple_" + suffix
	return result if not result.is_empty() and AssetCatalog.has_asset(result) else ""

static func ready() -> bool:
	return REQUIRED_ART.all(func(id: String) -> bool: return AssetCatalog.has_asset(id))

static func style(id: String) -> StyleBoxTexture:
	var result: StyleBoxTexture = AssetCatalog.nine_slice(id)
	for side: int in range(4): result.set_content_margin(side, 4.0)
	return result

static func patch(node: NinePatchRect, id: String) -> void:
	node.texture = AssetCatalog.texture(id)
	var margins: Array = AssetCatalog.metadata(id).get("nineSlice", [4, 4, 4, 4])
	node.patch_margin_left = int(margins[0])
	node.patch_margin_top = int(margins[1])
	node.patch_margin_right = int(margins[2])
	node.patch_margin_bottom = int(margins[3])

static func theme() -> Theme:
	var result: Theme = Theme.new()
	var font: FontFile = PixelFont.duplicate() as FontFile
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	font.multichannel_signed_distance_field = false
	font.generate_mipmaps = false
	result.default_font = font
	result.default_font_size = 12
	for control: String in ["Label", "TooltipLabel", "Button"]:
		result.set_color("font_shadow_color", control, Color.TRANSPARENT)
		result.set_color("font_outline_color", control, Color.TRANSPARENT)
		result.set_constant("outline_size", control, 0)
		result.set_constant("shadow_offset_x", control, 0)
		result.set_constant("shadow_offset_y", control, 0)
	result.set_color("font_color", "Label", INK)
	result.set_color("font_color", "TooltipLabel", INK)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		result.set_color(state, "Button", PAPER)
	result.set_color("font_disabled_color", "Button", Color("8990a6"))
	if not ready():
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			result.set_stylebox(state, "Button", StyleBoxEmpty.new())
		result.set_stylebox("panel", "Panel", StyleBoxEmpty.new())
		return result
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		result.set_stylebox(state, "Button", style("ui.r3_simple_button" + ("" if state == "normal" else "_" + state)))
	result.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	result.set_stylebox("panel", "Panel", style("ui.r3_simple_panel"))
	result.set_stylebox("panel", "TooltipPanel", style("ui.r3_simple_panel"))
	for control: String in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", control, style("ui.r3_simple_station"))
		result.set_stylebox("scroll_focus", control, StyleBoxEmpty.new())
		for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, control, style("ui.r3_simple_button_hover"))
	# Slider track/thumb reuse real model textures; never draw a replacement.
	result.set_stylebox("slider", "HSlider", style("ui.r3_simple_station"))
	result.set_stylebox("grabber_area", "HSlider", style("ui.r3_simple_button"))
	result.set_stylebox("grabber_area_highlight", "HSlider", style("ui.r3_simple_button_hover"))
	for state: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		result.set_icon(state, "HSlider", AssetCatalog.texture("ui.r3_simple_icon_energy"))
	return result
