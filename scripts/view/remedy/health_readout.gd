extends Control
## Graphical projection of actual HP and engine-computed forecasts only.
const GeneratedUI = preload("res://scripts/view/remedy/generated_ui.gd")
@export var bar_width: float = 72.0
@export var bar_height: float = 6.0
var hp: int = 40
var max_hp: int = 40
var guard: int = 0
var ghost_hp: float = 40.0
var guard_display: float = 0.0
var predicted_loss: int = 0
var preview_hp: int = -1
var preview_guard: int = -1
var incoming: int = 0
var show_shield: bool = false
var clock: float = 0.0
var hp_tween: Tween
var guard_tween: Tween

func _ready() -> void:
	GeneratedUI.patch($Frame, "ui.r2_hp_frame")
	$Frame.position = Vector2(-2, -2)
	$Frame.size = Vector2(bar_width + 4, bar_height + 4)
	for pair: Array in [["GhostClip", "ui.r2_hp_ghost"], ["FillClip", "ui.r2_hp_fill"], ["LossClip", "ui.r2_hp_loss"]]:
		var clip: Control = get_node(str(pair[0]))
		var strip: TextureRect = clip.get_node("Texture")
		strip.texture = AssetCatalog.texture(str(pair[1]))
		strip.size = Vector2(bar_width, bar_height)
		clip.size.y = bar_height
	$GuardIcon.texture = AssetCatalog.texture(GeneratedUI.resolve("ui.icon.r2_guard"))
	$Values.size.x = bar_width
	$Prediction.position.x = bar_width + 4

func update_values(values: Dictionary, forecast: Dictionary = {}, shield_visible: bool = true, immediate: bool = false) -> void:
	var old_hp: int = hp
	hp = int(values.get("hp", 0))
	max_hp = maxi(1,int(values.get("max_hp", 1)))
	guard = int(values.get("guard", 0))
	show_shield = shield_visible
	predicted_loss = int(forecast.get("hp_loss", 0))
	incoming = int(forecast.get("incoming", 0))
	preview_hp = int(forecast.get("preview_hp", -1))
	preview_guard = int(forecast.get("preview_guard", -1))
	if hp_tween != null and hp_tween.is_valid(): hp_tween.kill()
	if immediate or hp >= old_hp:
		ghost_hp = float(hp)
	else:
		ghost_hp = maxf(ghost_hp, old_hp)
		hp_tween = create_tween()
		hp_tween.tween_interval(0.3)
		hp_tween.tween_property(self, "ghost_hp", float(hp),0.28)
	if guard_tween != null and guard_tween.is_valid(): guard_tween.kill()
	guard_tween = create_tween()
	guard_tween.tween_property(self,"guard_display",float(preview_guard if preview_guard >= 0 else guard),0.18)
	$Values.text = "%d/%d" % [hp,max_hp]
	$Prediction.text = "-%d" % predicted_loss if predicted_loss > 0 else (ContentCatalog.text("ui.r2.blocked") if incoming > 0 and maxi(guard,preview_guard) > 0 and ContentCatalog.has_entry("ui.r2.blocked") else "")
	$Prediction.add_theme_color_override("font_color",Color("e8604c") if predicted_loss > 0 else Color("c9e58a"))
	_sync_bars()

func _process(delta: float) -> void:
	clock += delta
	$GuardIcon.visible = show_shield and (guard > 0 or preview_guard > 0)
	$GuardValue.visible = $GuardIcon.visible
	$GuardValue.text = str(roundi(guard_display))
	_sync_bars()

func _sync_bars() -> void:
	$GhostClip.size.x = bar_width * clampf(ghost_hp / max_hp, 0.0, 1.0)
	$FillClip.size.x = bar_width * clampf(float(hp) / max_hp, 0.0, 1.0)
	var loss: int = predicted_loss if preview_hp < 0 else maxi(0, hp - preview_hp)
	var start: float = bar_width * maxi(0, hp - loss) / max_hp
	$LossClip.position.x = start
	$LossClip.size.x = bar_width * mini(hp, loss) / max_hp
	$LossClip/Texture.position.x = -start
	$LossClip.visible = loss > 0
	$LossClip.modulate.a = 0.64 + 0.36 * (sin(clock * 8.0) + 1.0) * 0.5
