extends RefCounted
## Shared presentation only. Never mutates a rules state or consumes game RNG.
const GeneratedUI = preload("res://scripts/view/remedy/generated_ui.gd")
const PixelFont = preload("res://resources/fonts/fusion-pixel-12px/fusion-pixel-12px-proportional-zh_hans.otf.woff2")

static func pop(node: CanvasItem, amount: float = 1.15, seconds: float = 0.18) -> Tween:
	var original: Vector2 = node.scale
	node.scale = original * 0.6
	var tween: Tween = node.create_tween()
	tween.tween_property(node, "scale", original * amount, seconds * 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", original, seconds * 0.45)
	return tween

static func fly(node: CanvasItem, destination: Vector2, seconds: float = 0.12) -> Tween:
	var tween: Tween = node.create_tween().set_parallel(true)
	tween.tween_property(node, "position", destination, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(node, "scale", Vector2.ONE * 0.4, seconds)
	tween.tween_property(node, "modulate:a", 0.0, seconds)
	return tween

static func shake(node: CanvasItem, strength: float = 2.0, seconds: float = 0.12) -> Tween:
	var origin: Vector2 = node.position
	var tween: Tween = node.create_tween()
	for step: int in range(6):
		var direction: Vector2 = Vector2(-1.0 if step % 2 == 0 else 1.0, -0.45 if step % 3 == 0 else 0.45)
		tween.tween_property(node, "position", origin + direction * strength * (1.0 - float(step) / 6.0), seconds / 6.0)
	tween.tween_property(node, "position", origin, 0.001)
	return tween

static func flash(node: CanvasItem, color: Color = Color.WHITE, seconds: float = 0.055) -> Tween:
	var tween: Tween = node.create_tween()
	if node.material is ShaderMaterial:
		var material: ShaderMaterial = node.material as ShaderMaterial
		material.set_shader_parameter("flash_color", color)
		material.set_shader_parameter("flash_amount", 1.0)
		tween.tween_interval(seconds)
		tween.tween_callback(func() -> void: material.set_shader_parameter("flash_amount", 0.0))
	else:
		var original: Color = node.modulate
		node.modulate = color
		tween.tween_interval(seconds)
		tween.tween_property(node, "modulate", original, 0.02)
	return tween

static func hitstop(owner: Node, seconds: float = 0.05) -> void:
	# The timer ignores time scale and processes during pause, so a pause/close
	# cannot strand the game at a near-zero clock rate.
	var tree: SceneTree = owner.get_tree()
	Engine.time_scale = 0.05
	await tree.create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0

static func number(parent: Node, value: String, at: Vector2, color: Color = Color("e8604c")) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.position = at - Vector2(26, 14)
	label.size = Vector2(52, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",PixelFont)
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("1b1622"))
	label.add_theme_constant_override("outline_size", 4)
	label.pivot_offset = Vector2(26, 14)
	parent.add_child(label)
	pop(label, 1.35, 0.2)
	var tween: Tween = label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 28, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.3)
	tween.tween_callback(label.queue_free)
	return label

static func burst(parent: Node, at: Vector2, kind: String = "spark", count: int = 16) -> CPUParticles2D:
	if not AssetCatalog.has_asset("fx.r2_particle"):
		push_error("R2 particle artwork is not synchronized; no square-particle fallback is permitted.")
		return null
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.position = at
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = 0.55
	particles.explosiveness = 1.0
	particles.direction = Vector2.UP
	particles.spread = 140.0
	particles.gravity = Vector2(0, 130)
	particles.initial_velocity_min = 24.0
	particles.initial_velocity_max = 72.0
	particles.scale_amount_min = 0.5
	particles.scale_amount_max = 1.0
	particles.texture = GeneratedUI.frame("fx.r2_particle", int({"spark": 0, "dust": 1, "shine": 2}.get(kind, 0)))
	particles.color = Color.WHITE
	parent.add_child(particles)
	particles.emitting = true
	var tween: Tween = particles.create_tween()
	tween.tween_interval(0.8)
	tween.tween_callback(particles.queue_free)
	return particles
