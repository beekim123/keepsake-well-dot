extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var app: Control = load("res://scenes/main.tscn").instantiate()
	# Set the isolated path before add_child invokes main._ready and reads a save.
	# The QA entry remains safe even when launched without command-line flags.
	app._save_path = "user://d2-debug.json"
	app._debug_seed = 147
	root.add_child(app)
	await process_frame
	await process_frame
	var helper: RefCounted = load("res://scripts/debug/rope_pair_qa.gd").new()
	var directory: String = ""
	var result_file: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): directory = arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--result="): result_file = arg.trim_prefix("--result=")
	var result: Dictionary = await helper.run(app, directory)
	if result.get("ok", false) and OS.get_cmdline_user_args().has("--specials"):
		result["specials"] = await helper.special_scenarios()
		result["ok"] = result["ok"] and result["specials"].get("ok", false)
	if not result_file.is_empty():
		var file: FileAccess = FileAccess.open(result_file, FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"  "))
	var summary: Dictionary = result.duplicate()
	summary.erase("events")
	if summary.has("specials"):
		summary["specials"] = summary["specials"].duplicate()
		summary["specials"].erase("records")
	print("ROPE_FLOW_RESULT: " + JSON.stringify(summary))
	if DisplayServer.get_name() != "headless" and (OS.get_cmdline_user_args().has("--hold") or OS.get_cmdline_user_args().has("--hold-boss")):
		helper._prepare_scenario("boss" if OS.get_cmdline_user_args().has("--hold-boss") else "normal")
		await process_frame
		print("ROPE_WINDOW_READY: 1920x1080 visible Godot window; holding 180 seconds for native inspection")
		await create_timer(180.0).timeout
	quit(0 if result.get("ok", false) else 1)
