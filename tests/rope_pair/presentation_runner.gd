extends SceneTree
var passed: int = 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	if value: passed += 1
	else: failures.append(message)
func ready_to_pair() -> Node:
	var stage: Node = load("res://scenes/remedy/BattleScene.tscn").instantiate()
	stage.config = {"seed":147,"tutorial_id":"tutorial.pair","instant_presentation":true}
	root.add_child(stage)
	await process_frame
	await process_frame
	stage.command_play(0,0,{"second_target":1})
	stage.command_play(0,0)
	stage.instant_presentation = false
	return stage
func _run() -> void:
	for suspended: String in ["pause", "focus"]:
		var stage: Node = await ready_to_pair()
		var completed: Array[int] = [0]
		stage.tutorial_completed.connect(func(_result: Dictionary) -> void: completed[0] += 1)
		stage.command_play(0,1)
		var duration: float = stage._view.presentation_duration + 0.15
		if suspended == "pause": stage.toggle_pause()
		else: stage._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await create_timer(duration).timeout
		check(completed[0] == 0 and stage.busy, suspended + " blocks terminal transition while presentation is suspended")
		if suspended == "pause": stage.toggle_pause()
		else: stage._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		await create_timer(duration).timeout
		check(completed[0] == 1 and not stage.busy, suspended + " resumes and completes exactly once")
		stage.free()
	var restarted: Node = await ready_to_pair()
	var stale: Array[int] = [0]
	restarted.tutorial_completed.connect(func(_result: Dictionary) -> void: stale[0] += 1)
	restarted.command_play(0,1)
	var restart_wait: float = restarted._view.presentation_duration + 0.15
	restarted.start_tutorial({"seed":147,"tutorial_id":"tutorial.pair","instant_presentation":true})
	await create_timer(restart_wait).timeout
	check(stale[0] == 0 and restarted.state["status"] == "player" and not restarted.busy, "restart invalidates the old asynchronous terminal callback")
	restarted.free()
	var leaving: Node = await ready_to_pair()
	var exited: Array[int] = [0]
	leaving.tutorial_completed.connect(func(_result: Dictionary) -> void: exited[0] += 1)
	leaving.command_play(0,1)
	var exit_wait: float = leaving._view.presentation_duration + 0.15
	leaving.queue_free()
	await create_timer(exit_wait).timeout
	check(exited[0] == 0, "leaving the scene cancels terminal callbacks")
	print("ROPE_PRESENTATION_RESULT: " + JSON.stringify({"passed":passed,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
