extends Node2D
## Tutorial lifecycle around the same battle projection used by the expedition.
## The rules own locks, legal choices, forecasts, and all battle state.
signal checkpoint(state: Dictionary)
signal tutorial_completed(result: Dictionary)
signal exit_requested
signal command_finished(events: Array)
const Rules = preload("res://scripts/core/battle_rules.gd")
const BattleView = preload("res://scripts/view/battle_view.gd")
const SimpleUI = preload("res://scripts/view/remedy/simple_ui.gd")
const UI = preload("res://scripts/view/ui_factory.gd")
var config: Dictionary = {}
var rules: RefCounted
var state: Dictionary = {}
var displayed: Dictionary = {}
var busy: bool = true
var assets_ready: bool = false
var instant_presentation: bool = false
var presented_events: Array = []
var _view: Control
var _status: Dictionary = {}
var _paused: bool = false
var _focused: bool = true
var _completion_emitted: bool = false
var _lifecycle: int = 0
var _pause_panel: Panel
var _last_prompt: String = ""
@onready var ui: Control = $Interface/UI
@onready var bubble: Control = $Interface/UI/Dialogue
@onready var gesture: Node2D = $Interface/UI/Gesture

func _ready() -> void:
	ui.theme = SimpleUI.theme()
	_begin_configured.call_deferred()

func _begin_configured() -> void:
	if is_inside_tree(): start_tutorial(config)

func start_tutorial(options: Dictionary = {}) -> void:
	_lifecycle += 1
	config = options.duplicate(true)
	instant_presentation = bool(config.get("instant_presentation", false))
	_completion_emitted = false
	busy = true
	_paused = false
	if is_instance_valid(_pause_panel): _pause_panel.queue_free()
	_last_prompt = ""
	presented_events.clear()
	rules = Rules.new(ContentCatalog.definitions())
	var resume: Variant = config.get("resume_state", {})
	if resume is Dictionary and not resume.is_empty() and rules.is_tutorial_state_valid(resume): state = resume.duplicate(true)
	else: state = rules.start_tutorial({}, int(config.get("seed", 147)), str(config.get("tutorial_id", "tutorial.wet_sock"))).get("state", {})
	if state.is_empty(): return
	assets_ready = true
	displayed = state.duplicate(true)
	busy = false
	_rebuild([])
	checkpoint.emit(state.duplicate(true))

func _rebuild(events: Array) -> void:
	if is_instance_valid(_view):
		ui.remove_child(_view)
		_view.queue_free()
	_view = BattleView.new()
	_view.name = "BattleView"
	_view.size = Vector2(640,360)
	_view.configure(rules, state, _command, _show_pile, toggle_pause)
	_view.instant_presentation = instant_presentation
	_view.first_run_presentation = true
	_view.station_label = ContentCatalog.text("ui.rope.station_pair" if state.get("tutorial", {}).get("id") == "tutorial.pair" else "ui.rope.station_bind")
	_view.on_selection = _update_gesture
	ui.add_child(_view)
	ui.move_child(_view, 0)
	_view.present_events(events)
	_status = rules.tutorial_status(state)
	_show_prompt(_status)
	_apply_suspend()

func _command(action: Dictionary) -> void:
	if busy or _paused or not _focused or state.is_empty() or not rules.legal_actions(state).has(action): return
	var token: int = _lifecycle
	busy = true
	gesture.hide()
	var events: Array = rules.apply_action(state, action)
	presented_events.append_array(events.duplicate(true))
	displayed = state.duplicate(true)
	_rebuild(events)
	_view.commands_enabled = false
	if not instant_presentation and _view.presentation_duration > 0:
		await _wait_presentation(_view.presentation_duration, token)
	if token != _lifecycle or not is_inside_tree(): return
	busy = false
	_view.commands_enabled = true
	_apply_suspend()
	_status = rules.tutorial_status(state)
	_show_prompt(_status)
	command_finished.emit(events.duplicate(true))
	if state.get("status") == "player": checkpoint.emit(state.duplicate(true))
	elif not _completion_emitted:
		_completion_emitted = true
		gesture.hide()
		tutorial_completed.emit({"state": state.duplicate(true), "won": state.get("status") == "victory"})

func _wait_presentation(seconds: float, token: int) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds and token == _lifecycle and is_inside_tree():
		await get_tree().process_frame
		if token != _lifecycle or not is_inside_tree(): return
		# Only time in which the shared view can present counts toward completion.
		if not _paused and _focused: elapsed += get_process_delta_time()

func command_play(hand_index: int, target_index: int = -1, choices: Dictionary = {}) -> void:
	_command({"type": "play_card", "hand_index": hand_index, "target_index": target_index, "choices": choices})

func request_end_turn() -> void:
	_command({"type": "end_turn", "keep_index": -1})

func _show_prompt(prompt: Dictionary) -> void:
	var id: String = str(prompt.get("prompt_id", ""))
	if id != _last_prompt and not str(prompt.get("text", "")).is_empty():
		_last_prompt = id
		bubble.say(str(prompt["text"]), str(prompt.get("speaker", "npc.maye")))
		if instant_presentation: bubble.reveal()
	_update_gesture()

func _update_gesture() -> void:
	if not is_node_ready() or not is_instance_valid(_view) or busy or _paused or not _focused:
		if is_instance_valid(gesture): gesture.hide()
		return
	if _view.first_target >= 0:
		for slot: int in rules.living_slots(state):
			if slot != _view.first_target:
				gesture.guide(_view._enemy_centers[_view.first_target], _view._enemy_centers[slot])
				return
	var guide: String = str(_status.get("guide", "none"))
	if guide == "end_turn":
		gesture.guide(Vector2(185,244),Vector2(185,244),true)
		return
	if guide in ["drag_enemy", "drag_board", "pair_hits"]:
		var index: int = -1
		for slot: int in range(state.get("hand", []).size()):
			if state["hand"][slot]["uid"] == _status.get("allowed_card_uid"): index = slot
		if index < 0:
			for action: Dictionary in rules.legal_actions(state):
				if action["type"] == "play_card": index = int(action["hand_index"]); break
		if index >= 0 and index < _view._hand_buttons.size():
			var target_slot: int = _view._first_target()
			if guide == "pair_hits":
				for slot: int in rules.living_slots(state):
					if target_slot < 0 or int(state["enemies"][slot]["hp"]) > int(state["enemies"][target_slot]["hp"]): target_slot = slot
			var destination: Vector2 = _view._enemy_centers.get(target_slot, Vector2(476,208)) if guide in ["drag_enemy", "pair_hits"] else Vector2(130,208)
			gesture.guide(_view._hand_buttons[index].position + Vector2(28,12), destination)
			return
	gesture.hide()

func _show_pile(kind: String) -> void:
	var names: Array[String] = []
	for instance: Dictionary in state.get(kind, []): names.append(str(ContentCatalog.entry(str(instance["id"])).get("name", "")))
	_view._show_rules(" · ".join(names))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not _focused: return
	if _paused:
		if event.keycode == KEY_ESCAPE: toggle_pause()
	elif not busy and is_instance_valid(_view):
		if event.keycode == KEY_SPACE and bubble.visible: bubble.advance()
		else: _view.handle_key(event)
	get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	if not _focused: return
	_paused = not _paused
	_view.cancel_selection()
	if is_instance_valid(_pause_panel): _pause_panel.queue_free()
	if _paused:
		_pause_panel = UI.frame(ui,"PauseOverlay",Rect2(185,82,270,200))
		_pause_panel.z_index = 10
		UI.button(_pause_panel, ContentCatalog.text("ui.r2.resume"), Rect2(30,26,210,34), toggle_pause)
		var retry: Button = UI.button(_pause_panel, ContentCatalog.text("ui.r2.retry"), Rect2(30,74,210,34), restart_tutorial)
		var leave: Button = UI.button(_pause_panel, ContentCatalog.text("ui.r2.return_title"), Rect2(30,122,210,34), _exit_to_title)
		retry.disabled = busy
		leave.disabled = busy
	_apply_suspend()
	_update_gesture()

func _apply_suspend() -> void:
	if is_instance_valid(_view): _view.process_mode = Node.PROCESS_MODE_DISABLED if _paused or not _focused else Node.PROCESS_MODE_INHERIT
	if is_instance_valid(bubble): bubble.process_mode = Node.PROCESS_MODE_DISABLED if _paused or not _focused else Node.PROCESS_MODE_INHERIT
	if is_instance_valid(gesture) and (_paused or not _focused): gesture.hide()

func _notification(what: int) -> void:
	if not is_node_ready(): return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		if is_instance_valid(_view): _view.cancel_selection()
		_apply_suspend()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		_apply_suspend()
		_update_gesture()

func restart_tutorial() -> void:
	if busy: return
	if is_instance_valid(_pause_panel): _pause_panel.queue_free()
	if config.get("restart_state", {}) is Dictionary and not config.get("restart_state", {}).is_empty(): config["resume_state"] = config["restart_state"].duplicate(true)
	else: config.erase("resume_state")
	start_tutorial(config)

func _exit_to_title() -> void:
	if busy: return
	checkpoint.emit(state.duplicate(true))
	exit_requested.emit()

func presentation_snapshot() -> Dictionary:
	return {"state": state.duplicate(true), "displayed": displayed.duplicate(true), "busy": busy, "paused": _paused, "cards": state.get("hand", []).size(), "assets_ready": assets_ready, "guide": _status.get("guide", "none"), "presented_events": presented_events.duplicate(true)}

func _exit_tree() -> void:
	_lifecycle += 1
