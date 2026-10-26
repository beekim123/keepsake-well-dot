extends SceneTree
const Suite = preload("res://tests/rope_pair/policy_suite.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var result: Dictionary = Suite.new().run(root.get_node("ContentCatalog"))
	print("ROPE_POLICY_RESULT: " + JSON.stringify(result))
	quit(0 if result["failed"] == 0 else 1)
