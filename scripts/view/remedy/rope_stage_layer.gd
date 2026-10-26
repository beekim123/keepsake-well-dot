extends Control
## Explicit code-drawn UI placeholders until reviewed r4 textures arrive.
## This layer projects state; rope geometry never determines game rules.
const Art = preload("res://scripts/view/remedy/battle_art.gd")
const ROPE: Color = Color("ddb57a")
const SHADE: Color = Color("5a3a26")
var state: Dictionary = {}
var centers: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	# The clothesline and clips are decorative only.
	_rope(Vector2(90, 280), Vector2(550, 280), 4)
	var enemies: Array = state.get("enemies", [])
	for index: int in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		if not centers.has(index) or not str(enemy.get("departed", "")).is_empty() or int(enemy.get("hp", 0)) <= 0: continue
		var point: Vector2 = centers[index]
		var binds: int = int(enemy.get("binds", 0))
		if binds > 0:
			var tier: String = "low" if binds < 4 else ("mid" if binds < 8 else "high")
			var art: String = Art.available(["fx.r4_bind_" + tier])
			if not art.is_empty(): draw_texture_rect(AssetCatalog.texture(art), Rect2(point - Vector2(24, 12), Vector2(48, 32)), false)
			else:
				for ring: int in range(1 if binds < 4 else (2 if binds < 8 else 3)):
					var y: float = point.y - 5 + ring * 6
					draw_polyline(PackedVector2Array([Vector2(point.x-22,y),Vector2(point.x-17,y+4),Vector2(point.x+17,y+4),Vector2(point.x+22,y),Vector2(point.x+17,y-3),Vector2(point.x-17,y-3),Vector2(point.x-22,y)]), SHADE, 4)
					draw_polyline(PackedVector2Array([Vector2(point.x-22,y-1),Vector2(point.x-17,y+3),Vector2(point.x+17,y+3),Vector2(point.x+22,y-1)]), ROPE, 2)
		var partner: String = str(enemy.get("tie", ""))
		for other: int in range(index + 1, enemies.size()):
			if centers.has(other) and str(enemies[other].get("uid", "")) == partner and str(enemies[other].get("departed", "")).is_empty():
				_rope(point, centers[other], 20)
				_knot(point)
				_knot(centers[other])
	# Lantern at Asui's shoulder: the flames are the actual remaining energy.
	draw_rect(Rect2(172, 182, 34, 42), SHADE)
	draw_rect(Rect2(175, 186, 28, 32), Color("453b3c"))
	draw_line(Vector2(181,182),Vector2(181,177),ROPE,2)
	draw_line(Vector2(181,177),Vector2(197,177),ROPE,2)
	draw_line(Vector2(197,177),Vector2(197,182),ROPE,2)
	for flame: int in range(3):
		var x: float = 180 + flame * 9
		var color: Color = Color("ffd57a") if flame < int(state.get("energy", 0)) else Color("6b6261")
		draw_colored_polygon(PackedVector2Array([Vector2(x,192),Vector2(x-3,201),Vector2(x-2,207),Vector2(x+3,207),Vector2(x+4,201)]),color)
	# Laundry basket near Ma Ye; transparent button above it handles both piles.
	draw_colored_polygon(PackedVector2Array([Vector2(20,71),Vector2(70,71),Vector2(64,100),Vector2(26,100)]),SHADE)
	for y: int in range(74,100,6): draw_line(Vector2(24,y),Vector2(66,y),ROPE,2)
	for x: int in range(28,66,8): draw_line(Vector2(x,72),Vector2(x,99),ROPE,2)
	# Rope pull ring; E and button remain the input contract.
	draw_line(Vector2(185,226),Vector2(185,235),ROPE,3)
	var loop: PackedVector2Array = []
	for i: int in range(17):
		var angle: float = i * TAU / 16
		loop.append((Vector2(185,244) + Vector2(cos(angle)*10,sin(angle)*9)).round())
	draw_polyline(loop,ROPE,3)

func _knot(point: Vector2) -> void:
	draw_rect(Rect2(point-Vector2(3,3),Vector2(7,7)),SHADE)
	draw_line(point-Vector2(4,4),point+Vector2(4,4),ROPE,2)
	draw_line(point+Vector2(-4,4),point+Vector2(4,-4),ROPE,2)

func _rope(from: Vector2, to: Vector2, sag: float) -> void:
	var points: PackedVector2Array = []
	for i: int in range(25):
		var fraction: float = i / 24.0
		points.append((from.lerp(to,fraction)+Vector2(0,sin(fraction*PI)*sag)).round())
	draw_polyline(points,SHADE,4)
	draw_polyline(points,ROPE,2)
