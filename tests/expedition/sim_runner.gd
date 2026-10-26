extends SceneTree
## Standalone wrapper; the simulator is injectable and contains no file reads.
const Fixtures = preload("res://tests/expedition/fixtures.gd")
const Simulation = preload("res://tests/expedition/simulation.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var count: int = 300
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--quick": count = 50
		if arg.begins_with("--count="): count = maxi(1, int(arg.trim_prefix("--count=")))
	var result: Dictionary = Simulation.new().run(Fixtures.definitions(), count)
	print(JSON.stringify(result))
	quit(0 if result["completed"] else 1)
