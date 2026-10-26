extends Node2D
## A looping generated hand gesture, never an input substitute.
var start: Vector2 = Vector2.ZERO
var finish: Vector2 = Vector2.ZERO
var elapsed: float = 0.0
var pointing: bool = false

func _ready() -> void:
	if AssetCatalog.has_asset("ui.r2_pointer"): $Hand.texture = AssetCatalog.texture("ui.r2_pointer")
	if AssetCatalog.has_asset("fx.r2_tap_ring"): $Ring.texture = AssetCatalog.texture("fx.r2_tap_ring")

func guide(from: Vector2, to: Vector2, tap: bool = false) -> void:
	if from != start or to != finish: elapsed = 0.0
	start = from
	finish = to
	pointing = tap
	show()

func _process(delta: float) -> void:
	if not visible: return
	elapsed += delta
	var phase: float = fmod(elapsed,2.5)
	var progress: float = smoothstep(0.35,1.45,phase)
	position = start.lerp(finish,progress) + Vector2(0,-4.0*sin(minf(progress,1)*PI))
	if pointing: position = start+Vector2(0,3.0*sin(elapsed*7.0))
	modulate.a = 1.0-smoothstep(1.85,2.25,phase)
	$Ring.visible = phase < 0.35
	$Ring.scale = Vector2.ONE * (0.45 + minf(phase, 0.35))
	$Ring.modulate.a = 1.0 - minf(phase / 0.35, 1.0)
