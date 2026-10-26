extends RefCounted
## Texture-only R2 skin. Pixels come from the admitted model-generated pack;
## this helper only selects states and applies layout/nine-slice metadata.
const SimpleUI = preload("res://scripts/view/remedy/simple_ui.gd")
const PixelFont = preload("res://resources/fonts/fusion-pixel-12px/fusion-pixel-12px-proportional-zh_hans.otf.woff2")
const REQUIRED_ART: Array[String] = [
	"ui.r2_card_attack", "ui.r2_card_guard", "ui.r2_card_special",
	"ui.r2_button", "ui.r2_button_hover", "ui.r2_button_pressed", "ui.r2_button_disabled", "ui.r2_energy_frame",
	"ui.r2_dialogue", "ui.r2_panel", "ui.r2_station", "ui.r2_banner", "ui.r2_slider_grabber",
	"ui.r2_hp_frame", "ui.r2_hp_fill", "ui.r2_hp_ghost", "ui.r2_hp_loss",
	"ui.icon.r2_guard", "ui.icon.r2_deck", "ui.icon.r2_pause",
	"intent.r2_attack", "intent.r2_guard", "intent.r2_special", "intent.r2_idle",
	"ui.icon.r2_energy", "ui.icon.r2_energy_empty", "ui.r2_pointer",
	"fx.r2_tap_ring", "fx.r2_rope_strip", "fx.r2_shield_bubble", "fx.r2_particle"
]

static func resolve(id: String) -> String:
	var aliases: Dictionary = {
		"ui.r2_card_attack": "ui.r3_v2_card", "ui.r2_card_guard": "ui.r3_v2_card", "ui.r2_card_special": "ui.r3_v2_card",
		"ui.r2_button": "ui.r3_simple_button", "ui.r2_button_hover": "ui.r3_simple_button_hover", "ui.r2_button_pressed": "ui.r3_simple_button_pressed", "ui.r2_button_disabled": "ui.r3_simple_button_disabled",
		"ui.r2_panel": "ui.r3_simple_panel", "ui.r2_dialogue": "ui.r3_simple_dialogue", "ui.r2_station": "ui.r3_simple_station", "ui.r2_banner": "ui.r3_simple_station",
		"intent.r2_attack": "ui.r3_simple_icon_attack", "intent.r2_guard": "ui.r3_simple_icon_guard", "ui.icon.r2_guard": "ui.r3_simple_icon_guard", "ui.icon.r2_energy": "ui.r3_simple_icon_energy"
	}
	var candidate: String = str(aliases.get(id, id))
	return candidate if AssetCatalog.has_asset(candidate) else id

static func ready() -> bool:
	return REQUIRED_ART.all(func(id: String) -> bool: return AssetCatalog.has_asset(id))

static func missing() -> Array[String]:
	var result: Array[String] = []
	for id: String in REQUIRED_ART:
		if not AssetCatalog.has_asset(id): result.append(id)
	return result

static func frame(id: String, index: int = 0) -> Texture2D:
	if not AssetCatalog.has_asset(id): return null
	if int(AssetCatalog.metadata(id).get("frames", 1)) <= 1: return AssetCatalog.texture(id)
	var result: AtlasTexture = AtlasTexture.new()
	result.atlas = AssetCatalog.texture(id)
	var dimensions: Vector2i = AssetCatalog.frame_size(id)
	result.region = Rect2(index * dimensions.x, 0, dimensions.x, dimensions.y)
	return result

static func patch(node: NinePatchRect, id: String) -> void:
	id = resolve(id)
	if not AssetCatalog.has_asset(id): return
	node.texture = AssetCatalog.texture(id)
	var margins: Array = AssetCatalog.metadata(id).get("nineSlice", [4, 4, 4, 4])
	node.patch_margin_left = int(margins[0])
	node.patch_margin_top = int(margins[1])
	node.patch_margin_right = int(margins[2])
	node.patch_margin_bottom = int(margins[3])

static func style(id: String) -> StyleBoxTexture:
	id = resolve(id)
	var result: StyleBoxTexture = AssetCatalog.nine_slice(id)
	# Keep the 12px readable labels in the unchanged compact button geometry.
	for side: int in range(4): result.set_content_margin(side, 4.0)
	return result

static func theme() -> Theme:
	if SimpleUI.ready(): return SimpleUI.theme()
	var result: Theme = Theme.new()
	result.default_font = PixelFont
	result.default_font_size = 12
	# Do not inherit the historical dark-panel shadow/outline onto pale R2
	# generated paper. Keep every 12px font stroke at its authored width.
	for control: String in ["Label", "TooltipLabel", "Button"]:
		result.set_color("font_shadow_color", control, Color.TRANSPARENT)
		result.set_color("font_outline_color", control, Color.TRANSPARENT)
		result.set_constant("outline_size", control, 0)
		result.set_constant("shadow_offset_x", control, 0)
		result.set_constant("shadow_offset_y", control, 0)
	result.set_color("font_color", "Label", Color("1b1622"))
	result.set_color("font_color", "TooltipLabel", Color("1b1622"))
	result.set_color("font_color", "Button", Color("1b1622"))
	result.set_color("font_hover_color", "Button", Color("1b1622"))
	result.set_color("font_pressed_color", "Button", Color("d8dcdc"))
	result.set_color("font_disabled_color", "Button", Color("aab3ba"))
	if not ready():
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]: result.set_stylebox(state, "Button", StyleBoxEmpty.new())
		result.set_stylebox("panel", "Panel", StyleBoxEmpty.new())
		return result
	result.set_stylebox("normal", "Button", style("ui.r2_button"))
	result.set_stylebox("hover", "Button", style("ui.r2_button_hover"))
	result.set_stylebox("pressed", "Button", style("ui.r2_button_pressed"))
	result.set_stylebox("disabled", "Button", style("ui.r2_button_disabled"))
	result.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	result.set_stylebox("panel", "Panel", style("ui.r2_panel"))
	result.set_stylebox("panel", "TooltipPanel", style("ui.r2_panel"))
	result.set_stylebox("slider", "HSlider", style("ui.r2_hp_frame"))
	result.set_stylebox("grabber_area", "HSlider", style("ui.r2_hp_fill"))
	result.set_stylebox("grabber_area_highlight", "HSlider", style("ui.r2_hp_ghost"))
	for state: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		result.set_icon(state, "HSlider", AssetCatalog.texture("ui.r2_slider_grabber"))
	var grip: StyleBoxTexture = StyleBoxTexture.new()
	grip.texture = AssetCatalog.texture("ui.r2_slider_grabber")
	for side: int in range(4):
		grip.set_texture_margin(side, 2.0)
		grip.set_content_margin(side, 2.0)
	for control: String in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", control, style("ui.r2_station"))
		result.set_stylebox("scroll_focus", control, StyleBoxEmpty.new())
		for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, control, grip)
	return result
