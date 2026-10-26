extends Node
## The sole translation from art semantic IDs to synchronized resource paths.

const MANIFEST_PATH: String = "res://resources/art/manifest.json"
const ART_ROOT: String = "res://resources/art/"
var _assets: Dictionary = {}
var _textures: Dictionary = {}
var _frame_sets: Dictionary = {}
var valid: bool = false

func _ready() -> void:
	valid = reload_manifest()

func reload_manifest() -> bool:
	_assets.clear()
	_textures.clear()
	_frame_sets.clear()
	var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("AssetCatalog: art manifest is missing; run sync")
		return false
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		push_error("AssetCatalog: invalid art manifest JSON")
		return false
	var manifest: Dictionary = parser.data
	if manifest.get("format", "") != "art-manifest/1":
		push_error("AssetCatalog: unsupported art manifest")
		return false
	for item: Dictionary in manifest.get("assets", []):
		var id: String = str(item.get("id", ""))
		var relative: String = str(item.get("file", ""))
		if id.is_empty() or _assets.has(id) or relative.is_empty() or relative.contains("..") or relative.is_absolute_path():
			push_error("AssetCatalog: invalid or duplicate asset: " + id)
			return false
		_assets[id] = item
	return true

func has_asset(id: String) -> bool:
	return _assets.has(id)

func metadata(id: String) -> Dictionary:
	return _assets.get(id, {}).duplicate(true)

func texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id] as Texture2D
	if not _assets.has(id):
		push_error("AssetCatalog: unknown asset " + id)
		return null
	var path: String = ART_ROOT + str(_assets[id]["file"])
	var result: Texture2D = load(path) as Texture2D
	if result == null:
		push_error("AssetCatalog: texture unavailable " + id)
		return null
	_textures[id] = result
	return result

func anchor(id: String) -> Vector2:
	var point: Array = _assets.get(id, {}).get("anchor", [0, 0])
	return Vector2(float(point[0]), float(point[1]))

func frame_size(id: String) -> Vector2i:
	var dimensions: Array = _assets.get(id, {}).get("size", [0, 0])
	return Vector2i(int(dimensions[0]), int(dimensions[1]))

func frames(id: String, animation: String = "idle") -> SpriteFrames:
	var cache_key: String = id + ":" + animation
	if _frame_sets.has(cache_key):
		return _frame_sets[cache_key] as SpriteFrames
	var info: Dictionary = _assets.get(id, {})
	var animation_info: Dictionary = info.get("animations", {}).get(animation, {})
	var atlas: Texture2D = texture(id)
	if info.is_empty() or animation_info.is_empty() or atlas == null:
		push_error("AssetCatalog: missing animation " + cache_key)
		return null
	var result: SpriteFrames = SpriteFrames.new()
	result.remove_animation("default")
	result.add_animation(animation)
	result.set_animation_speed(animation, float(animation_info.get("fps", 4)))
	result.set_animation_loop(animation, bool(animation_info.get("loop", true)))
	var dimensions: Vector2i = frame_size(id)
	for frame_index: Variant in animation_info.get("frames", []):
		var frame: AtlasTexture = AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2(int(frame_index) * dimensions.x, 0, dimensions.x, dimensions.y)
		result.add_frame(animation, frame)
	_frame_sets[cache_key] = result
	return result

func nine_slice(id: String) -> StyleBoxTexture:
	var info: Dictionary = _assets.get(id, {})
	var margins: Array = info.get("nineSlice", [0, 0, 0, 0])
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = texture(id)
	for side: int in range(4):
		style.set_texture_margin(side, float(margins[side]))
		style.set_content_margin(side, float(margins[side]) + 4.0)
	return style
