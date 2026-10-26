extends Node2D
## Sparse model-texture water and lamp glints. No procedural scenery or game RNG.
const GeneratedUI = preload("res://scripts/view/remedy/generated_ui.gd")
var elapsed: float = 0.0

func _ready() -> void:
	for child: Node in $Drops.get_children(): child.texture = GeneratedUI.frame("fx.r2_particle", 3)
	for child: Node in $Lights.get_children(): child.texture = GeneratedUI.frame("fx.r2_particle", 4)

func _process(delta: float) -> void:
	elapsed += delta
	for index: int in range($Drops.get_child_count()):
		var sprite: Sprite2D = $Drops.get_child(index)
		var cycle: float = fmod(elapsed * 0.20 + index * 0.31, 1.0)
		sprite.position.y = 96 + cycle * 136
		sprite.modulate.a = 0.28 * sin(cycle * PI)
	for index: int in range($Lights.get_child_count()):
		var sprite: Sprite2D = $Lights.get_child(index)
		sprite.modulate.a = 0.20 + 0.08 * sin(elapsed * 3.0 + index)
