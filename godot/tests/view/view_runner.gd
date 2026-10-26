extends SceneTree
const Suite = preload("res://tests/view/view_suite.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	var result: Dictionary = await Suite.new().run_suite(self)
	root.get_node("AudioService").stop_all()
	await create_timer(0.15).timeout
	print("D1_VIEW_RESULT: " + JSON.stringify(result))
	quit(0 if result["failed"] == 0 else 1)
