extends SceneTree
## Adapter only: the same seven-node simulator is shared with standalone expedition QA.
const Simulation = preload("res://tests/expedition/simulation.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var catalog: Node = root.get_node("ContentCatalog")
	if not catalog.valid:
		printerr("ERROR: simulation requires valid synchronized ContentCatalog definitions")
		quit(1)
		return
	var count: int = 300
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--quick":
			count = 50
		elif arg.begins_with("--count=") and arg.trim_prefix("--count=").is_valid_int() and int(arg.trim_prefix("--count=")) > 0:
			count = int(arg.trim_prefix("--count="))
		else:
			printerr("ERROR: unknown or invalid simulation argument: " + arg)
			quit(1)
			return
	var result: Dictionary = Simulation.new().run(catalog.definitions(), count)
	result["format"] = "d1-simulation/1"
	print("D1_SIM_RESULT: " + JSON.stringify(result))
	quit(0 if result.get("completed", false) and result.get("errors", ["missing"]).is_empty() and int(result.get("trips", 0)) == count else 1)
