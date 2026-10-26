extends SceneTree
const Suite = preload("res://tests/rope_pair/review_suite.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var result: Dictionary = Suite.new().run(root.get_node("ContentCatalog"))
	print("ROPE_REVIEW_RESULT: " + JSON.stringify(result))
	quit(0 if result["failed"] == 0 else 1)
