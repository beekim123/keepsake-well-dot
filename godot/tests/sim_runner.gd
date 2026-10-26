extends SceneTree
## D0 deliberately does not fabricate a battle bot, win rate, or expedition duration.

const Rules = preload("res://scripts/core/damage_rules.gd")

func _initialize() -> void:
	var cases: Array[Dictionary] = [
		{"hp": 12, "guard": 4, "damage": 6, "expected_hp": 10, "expected_guard": 0},
		{"hp": 12, "guard": 8, "damage": 6, "expected_hp": 12, "expected_guard": 2},
		{"hp": 3, "guard": 0, "damage": 99, "expected_hp": 0, "expected_guard": 0},
		{"hp": 12, "guard": 4, "damage": 0, "expected_hp": 12, "expected_guard": 4}
	]
	var passed: int = 0
	for scenario: Dictionary in cases:
		var result: Dictionary = Rules.apply_damage({"hp": scenario["hp"], "guard": scenario["guard"]}, scenario["damage"])
		if result["state"]["hp"] == scenario["expected_hp"] and result["state"]["guard"] == scenario["expected_guard"]:
			passed += 1
	print(JSON.stringify({"stage": "foundation-smoke", "cases": cases.size(), "passed": passed, "full_simulation_implemented": false, "note": "Full expedition simulation, win rates, and duration measurements begin in D1; no balance claim is made."}))
	quit(0 if passed == cases.size() else 1)
