extends SceneTree
## Current rope-and-pair gate. Historical shield suites remain reference only.
const RulesSuite = preload("res://tests/rope_pair/rules_suite.gd")
const ContentSuite = preload("res://tests/rope_pair/content_suite.gd")
const PolicySuite = preload("res://tests/rope_pair/policy_suite.gd")
const ReviewSuite = preload("res://tests/rope_pair/review_suite.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var suites: Dictionary = {"rules": RulesSuite.new().run(), "content_migration_expedition": ContentSuite.new().run(root.get_node("ContentCatalog")), "policy_regression": PolicySuite.new().run(root.get_node("ContentCatalog")), "review_regression": ReviewSuite.new().run(root.get_node("ContentCatalog"))}
	var passed: int = 0
	var failed: int = 0
	for result: Dictionary in suites.values():
		passed += int(result["passed"])
		failed += int(result["failed"])
	print("RULES_TEST_RESULT: " + JSON.stringify({"passed": passed, "failed": failed, "suites": suites}))
	quit(0 if failed == 0 and passed > 0 else 1)
