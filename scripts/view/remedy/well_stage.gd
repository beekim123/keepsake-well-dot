extends Node2D
## Clean town plate plus independent admitted model actors. No painted UI or
## historical vignette layers are used by the simplified opening.
const GeneratedUI = preload("res://scripts/view/remedy/generated_ui.gd")
var _clock: float = 0.0
var rope_active: bool = false
var descending: bool = false
var talking: bool = false
var assets_ready: bool = false
const REQUIRED_ART: Array[String] = ["board.r3_simple_town", "char.r3_simple_asui", "char.r3_simple_ma_ye", "char.r3_simple_mai_aunt"]
const AUNT_ART: String = "char.r3_simple_mai_aunt"

func _ready() -> void:
	assets_ready = GeneratedUI.ready() and REQUIRED_ART.all(func(id: String) -> bool: return AssetCatalog.has_asset(id))
	$Far.texture = AssetCatalog.texture("board.r3_simple_town")
	$Mid.hide()
	$Near.hide()
	$Embers.hide()
	_setup_actor($Asui, "char.r3_simple_asui")
	# No unrelated portrait or old-style silhouette stands in for an actor
	# awaiting its admitted asset. The exact speaker text remains in dialogue.
	_setup_actor($Aunt, AUNT_ART)
	_setup_actor($Maye, "char.r3_simple_ma_ye")
	_setup_actor($RopeGlow, "char.r3_simple_ma_ye")
	if AssetCatalog.has_asset("board.r3_simple_town"):
		# Reuse only the well's own front masonry as an occlusion layer. This is
		# independent stage art, not a screenshot or painted-over gameplay frame.
		var lip: AtlasTexture = AtlasTexture.new()
		lip.atlas = AssetCatalog.texture("board.r3_simple_town")
		lip.region = Rect2(442, 263, 198, 97)
		$WellLip.texture = lip

func _setup_actor(sprite: Sprite2D, id: String, frame: int = 0) -> void:
	if not AssetCatalog.has_asset(id): return
	var sheet: Texture2D = AssetCatalog.texture(id)
	var dimensions: Vector2i = AssetCatalog.frame_size(id)
	var texture: AtlasTexture = AtlasTexture.new()
	texture.atlas = sheet
	texture.region = Rect2(Vector2(mini(frame, int(AssetCatalog.metadata(id).get("frames", 1))-1) * dimensions.x, 0), Vector2(dimensions))
	sprite.texture = texture
	sprite.offset = -AssetCatalog.anchor(id)

func _process(delta: float) -> void:
	_clock += delta
	if not descending:
		$Asui.scale.y = 1.0 + sin(_clock * TAU / 2.4) * 0.012
		$Aunt.scale.y = 1.0 + sin((_clock + 0.6) * TAU / 2.4) * 0.012
	# This batch has one genuine pose, so speech is a slight transform, never
	# a duplicate frame advertised as new mouth or movement artwork.
	$Maye.rotation = sin(_clock * 4.0) * (0.018 if talking else 0.006)
	$RopeGlow.position = $Maye.position
	$RopeGlow.rotation = $Maye.rotation
	$WellLip.visible = descending
	$RopeGlow.visible = rope_active
	$RopeGlow.modulate.a = 0.28 + (sin(_clock * TAU / 0.8) + 1.0) * 0.18
