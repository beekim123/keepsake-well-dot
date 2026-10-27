extends Node2D
## Authentic source frames. Admitted r4 motion sheets play their actual poses;
## historical stills retain their existing presentation fallback.
var asset_id: String = ""
var base_position: Vector2 = Vector2.ZERO
var animation: String = "idle"
var _sprite: Node2D
var _motion: Tween
var _elapsed: float = 0.0
var _pose_until: float = 0.0
var direction: float = 1.0
var wilted: bool = false
var _last_wilted: bool = false

func setup(id: String, ground: Vector2) -> void:
	asset_id = id
	base_position = ground.round()
	position = base_position
	_sprite = AnimatedSprite2D.new() if int(AssetCatalog.metadata(id).get("frames", 1)) > 1 else Sprite2D.new()
	_sprite.centered = false
	_sprite.offset = -AssetCatalog.anchor(id)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	pose("idle")

func pose(value: String, seconds: float = 0.0) -> bool:
	if not AssetCatalog.has_asset(asset_id): return false
	animation = value
	_pose_until = _elapsed + maxf(seconds, 0.36) if value not in ["idle", "defeat"] else 0.0
	var animations: Dictionary = AssetCatalog.metadata(asset_id).get("animations", {})
	var source_pose: String = value if animations.has(value) else "idle"
	if _sprite is AnimatedSprite2D:
		_sprite.sprite_frames = AssetCatalog.frames(asset_id, source_pose)
		_sprite.play(source_pose)
	else:
		_sprite.texture = AssetCatalog.texture(asset_id)
	if _motion != null and _motion.is_valid(): _motion.kill()
	position = base_position
	scale = Vector2.ONE
	_sprite.modulate = Color.WHITE
	if _uses_motion_frames():
		if value == "idle": position = base_position + Vector2(0, 3 if wilted else 0)
		# Pose motion is in the sheet: no second squash/slide over the real frames.
		# Defeat is only a fade; this seven-frame sheet contains no death pose.
		if value == "defeat":
			_motion = create_tween()
			_motion.tween_property(_sprite, "modulate:a", 0.0, 0.2)
		return true
	if value == "idle": return true
	_motion = create_tween()
	match value:
		"attack", "cast":
			_motion.tween_property(self, "position", base_position + Vector2(direction * 10, -2), 0.09)
			_motion.tween_property(self, "position", base_position, 0.15)
		"hit", "hurt":
			_sprite.modulate = Color(1.6, 0.7, 0.7)
			_motion.tween_property(self, "position", base_position - Vector2(direction * 4, 0), 0.06)
			_motion.tween_property(self, "position", base_position, 0.12)
			_motion.parallel().tween_property(_sprite, "modulate", Color.WHITE, 0.12)
		"defeat":
			_motion.tween_property(self, "scale", Vector2(1.15, 0.2), 0.16)
			_motion.parallel().tween_property(_sprite, "modulate:a", 0.0, 0.2)
	return true

func _uses_motion_frames() -> bool:
	return asset_id.contains(".r4_") and asset_id.ends_with("_motion") and _sprite is AnimatedSprite2D

func _process(delta: float) -> void:
	_elapsed += delta
	if _pose_until > 0 and _elapsed >= _pose_until:
		_pose_until = 0.0
		pose("idle")
	if animation == "idle" and _uses_motion_frames():
		scale = Vector2.ONE
		if wilted != _last_wilted:
			_last_wilted = wilted
			position = base_position + Vector2(0, 3 if wilted else 0)
		_sprite.modulate = Color("aaa2aa") if wilted else Color.WHITE
	elif animation == "idle":
		scale.y = (0.84 if wilted else 1.0) + 0.015 * sin(_elapsed * 2.8 + base_position.x)
		_sprite.modulate = Color("aaa2aa") if wilted else Color.WHITE
