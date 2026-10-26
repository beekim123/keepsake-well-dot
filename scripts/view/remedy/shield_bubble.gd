extends Node2D
## The shield silhouette is model artwork; the scene only animates its state.
var active: bool = false
var clock: float = 0.0
@export var radius: Vector2 = Vector2(36,44)

func _ready() -> void:
	if AssetCatalog.has_asset("fx.r2_shield_bubble"):
		$Art.texture = AssetCatalog.texture("fx.r2_shield_bubble")
	$Art.position = Vector2(-radius.x, -radius.y * 2.0)
	$Art.size = radius * 2.0

func _process(delta: float) -> void:
	clock += delta
	$Art.visible = active
	$Art.modulate.a = 0.65 + sin(clock * 3.0) * 0.12
