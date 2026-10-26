extends SceneTree
## Standalone wrapper; aggregates inject synchronized catalog definitions instead.
const Fixtures = preload("res://tests/expedition/fixtures.gd")
const Suite = preload("res://tests/expedition/test_suite.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var result: Dictionary = Suite.new().run(Fixtures.definitions())
	print("EXPEDITION_TEST_RESULT: " + JSON.stringify(result))
	quit(0 if int(result["failed"]) == 0 else 1)
