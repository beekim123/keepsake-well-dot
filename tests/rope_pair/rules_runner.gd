extends SceneTree
const Suite = preload("res://tests/rope_pair/rules_suite.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var result: Dictionary = Suite.new().run()
	print("ROPE_PAIR_RESULT: " + JSON.stringify(result))
	quit(0 if result["failed"] == 0 else 1)
