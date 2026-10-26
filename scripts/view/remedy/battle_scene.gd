extends Node2D
## R2 side-view stage. The rules are the sole authority for commands, previews,
## locks, card order, HP and outcome. This scene only presents their events.
signal checkpoint(state: Dictionary)
signal tutorial_completed(result: Dictionary)
signal exit_requested
signal command_finished(events: Array)

const GeneratedUI = preload("res://scripts/view/remedy/generated_ui.gd")
const Art = preload("res://scripts/view/remedy/battle_art.gd")
const Rules = preload("res://scripts/core/battle_rules.gd")
const Juice = preload("res://scripts/view/remedy/juice.gd")
const CardScene = preload("res://scenes/remedy/BattleCard.tscn")
const HERO_HOME: Vector2 = Vector2(130,236)
const ENEMY_HOME: Vector2 = Vector2(476,236)
const REQUIRED_ART: Array[String] = ["char.r2_asui","enemy.r2_wet_sock","char.r2_ma_ye","board.r2_sock_swamp_far","board.r2_sock_swamp_mid","board.r2_sock_swamp_near","cardart.r2_knock","cardart.r2_brace","cardart.r2_rope_lasso","cardart.r2_tug","intent.r2_attack","ui.icon.r2_energy","ui.icon.r2_energy_empty"]
var config: Dictionary = {}
var rules: RefCounted
var state: Dictionary = {}
var displayed: Dictionary = {}
var busy: bool = true
var assets_ready: bool = false
var instant_presentation: bool = false
var presented_events: Array = []
var _cards: Array[Node2D] = []
var _legal: Array = []
var _forecast: Dictionary = {}
var _status: Dictionary = {}
var _hover: Node2D
var _selected: Node2D
var _dragged: Node2D
var _press_origin: Vector2 = Vector2.ZERO
var _last_pointer: Vector2 = Vector2.ZERO
var _drag_moved: bool = false
var _target: int = -1
var _elapsed: float = 0.0
var _paused: bool = false
var _focused: bool = true
var _last_prompt: String = ""
var _completion_emitted: bool = false
var _lifecycle: int = 0
var _preview: Dictionary = {}
var _trails: Array[Sprite2D] = []
var _maye_frames: Array[Texture2D] = []
var _actor_tracks: Dictionary = {}
@onready var ui: Control = $Interface/UI
@onready var stage: Node2D = $Stage
@onready var hero: Node2D = $Stage/Hero
@onready var enemy: Node2D = $Stage/Enemy
@onready var bubble: Control = $Interface/UI/Dialogue
@onready var hand: Node2D = $Interface/UI/Hand
@onready var hero_hp: Control = $Interface/UI/PlayerHealth
@onready var enemy_hp: Control = $Interface/UI/EnemyHealth
@onready var end_button: Button = $Interface/UI/EndTurn
@onready var gesture: Node2D = $Interface/UI/Gesture

func _ready() -> void:
	ui.theme = GeneratedUI.theme()
	GeneratedUI.patch(ui.get_node("Station"), "ui.r2_station")
	GeneratedUI.patch(ui.get_node("Banner"), "ui.r2_banner")
	if AssetCatalog.has_asset("ui.icon.r2_pause"): ui.get_node("Pause").icon = AssetCatalog.texture("ui.icon.r2_pause")
	ui.get_node("Pause").pressed.connect(toggle_pause)
	end_button.pressed.connect(request_end_turn)
	ui.get_node("PauseOverlay/Resume").pressed.connect(toggle_pause)
	ui.get_node("PauseOverlay/Retry").pressed.connect(restart_tutorial)
	ui.get_node("PauseOverlay/Exit").pressed.connect(_exit_to_title)
	for key: String in ["EndTurn","PauseOverlay/Resume","PauseOverlay/Retry","PauseOverlay/Exit"]:
		var button: Button = ui.get_node(key) as Button
		button.mouse_entered.connect(func() -> void: _cue("sfx.ui_hover"))
	_apply_text()
	call_deferred("_begin_configured")

func _begin_configured() -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	start_tutorial(config)

func _apply_text() -> void:
	ui.get_node("Station/Name").text = _text("battle_station")
	end_button.text = _text("end_turn")
	ui.get_node("Pause").tooltip_text = _text("pause")
	ui.get_node("PauseOverlay/Resume").text = _text("resume")
	ui.get_node("PauseOverlay/Retry").text = _text("retry")
	ui.get_node("PauseOverlay/Exit").text = _text("return_title")

func _text(key: String) -> String:
	return ContentCatalog.text("ui.r2."+key) if ContentCatalog.has_entry("ui.r2."+key) else ""

func start_tutorial(options: Dictionary = {}) -> void:
	_lifecycle += 1
	var token: int = _lifecycle
	config = options.duplicate(true)
	instant_presentation = bool(config.get("instant_presentation",false))
	_completion_emitted = false
	busy = true
	_paused = false
	ui.get_node("PauseOverlay").hide()
	_apply_suspend()
	_cancel_selection(false)
	for card: Node2D in _cards: card.queue_free()
	_cards.clear()
	presented_events.clear()
	_last_prompt = ""
	rules = Rules.new(ContentCatalog.definitions())
	assets_ready = _load_assets()
	if not assets_ready:
		bubble.say(_text("no_assets"),"",0)
		push_error("R2 BattleScene: model-generated R2 pack is incomplete; no procedural art fallback is permitted: " + ", ".join(GeneratedUI.missing()))
		return
	var resume: Variant = config.get("resume_state",{})
	var resumed: bool = resume is Dictionary and not resume.is_empty() and rules.is_tutorial_state_valid(resume)
	if resumed:
		state = resume.duplicate(true)
	else:
		var started: Dictionary = rules.start_tutorial({},int(config.get("seed",1)))
		state = started.get("state",{})
	if state.is_empty():
		push_error("R2 BattleScene: could not start registered tutorial")
		return
	displayed = state.duplicate(true)
	hero.position = HERO_HOME
	hero.scale = Vector2.ONE
	enemy.position = ENEMY_HOME
	enemy.scale = Vector2.ONE
	enemy.modulate = Color.WHITE
	enemy.visible = int(state["enemies"][0]["hp"])>0
	ui.get_node("EnemyHealth").visible = enemy.visible
	ui.get_node("Intent").visible = enemy.visible
	_refresh_authority()
	_sync_readouts(true)
	_cue("music.battle")
	if AudioService.has_method("set_ambience"): AudioService.set_ambience("battle")
	if resumed:
		_sync_hand(false)
	else:
		await _show_banner(_text("player_turn"),"sfx.turn_start")
		if not _alive(token): return
		await _deal_hand()
	if not _alive(token): return
	busy = false
	_refresh_authority()
	_sync_readouts()
	_show_prompt(_status)
	checkpoint.emit(state.duplicate(true))

func _load_assets() -> bool:
	if not GeneratedUI.ready(): return false
	ui.get_node("TargetRope").texture = AssetCatalog.texture("fx.r2_rope_strip")
	ui.get_node("Energy/Frame").texture = AssetCatalog.texture("ui.r2_energy_frame")
	for id: String in REQUIRED_ART:
		if not AssetCatalog.has_asset(id): return false
	$Stage/Far.texture = AssetCatalog.texture("board.r2_sock_swamp_far")
	$Stage/Mid.texture = AssetCatalog.texture("board.r2_sock_swamp_mid")
	$Stage/Near.texture = AssetCatalog.texture("board.r2_sock_swamp_near")
	_actor_tracks.clear()
	_prepare_actor(hero,Art.actor("char.r2_asui"))
	_prepare_actor(enemy,Art.actor("enemy.r2_wet_sock"),1.25)
	var maye_id: String = Art.actor("char.r2_ma_ye")
	$Stage/MaYe.texture = _asset_frame(maye_id)
	$Stage/MaYe.offset = -AssetCatalog.anchor(maye_id)
	$Stage/MaYe.scale = Vector2.ONE
	$Stage/MaYe.rotation = 0.0
	_maye_frames = []
	for index: int in range(int(AssetCatalog.metadata(maye_id).get("frames",1))):
		_maye_frames.append(_asset_frame(maye_id,index))
	return true

func _asset_frame(id: String, index: int = 0) -> Texture2D:
	var texture: Texture2D = AssetCatalog.texture(id)
	var info: Dictionary = AssetCatalog.metadata(id)
	if int(info.get("frames",1))<=1: return texture
	var dimensions: Vector2i = AssetCatalog.frame_size(id)
	var frame: AtlasTexture = AtlasTexture.new()
	frame.atlas = texture
	frame.region = Rect2(index*dimensions.x,0,dimensions.x,dimensions.y)
	return frame

# Sprite sheets contain authored cell changes rather than a continuously
# stretched still. The metadata remains the animation authority; old one-frame
# assets are a safe idle-only fallback until the root synchronizes the new art.
func _prepare_actor(actor: Node2D, id: String, phase: float = 0.0) -> void:
	var sprite: Sprite2D = actor.get_node("Portrait") as Sprite2D
	var info: Dictionary = AssetCatalog.metadata(id)
	var textures: Array[Texture2D] = []
	for index: int in range(int(info.get("frames",1))): textures.append(_asset_frame(id,index))
	sprite.offset = -AssetCatalog.anchor(id)
	sprite.scale = Vector2.ONE
	sprite.texture = textures[0]
	_actor_tracks[actor] = {"textures":textures,"animations":info.get("animations",{}),"animation":"idle","elapsed":phase}
	_tick_actor(actor,0.0)

func _pose_actor(actor: Node2D, animation: String) -> void:
	if not _actor_tracks.has(actor): return
	var track: Dictionary = _actor_tracks[actor]
	if not track["animations"].has(animation): return
	track["animation"] = animation
	track["elapsed"] = 0.0
	_tick_actor(actor,0.0)

func _tick_actor(actor: Node2D, delta: float) -> void:
	if not _actor_tracks.has(actor): return
	var track: Dictionary = _actor_tracks[actor]
	track["elapsed"] = float(track["elapsed"])+delta
	var animation: Dictionary = track["animations"].get(track["animation"],{})
	var sequence: Array = animation.get("frames",[0])
	if sequence.is_empty(): return
	var step: int = int(float(track["elapsed"])*float(animation.get("fps",4)))
	if not bool(animation.get("loop",true)) and step>=sequence.size():
		track["animation"] = "idle"
		track["elapsed"] = 0.0
		animation = track["animations"].get("idle",{})
		sequence = animation.get("frames",[0])
		step = 0
	var sprite: Sprite2D = actor.get_node("Portrait") as Sprite2D
	sprite.texture = track["textures"][int(sequence[step%sequence.size()])]

func _refresh_authority() -> void:
	_legal = rules.legal_actions(state)
	_forecast = rules.forecast(state)
	_status = rules.tutorial_status(state)
	end_button.disabled = busy or not bool(_status.get("can_end_turn",false))
	for card: Node2D in _cards:
		card.hand_index = rules.find_card(state.get("hand",[]),card.uid)
		card.enabled = not _actions_for(card.hand_index).is_empty()
		card.emphasized = str(_status.get("allowed_card_uid","")) == card.uid
		if str(_status.get("guide",""))=="drag_enemy" and str(_status.get("allowed_card_uid","")).is_empty():
			card.emphasized = card.enabled
		card.queue_redraw()
	_update_gesture()

func _sync_readouts(immediate: bool = false) -> void:
	if displayed.is_empty(): return
	var forecast: Dictionary = _forecast if not busy else {}
	var shield_visible: bool = bool(_status.get("show_shield",false))
	hero_hp.update_values(displayed["player"],forecast,shield_visible,immediate)
	enemy_hp.update_values(displayed["enemies"][0],{},true,immediate)
	$Stage/Hero/Shield.active = int(displayed["player"]["guard"])>0 and shield_visible
	$Stage/Enemy/Shield.active = int(displayed["enemies"][0]["guard"])>0
	ui.get_node("Energy/Value").text = "%d/3" % int(displayed["energy"])
	ui.get_node("Energy/Orb").texture = AssetCatalog.texture("ui.r3_simple_icon_energy")
	ui.get_node("Energy/Orb").modulate = Color.WHITE if int(displayed["energy"])>0 else Color(0.45,0.45,0.5)
	if not busy:
		var intents: Array = _forecast.get("intents",[])
		if not intents.is_empty(): _show_intent(intents[0])

func _show_intent(intent: Dictionary) -> void:
	var id: String = Art.intent(str(intent.get("type","idle")))
	ui.get_node("Intent/Icon").texture = AssetCatalog.texture(id)
	ui.get_node("Intent/Value").text = str(int(intent.get("amount",0))) if int(intent.get("amount",0))>0 else ""

func _sync_hand(animated: bool = true) -> void:
	var hand_data: Array = displayed.get("hand",[])
	var retained: Array[Node2D] = []
	for index: int in range(hand_data.size()):
		var instance: Dictionary = hand_data[index]
		var card: Node2D = _card_by_uid(str(instance["uid"]))
		if card == null:
			card = CardScene.instantiate()
			hand.add_child(card)
			card.setup(instance,ContentCatalog.entry(instance["id"]),index,rules.card_cost(state,ContentCatalog.entry(instance["id"])))
			card.position = Vector2(-40,355) if animated else Vector2(320,354)
			card.rotation = -0.6 if animated else 0.0
		card.hand_index = index
		retained.append(card)
	for old: Node2D in _cards:
		if not retained.has(old) and is_instance_valid(old): old.queue_free()
	_cards = retained
	_layout_hand(0.24 if animated else 0.001)

func _layout_hand(seconds: float = 0.08) -> void:
	var count: int = _cards.size()
	var spacing: float = minf(61.0,330.0/maxi(1,count-1))
	for index: int in range(count):
		var card: Node2D = _cards[index]
		var relative: float = float(index)-float(count-1)*0.5
		card.home_angle = relative*0.095
		# Keep all rotated corners in the 640x360 frame, including tug's 5-card
		# hand and the engine's 8-card limit. Hover details also stay onscreen.
		var bottom_clearance: float = absf(sin(card.home_angle))*28.0
		card.home = Vector2(320+relative*spacing,minf(348+absf(relative)*1.4,354-bottom_clearance))
		if card == _dragged: continue
		var highlighted: bool = card == _hover or card == _selected
		card.modulate.a = 1.0
		var destination: Vector2 = card.home+Vector2(0,-16 if highlighted else 0)
		# Integer2× continuous paper gives a112×152 inspection card.
		if highlighted: destination.y = minf(destination.y,314.0)
		if _hover != null and not highlighted:
			destination.x += -8.0 if index < _cards.find(_hover) else 8.0
		card.set_hover(highlighted)
		card.z_index = 30 if highlighted else index
		card.place(destination,0.0 if highlighted else card.home_angle,2.0 if highlighted else 1.0,seconds)

func _deal_hand() -> void:
	var dealt: Array = displayed["hand"].duplicate(true)
	displayed["hand"] = []
	for instance: Dictionary in dealt:
		displayed["hand"].append(instance)
		_sync_hand(true)
		_cue("sfx.draw")
		await _wait(0.06)
	await _wait(0.2)

func _card_by_uid(uid: String) -> Node2D:
	for card: Node2D in _cards:
		if is_instance_valid(card) and card.uid==uid: return card
	return null

func _actions_for(index: int) -> Array:
	var result: Array = []
	for action: Dictionary in _legal:
		if action.get("type","")=="play_card" and int(action.get("hand_index",-1))==index: result.append(action)
	return result

func _action_for(index: int, target_index: int) -> Dictionary:
	for action: Dictionary in _actions_for(index):
		if int(action.get("target_index",-1))==target_index: return action
	return {}

func _card_at(point: Vector2) -> Node2D:
	if _hover != null and is_instance_valid(_hover) and _hover.contains_point(point): return _hover
	for index: int in range(_cards.size()-1,-1,-1):
		if _cards[index].contains_point(point): return _cards[index]
	return null

func _input(event: InputEvent) -> void:
	if state.is_empty() or not assets_ready or not _focused: return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
		return
	if _paused or busy: return
	if event is InputEventMouseMotion:
		_pointer_moved(get_canvas_transform().affine_inverse()*event.position)
	elif event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_selection()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			var point: Vector2 = get_canvas_transform().affine_inverse()*event.position
			if event.pressed: _pointer_down(point)
			else: _pointer_up(point)

func _pointer_down(point: Vector2) -> void:
	if ui.get_node("Pause").get_global_rect().has_point(point) or end_button.get_global_rect().has_point(point) or (bubble.visible and bubble.get_global_rect().has_point(point)): return
	var card: Node2D = _card_at(point)
	if card != null:
		if not card.enabled:
			_reject(card)
			return
		_selected = card
		_dragged = card
		_hover = null
		_press_origin = point
		_last_pointer = point
		_drag_moved = false
		if card.motion != null and card.motion.is_valid(): card.motion.kill()
		card.set_hover(true)
		card.scale = Vector2.ONE*2.0
		card.z_index = 35
		_cue("sfx.card_pick")
		gesture.hide()
		get_viewport().set_input_as_handled()
	elif _selected != null:
		var target_index: int = _drop_target(_selected,point)
		if target_index != -2: _play_selected(target_index)
		else: _reject(_selected)

func _pointer_moved(point: Vector2) -> void:
	if _dragged != null:
		var speed: float = point.x-_last_pointer.x
		_drag_moved = _drag_moved or point.distance_to(_press_origin)>5.0
		if _drag_moved:
			# Keep the aimed-at actor and its HP visible, rather than putting a
			# 1.6x inspection card directly over the legal target's whole body.
			_dragged.position = point+Vector2(-45,40)
			_dragged.scale = Vector2.ONE*1.1
			_dragged.modulate.a = 0.88
			_dragged.set_hover(false)
			_dragged.rotation = clampf(speed*0.012,-0.14,0.14)
			_target = _drop_target(_dragged,point)
			_update_target_preview(_dragged,_target)
			_draw_rope(point)
		_last_pointer = point
		return
	var card: Node2D = _card_at(point)
	if card != _hover:
		_hover = card
		if card != null: _cue("sfx.card_hover")
		_layout_hand()

func _pointer_up(point: Vector2) -> void:
	if _dragged == null: return
	var card: Node2D = _dragged
	_dragged = null
	_clear_rope()
	if _drag_moved:
		var target_index: int = _drop_target(card,point)
		if target_index==-2:
			_reject(card)
		else:
			_play_selected(target_index)
	else:
		_target = 0 if str(card.definition.get("target","self"))=="enemy" else -1
		_layout_hand()
		_update_target_preview(card,_target)
	get_viewport().set_input_as_handled()

func _drop_target(card: Node2D, point: Vector2) -> int:
	if str(card.definition.get("target","self"))=="enemy":
		return 0 if Rect2(434,164,84,78).has_point(point) and int(state["enemies"][0]["hp"])>0 else -2
	# Self/no-target cards accept the stage, not buttons, dialogue or the hand.
	return -1 if Rect2(72,92,535,151).has_point(point) else -2

func _update_target_preview(card: Node2D, target_index: int) -> void:
	_clear_preview()
	if target_index==-2: return
	var action: Dictionary = _action_for(card.hand_index,target_index)
	if action.is_empty(): return
	_preview = rules.preview(state,card.hand_index,target_index,action.get("choices",{}))
	if not bool(_preview.get("valid",false)): return
	var next_player: Dictionary = _preview["player"]
	var after: Dictionary = _preview["forecast_after"].duplicate(true)
	after["preview_guard"] = int(next_player["guard"])
	hero_hp.update_values(state["player"],after,bool(_status.get("show_shield",false)),true)
	var changes: Array = _preview.get("enemy_changes",[])
	if not changes.is_empty():
		enemy_hp.update_values(state["enemies"][0],{"preview_hp":int(changes[0]["hp_after"]),"preview_guard":int(changes[0]["guard_after"])},true,true)
	var target_sprite: Sprite2D = $Stage/Enemy/Portrait if target_index==0 or str(card.definition.get("type",""))=="attack" else $Stage/Hero/Portrait
	(target_sprite.material as ShaderMaterial).set_shader_parameter("outlined",1.0)
	target_sprite.position.y = -2.0

func _clear_preview() -> void:
	_preview.clear()
	for sprite: Sprite2D in [$Stage/Hero/Portrait,$Stage/Enemy/Portrait]:
		(sprite.material as ShaderMaterial).set_shader_parameter("outlined",0.0)
		sprite.position.y = 0.0
	_sync_readouts()

func _draw_rope(point: Vector2) -> void:
	if _dragged == null or str(_dragged.definition.get("target","self"))!="enemy": return
	var origin: Vector2 = _dragged.home-Vector2(0,32)
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(20):
		var t: float = float(index)/19.0
		points.append(origin.lerp(point,t)+Vector2(sin(t*PI*6)*1.2,-sin(t*PI)*23))
	ui.get_node("TargetRope").points = points
	ui.get_node("TargetRope").modulate = Color(1.14,1.14,1.14,1.0) if _target==0 else Color.WHITE

func _clear_rope() -> void:
	ui.get_node("TargetRope").clear_points()

func _cancel_selection(sound: bool = true) -> void:
	_dragged = null
	_selected = null
	_hover = null
	_target = -1
	_clear_rope()
	if not displayed.is_empty(): _clear_preview()
	_layout_hand()
	if sound: _cue("sfx.card_pick")
	_update_gesture()

func _reject(card: Node2D = null) -> void:
	_cue("sfx.ui_deny")
	_dragged = null
	_selected = null
	_hover = null
	_clear_rope()
	_clear_preview()
	if card != null and is_instance_valid(card):
		if card.motion != null and card.motion.is_valid(): card.motion.kill()
		var motion: Tween = card.create_tween()
		var origin: Vector2 = card.position
		for step: int in range(6): motion.tween_property(card,"position",origin+Vector2(-3 if step%2==0 else 3,0),0.025)
		motion.tween_callback(func() -> void: _layout_hand(0.16))
	Juice.flash(end_button,Color("e8604c"),0.12)
	_update_gesture()

func _play_selected(target_index: int) -> void:
	if _selected == null: return
	var card: Node2D = _selected
	_selected = null
	_hover = null
	_dragged = null
	command_play(card.hand_index,target_index)

func command_play(hand_index: int, target_index: int = -1, choices: Dictionary = {}) -> void:
	if busy or _paused or not _focused or not can_process() or state.is_empty(): return
	var token: int = _lifecycle
	var action: Dictionary = _action_for(hand_index,target_index)
	if action.is_empty():
		_reject(_cards[hand_index] if hand_index>=0 and hand_index<_cards.size() else null)
		return
	var predicted: Dictionary = rules.preview(state,hand_index,target_index,choices)
	if not bool(predicted.get("valid",false)):
		_reject()
		return
	busy = true
	gesture.hide()
	end_button.disabled = true
	var instance: Dictionary = state["hand"][hand_index].duplicate(true)
	var card: Node2D = _card_by_uid(str(instance["uid"]))
	var events: Array = rules.play_card(state,hand_index,target_index,choices)
	_clear_preview()
	_clear_rope()
	if card != null:
		if card.motion != null and card.motion.is_valid(): card.motion.kill()
		var destination: Vector2 = ENEMY_HOME-Vector2(0,32) if str(card.definition.get("type",""))=="attack" else HERO_HOME-Vector2(0,40)
		Juice.fly(card,destination,0.12)
		await _wait(0.12)
		if not _alive(token): return
		_cards.erase(card)
		card.queue_free()
	await _present_events(events)
	if not _alive(token): return
	await _settle(events)

func request_end_turn() -> void:
	if busy or _paused or not _focused or not can_process() or state.is_empty(): return
	var token: int = _lifecycle
	if not bool(rules.tutorial_status(state).get("can_end_turn",false)):
		_reject()
		return
	_cancel_selection(false)
	busy = true
	end_button.disabled = true
	gesture.hide()
	var events: Array = rules.end_turn(state)
	await _present_events(events)
	if not _alive(token): return
	await _settle(events)

func _present_events(events: Array) -> void:
	var token: int = _lifecycle
	for event: Dictionary in events:
		if not _alive(token): return
		presented_events.append(event.duplicate(true))
		match str(event.get("type","")):
			"card_played":
				displayed["energy"] -= int(event.get("cost",0))
				var index: int = rules.find_card(displayed["hand"],event.get("uid",""))
				if index>=0: displayed["hand"].remove_at(index)
				var card_def: Dictionary = ContentCatalog.entry(str(event.get("id","")))
				if card_def.get("type","")=="attack":
					_pose_actor(hero,"attack")
					var move: Tween = hero.create_tween()
					move.tween_property(hero,"position",HERO_HOME+Vector2(12,0),0.08)
					await _wait(0.08)
				_sync_readouts()
			"damage":
				await _present_damage(event)
			"guard":
				await _present_guard(event)
			"enemy_action":
				_show_intent(event.get("intent",{}))
				Juice.pop(ui.get_node("Intent"),1.2,0.18)
				if event.get("intent",{}).get("type","")=="attack":
					_cue("sfx.enemy_wet_sock")
					_pose_actor(enemy,"attack")
					var windup: Tween = enemy.create_tween()
					windup.tween_property(enemy,"position",ENEMY_HOME+Vector2(8,0),0.1)
					windup.tween_property(enemy,"position",HERO_HOME+Vector2(45,0),0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					await _wait(0.26)
			"enemy_defeated":
				await _present_death()
			"turn_end":
				await _discard_hand()
				await _show_banner(_text("enemy_turn"),"sfx.end_turn")
			"turn_start":
				displayed["turn"] = int(event.get("turn",displayed["turn"]))
				displayed["energy"] = int(event.get("energy",3))
				displayed["player"]["guard"] = int(event.get("guard",0))
				_sync_readouts()
				await _show_banner(_text("player_turn"),"sfx.turn_start")
			"draw":
				displayed["hand"].append(event["card"].duplicate(true))
				_sync_hand(true)
				_cue("sfx.draw")
				await _wait(0.06)
			"tutorial_prompt":
				_show_prompt(event)
				if event.get("guide","")=="enemy": await _wait(0.75)
			"invalid_action":
				_reject()
	_sync_readouts()

func _present_damage(event: Dictionary) -> void:
	var player_hit: bool = event.get("target",null) is String and event["target"]=="player"
	var actor: Node2D = hero if player_hit else enemy
	var sprite: Sprite2D = actor.get_node("Portrait") as Sprite2D
	var values: Dictionary = displayed["player"] if player_hit else displayed["enemies"][int(event.get("target",0))]
	values["hp"] = int(values["hp"])-int(event.get("hp_damage",0))
	values["guard"] = int(values["guard"])-int(event.get("blocked",0))
	var damage: int = int(event.get("hp_damage",0))
	var blocked: int = int(event.get("blocked",0))
	if blocked>0:
		_pose_actor(actor,"guard")
		Juice.burst($Stage/Effects,actor.position-Vector2(0,36),"spark",14)
		_cue("sfx.guard_block")
		Juice.flash(sprite,Color("7cd0cc"),0.07)
		var readout: Control = hero_hp if player_hit else enemy_hp
		Juice.flash(readout.get_node("GuardIcon"),Color(1.8,1.8,1.8),0.09)
		if damage==0:
			Juice.number(ui,_text("blocked"),actor.position-Vector2(0,92),Color("c9e58a"))
		if int(values["guard"])<=0:
			await _wait(0.06)
			_cue("sfx.guard_break")
	if damage>0:
		_pose_actor(actor,"hurt")
		var big: bool = int(event.get("amount",damage))>=rules.limit("big_hit_threshold",12)
		Juice.flash(sprite,Color("e8604c") if player_hit else Color.WHITE,0.055)
		Juice.shake(stage,4.0 if big else 2.0,0.12)
		Juice.number(ui,"-%d" % damage,actor.position-Vector2(0,79),Color("e8604c"))
		Juice.burst($Stage/Effects,actor.position-Vector2(0,34),"spark",10)
		_cue("sfx.hurt" if player_hit else ("sfx.hit_big" if big else "sfx.hit_small"))
		if big:
			var zoom: Tween = stage.create_tween()
			zoom.tween_property(stage,"scale",Vector2.ONE*1.012,0.06)
			zoom.tween_property(stage,"scale",Vector2.ONE,0.18)
		Juice.hitstop(self,0.08 if big else 0.05)
		var knock: Tween = actor.create_tween()
		var home: Vector2 = HERO_HOME if player_hit else ENEMY_HOME
		knock.tween_property(actor,"position",home+Vector2(-3 if player_hit else 6,0),0.035)
		knock.tween_property(actor,"position",home,0.12)
	_sync_readouts()
	await _wait(0.18)
	if player_hit:
		var back: Tween = enemy.create_tween()
		back.tween_property(enemy,"position",ENEMY_HOME,0.18)
	else:
		var back: Tween = hero.create_tween()
		back.tween_property(hero,"position",HERO_HOME,0.12)
	await _wait(0.18)

func _present_guard(event: Dictionary) -> void:
	var is_player: bool = event.get("target",null) is String and event["target"]=="player"
	var actor: Node2D = hero if is_player else enemy
	var values: Dictionary = displayed["player"] if is_player else displayed["enemies"][int(event.get("target",0))]
	values["guard"] = int(values["guard"])+int(event.get("amount",0))
	var shield: Node2D = actor.get_node("Shield") as Node2D
	shield.active = true
	_pose_actor(actor,"guard")
	Juice.pop(shield,1.1,0.3)
	Juice.number(ui,"+%d" % int(event.get("amount",0)),actor.position-Vector2(0,74),Color("7cd0cc"))
	_cue("sfx.guard_gain")
	_sync_readouts()
	await _wait(0.3)

func _present_death() -> void:
	Juice.flash($Stage/Enemy/Portrait,Color.WHITE,0.06)
	await _wait(0.11)
	Juice.flash($Stage/Enemy/Portrait,Color.WHITE,0.06)
	await _wait(0.1)
	var flatten: Tween = enemy.create_tween()
	flatten.tween_property(enemy,"scale",Vector2(1.35,0.2),0.13)
	await _wait(0.13)
	_cue("sfx.enemy_poof")
	Juice.burst($Stage/Effects,ENEMY_HOME-Vector2(0,12),"dust",20)
	Juice.burst($Stage/Effects,ENEMY_HOME-Vector2(0,20),"shine",5)
	enemy.hide()
	ui.get_node("Intent").hide()
	enemy_hp.hide()
	await _wait(0.4)

func _discard_hand() -> void:
	for card: Node2D in _cards:
		if card.motion != null and card.motion.is_valid(): card.motion.kill()
		Juice.fly(card,Vector2(690,345),0.22)
		_cue("sfx.discard")
		await _wait(0.06)
	await _wait(0.2)
	for card: Node2D in _cards: card.queue_free()
	_cards.clear()
	displayed["hand"] = []

func _show_banner(text: String, cue: String) -> void:
	var banner: Control = ui.get_node("Banner") as Control
	banner.get_node("Text").text = text
	banner.position = Vector2(-252,95)
	banner.show()
	_cue(cue)
	var tween: Tween = banner.create_tween()
	tween.tween_property(banner,"position:x",200.0,0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.4)
	tween.tween_property(banner,"position:x",656.0,0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait(0.85)
	banner.hide()

func _show_prompt(prompt: Dictionary) -> void:
	var id: String = str(prompt.get("prompt_id",""))
	if id!=_last_prompt and not str(prompt.get("text","")).is_empty():
		_last_prompt = id
		bubble.say(str(prompt.get("text","")),str(prompt.get("speaker","npc.maye")),0)
	_update_gesture()

func _update_gesture() -> void:
	if not is_node_ready() or busy or _paused or _dragged!=null:
		if is_instance_valid(gesture): gesture.hide()
		return
	var guide: String = str(_status.get("guide","none"))
	if guide=="end_turn":
		gesture.guide(Vector2(590,282),Vector2(590,282),true)
		return
	if guide=="drag_enemy" or guide=="drag_board":
		var card: Node2D = _card_by_uid(str(_status.get("allowed_card_uid","")))
		if card==null:
			for candidate: Node2D in _cards:
				if candidate.enabled:
					card = candidate
					break
		if card!=null:
			gesture.guide(card.home-Vector2(4,43),ENEMY_HOME-Vector2(0,34) if guide=="drag_enemy" else HERO_HOME-Vector2(0,32))
			return
	gesture.hide()

func _settle(events: Array) -> void:
	var token: int = _lifecycle
	displayed = state.duplicate(true)
	_sync_hand()
	await _wait(0.16)
	if not _alive(token): return
	busy = false
	_refresh_authority()
	_sync_readouts()
	_show_prompt(_status)
	command_finished.emit(events.duplicate(true))
	if state.get("status","")=="player":
		checkpoint.emit(state.duplicate(true))
	elif not _completion_emitted:
		_completion_emitted = true
		busy = true
		gesture.hide()
		end_button.disabled = true
		await _wait(0.65)
		if not _alive(token): return
		busy = false
		tutorial_completed.emit({"state":state.duplicate(true),"won":state.get("status","")=="victory"})

func _handle_key(event: InputEventKey) -> void:
	if event.keycode==KEY_ESCAPE:
		if _selected!=null or _dragged!=null: _cancel_selection()
		else: toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _paused or busy: return
	if event.keycode>=KEY_1 and event.keycode<=KEY_8:
		var index: int = int(event.keycode-KEY_1)
		if index<_cards.size():
			if not _cards[index].enabled: _reject(_cards[index])
			else:
				_selected = _cards[index]
				_hover = null
				_target = 0 if str(_selected.definition.get("target","self"))=="enemy" else -1
				_layout_hand()
				_update_target_preview(_selected,_target)
				_cue("sfx.card_pick")
	elif event.keycode==KEY_LEFT or event.keycode==KEY_RIGHT:
		if _selected!=null:
			_target = 0 if str(_selected.definition.get("target","self"))=="enemy" else -1
			_update_target_preview(_selected,_target)
	elif event.keycode==KEY_ENTER or event.keycode==KEY_KP_ENTER:
		if _selected!=null: _play_selected(_target)
	elif event.keycode==KEY_E:
		request_end_turn()
	elif event.keycode==KEY_SPACE:
		if bubble.visible: bubble.advance()
	get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	if not _focused: return
	_paused = not _paused
	_cancel_selection(false)
	ui.get_node("PauseOverlay").visible = _paused
	ui.get_node("PauseOverlay/Retry").disabled = busy
	ui.get_node("PauseOverlay/Exit").disabled = busy
	_apply_suspend()
	gesture.visible = gesture.visible and not _paused
	if not _paused: _update_gesture()
	_cue("sfx.ui_click")

func _apply_suspend() -> void:
	var suspended: bool = _paused or not _focused
	stage.process_mode = Node.PROCESS_MODE_DISABLED if suspended else Node.PROCESS_MODE_INHERIT
	ui.process_mode = Node.PROCESS_MODE_DISABLED if suspended else Node.PROCESS_MODE_INHERIT
	ui.get_node("PauseOverlay").process_mode = Node.PROCESS_MODE_ALWAYS

func _notification(what: int) -> void:
	if not is_node_ready(): return
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_cancel_selection(false)
		_apply_suspend()
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		_apply_suspend()
		_update_gesture()

func restart_tutorial() -> void:
	if busy: return
	if config.get("restart_state", {}) is Dictionary and not config.get("restart_state", {}).is_empty():
		config["resume_state"] = config["restart_state"].duplicate(true)
	else:
		config.erase("resume_state")
	start_tutorial(config)

func _exit_to_title() -> void:
	if busy: return
	checkpoint.emit(state.duplicate(true))
	exit_requested.emit()

func _process(delta: float) -> void:
	if not assets_ready or _paused or not _focused: return
	_elapsed += delta
	_tick_actor(hero,delta)
	_tick_actor(enemy,delta)
	if bubble.visible and _maye_frames.size()>1 and int(_elapsed*6)%2==1: $Stage/MaYe.texture = _maye_frames[1]
	else: $Stage/MaYe.texture = _maye_frames[0]
	if not busy:
		var should_glow: bool = bool(_status.get("can_end_turn",false)) and (int(state.get("energy",0))==0 or _cards.is_empty())
		end_button.modulate = Color(1,1,1,0.83+0.17*sin(_elapsed*TAU/0.8)) if should_glow else Color.WHITE
	if _dragged!=null and _drag_moved and int(_elapsed*30)%3==0:
		_trail(_dragged)

func _trail(card: Node2D) -> void:
	if _trails.size()>3:
		var first: Sprite2D = _trails.pop_front()
		if is_instance_valid(first): first.queue_free()
	var trail: Sprite2D = Sprite2D.new()
	trail.texture = card.get_node("Art").texture
	trail.position = card.position-Vector2(0,56)
	trail.scale = Vector2.ONE*1.3
	trail.rotation = card.rotation
	trail.modulate = Color(1,0.88,0.6,0.15)
	hand.add_child(trail)
	_trails.append(trail)
	var tween: Tween = trail.create_tween()
	tween.tween_property(trail,"modulate:a",0.0,0.12)

func _cue(id: String) -> void:
	if AudioService.has_cue(id): AudioService.play(id)

func _wait(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed<seconds:
		await get_tree().process_frame
		if not is_inside_tree() or is_queued_for_deletion(): return
		if _paused or not _focused or not can_process(): continue
		if instant_presentation: return
		elapsed += get_process_delta_time()

func _alive(token: int) -> bool:
	return token==_lifecycle and is_inside_tree() and not is_queued_for_deletion()

func presentation_snapshot() -> Dictionary:
	return {"state":state.duplicate(true),"displayed":displayed.duplicate(true),"busy":busy,"paused":_paused,"cards":_cards.size(),"assets_ready":assets_ready,"guide":_status.get("guide","none"),"end_enabled":not end_button.disabled,"preview":_preview.duplicate(true),"presented_events":presented_events.duplicate(true)}

func _exit_tree() -> void:
	_lifecycle += 1
	Engine.time_scale = 1.0
	if AudioService.has_method("set_ambience"): AudioService.set_ambience("")
