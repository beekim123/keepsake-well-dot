extends SceneTree
const Simulation = preload("res://tests/expedition/simulation.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var count: int = 300
	var output: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--count="): count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	var result: Dictionary = Simulation.new().run(root.get_node("ContentCatalog").definitions(), count)
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t") + "\n")
		file.close()
	print("ROPE_SIM_RESULT: " + JSON.stringify(result))
	quit(0 if result.get("completed", false) and result.get("errors", ["missing"]).is_empty() else 1)
