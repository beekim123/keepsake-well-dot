extends SceneTree
var failures: Array[String] = []
var passed: int = 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	if value: passed += 1
	else: failures.append(message)
func _run() -> void:
	var stage: Node = load("res://scenes/remedy/BattleScene.tscn").instantiate()
	stage.config = {"seed": 147, "tutorial_id": "tutorial.wet_sock", "instant_presentation": true}
	root.add_child(stage)
	await process_frame
	await process_frame
	stage.command_play(0,0)
	stage.request_end_turn()
	check(stage.state["turn"] == 2 and stage.state["hand"].size() == 2, "turn two teaches with two bind cards")
	stage.command_play(0,0)
	var first: Dictionary = stage.rules.forecast(stage.state)
	check(first["damage"] == 1 and stage.state["enemies"][0]["binds"] == 4, "first bind visibly changes five damage to one")
	stage.request_end_turn()
	check(stage.state["turn"] == 2, "tutorial prevents ending before second bind")
	if stage.state["turn"] == 2:
		stage.command_play(0,0)
		check(stage.state["enemies"][0]["binds"] == 8, "second bind stacks surplus rope")
		stage.request_end_turn()
		check(stage.state["turn"] == 3 and stage.state["enemies"][0]["binds"] == 3, "third turn shows the three retained circles")
		check(stage._view.state["enemies"][0]["binds"] == 3, "shared projection exposes retained circles")
		stage.command_play(0,0)
		stage.request_end_turn()
		check(stage.state["enemies"][0]["binds"] == 0 and stage.presented_events.any(func(event: Dictionary) -> bool: return event.get("type") == "enemy_shake_off"), "the next enemy action visibly shakes off the retained rope")
	else:
		check(false, "third turn retained-rope sequence cannot proceed")
	stage.free()
	print("ROPE_TUTORIAL_RESULT: " + JSON.stringify({"passed": passed, "failed": failures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
