extends SceneTree
## Historical b1eb91e battle/expedition suites adapted to the standalone root.
## Old D1 audio/view assumptions are outside this rules baseline.
const BattleSuite = preload("res://tests/battle/battle_suite.gd")
const ExpeditionSuite = preload("res://tests/expedition/test_suite.gd")
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	await process_frame
	var definitions: Dictionary = root.get_node("ContentCatalog").definitions()
	var suites: Dictionary = {"battle": BattleSuite.new().run(definitions), "expedition": ExpeditionSuite.new().run(definitions)}
	var passed: int = 0
	var failed: int = 0
	for result: Dictionary in suites.values():
		passed += int(result.get("passed", 0))
		failed += int(result.get("failed", 1))
	print("RULES_TEST_RESULT: " + JSON.stringify({"passed": passed, "failed": failed, "suites": suites}))
	quit(0 if failed == 0 and passed > 0 else 1)
