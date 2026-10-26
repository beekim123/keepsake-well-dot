extends AnimatedSprite2D
## Native pixel frames, anchored on a shared ground line. No tweened transforms.
var asset_id: String = ""
var base_position: Vector2 = Vector2.ZERO
var _pose_until: float = 0.0
var _elapsed: float = 0.0

func setup(id: String, ground: Vector2, animation: String = "idle") -> void:
	asset_id = id
	base_position = ground.round()
	position = base_position
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	centered = false
	offset = -AssetCatalog.anchor(id)
	pose(animation)

func pose(animation: String, seconds: float = 0.0) -> bool:
	if not AssetCatalog.has_asset(asset_id): return false
	var animations: Dictionary = AssetCatalog.metadata(asset_id).get("animations", {})
	if not animations.has(animation):
		if not animations.has("idle"): return false
		animation = "idle"
	sprite_frames = AssetCatalog.frames(asset_id, animation)
	play(animation)
	_pose_until = _elapsed + seconds if seconds > 0 else 0.0
	return true

func _process(delta: float) -> void:
	_elapsed += delta
	position = base_position.round()
	if _pose_until > 0 and _elapsed >= _pose_until:
		_pose_until = 0.0
		pose("idle")
