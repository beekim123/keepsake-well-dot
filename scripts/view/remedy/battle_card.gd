extends Node2D
## An authored card scene. The battle hand owns hit testing and fan animation.
const GeneratedUI = preload("res://scripts/view/remedy/generated_ui.gd")
const Art = preload("res://scripts/view/remedy/battle_art.gd")
const SIZE: Vector2 = Vector2(56, 76)

var uid: String = ""
var hand_index: int = -1
var definition: Dictionary = {}
var home: Vector2 = Vector2.ZERO
var home_angle: float = 0.0
var enabled: bool = true
var emphasized: bool = false
var hovered: bool = false
var clock: float = 0.0
var motion: Tween

func setup(instance: Dictionary, card: Dictionary, index: int, cost: int) -> void:
	uid = str(instance["uid"])
	hand_index = index
	definition = card
	$Name.text = str(card.get("name", ""))
	$Cost.text = str(cost)
	$Description.text = str(card.get("text", "")).replace(" ", "")
	var art: String = Art.card_art(card)
	if AssetCatalog.has_asset(art): $Art.texture = AssetCatalog.texture(art)
	var frame_id: String = Art.card_frame(card)
	$Frame.texture = AssetCatalog.texture(frame_id) if not frame_id.is_empty() else null
	for edge: String in ["left", "top", "right", "bottom"]:
		$Frame.set("patch_margin_" + edge, 0)
	# The entire AI paper is shown unchanged at 1× or integer 2×, not rebuilt
	# from the rejected cost badge/name strip/footer boxes.
	$Frame.size = SIZE
	var summary: Dictionary = Art.effect(card)
	$Effect.text = str(summary["text"])
	var icon: String = str(summary["icon"])
	if AssetCatalog.has_asset(icon): $EffectIcon.texture = AssetCatalog.texture(icon)
	$Effect.add_theme_color_override("font_color", Color("20263d"))
	_sync_art_state()

func contains_point(point: Vector2) -> bool:
	return Rect2(-28,-76,56,76).has_point(to_local(point))

func set_hover(value: bool) -> void:
	hovered = value
	_sync_art_state()
	_sync_description_pixels()

func place(at: Vector2, angle: float, zoom: float = 1.0, seconds: float = 0.08) -> void:
	if motion != null and motion.is_valid(): motion.kill()
	motion = create_tween().set_parallel(true)
	motion.tween_property(self, "position", at, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "rotation", angle, seconds)
	motion.tween_property(self, "scale", Vector2.ONE * zoom, seconds)

func _process(delta: float) -> void:
	clock += delta
	_sync_art_state()
	_sync_description_pixels()

func _sync_description_pixels() -> void:
	# All inspection text remains native12px while the paper scales exactly2×.
	# Hide the full description during transit/drag, just as the prior scene did.
	var settled: bool = hovered and is_equal_approx(scale.x, 2.0) and is_zero_approx(rotation)
	$Description.visible = settled
	if settled:
		for key: String in ["Cost", "Name", "Description", "Effect"]:
			var label: Label = get_node(key)
			label.scale = Vector2.ONE / global_scale
			label.rotation = -global_rotation
			label.global_position = to_global(label.position).round()
	else:
		for key: String in ["Cost", "Name", "Description", "Effect"]:
			var label: Label = get_node(key)
			label.scale = Vector2.ONE
			label.rotation = 0.0

func _sync_art_state() -> void:
	$Frame.size = SIZE
	$Art.position = Vector2(-20, -65) if hovered else Vector2(-20, -60)
	$Art.size = Vector2(40, 28)
	$Cost.position = Vector2(-23, -71)
	$Cost.size = Vector2(20, 16) if hovered else Vector2(16, 16)
	$Name.position = Vector2(-23, -37) if hovered else Vector2(-24, -32)
	$Name.size = Vector2(92, 16) if hovered else Vector2(48, 16)
	$Description.position = Vector2(-23, -28)
	$Description.size = Vector2(92, 34)
	$EffectIcon.position = Vector2(-11, -12) if hovered else Vector2(-19, -18)
	$EffectIcon.size = Vector2(6, 6) if hovered else Vector2(12, 12)
	$Effect.position = Vector2(-3, -13) if hovered else Vector2(-4, -18)
	$Effect.size = Vector2(44, 16) if hovered else Vector2(28, 16)
	var brightness: float = 1.0 + (0.10 + 0.08 * sin(clock * 6.0) if emphasized else 0.0)
	$Frame.modulate = Color(brightness, brightness, brightness, 1.0) if enabled else Color(0.68, 0.68, 0.72, 1.0)
	$Art.modulate = Color.WHITE if enabled else Color(0.68, 0.68, 0.72, 1.0)
