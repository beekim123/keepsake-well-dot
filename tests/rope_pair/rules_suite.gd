extends RefCounted
const Rules = preload("res://scripts/core/battle_rules.gd")
var passed: int = 0
var failures: Array = []
var rules: RefCounted
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else: failures.append(label)
func fixture(count: int = 2) -> Dictionary:
	var enemies: Array = []
	for i: int in range(count): enemies.append("enemy.test")
	return rules.start({"enemies": enemies}, {"deck": ["card.hit", "card.bind", "card.tie", "card.hit", "card.bind", "card.tie", "card.hit", "card.bind", "card.tie", "card.hit"]}, 42)["state"]
func play(state: Dictionary, id: String, target: int = 0, choices: Dictionary = {}) -> Array:
	state["hand"] = [rules.new_card(state, id)]
	state["energy"] = 10
	return rules.play_card(state, 0, target, choices)
func run() -> Dictionary:
	rules = Rules.new({"balance": [{"id": "balance.default", "hand_size": 5, "hand_limit": 7}], "enemies": [{"id": "enemy.test", "hp": 20, "pair_tag": "sock", "intents": [{"type": "attack", "amount": 3, "times": 2}]}], "cards": [{"id": "card.hit", "cost": 1, "type": "attack", "target": "enemy", "ops": [{"op": "damage", "amount": 5}]}, {"id": "card.bind", "cost": 1, "type": "rope", "target": "enemy", "ops": [{"op": "bind", "amount": 4}]}, {"id": "card.tie", "cost": 1, "type": "rope", "target": "two_enemies", "ops": [{"op": "tie"}], "fallback_ops": [{"op": "bind", "amount": 2}]}]})
	var s: Dictionary = fixture()
	check(s["hand"].size() == 5, "refill starts at five")
	check(s["enemies"][0].has("binds"), "enemy bind schema")
	var retained: Array = s["hand"].duplicate(true)
	rules.end_turn(s)
	check(s["hand"] == retained, "end turn retains hand")
	s = fixture(1)
	play(s, "card.bind")
	check(s["enemies"][0].get("binds", 0) == 4, "apply four binds")
	check(rules.forecast(s)["damage"] == 2, "multi hit forecast consumes binds per hit")
	var snapshot: Dictionary = s.duplicate(true)
	rules.forecast(s)
	check(s == snapshot, "forecast pure")
	rules.end_turn(s)
	check(s["player"]["hp"] == 38, "four binds block three then one")
	check(s["enemies"][0].get("binds", -1) == 0, "only used binds consumed")
	s = fixture(1)
	play(s, "card.tie")
	check(s["enemies"][0].get("binds", 0) == 2, "single enemy tie fallback")
	s = fixture()
	var invalid: Array = play(s, "card.tie", 0, {"second_target": 0})
	check(invalid[0].get("reason", "") == "invalid_second_target", "same target rejected")
	play(s, "card.tie", 0, {"second_target": 1})
	check(s["enemies"][0].get("tie", "") == s["enemies"][1]["uid"], "tie stores stable partner uid")
	play(s, "card.hit")
	check(s["enemies"][0]["hp"] == 15 and s["enemies"][1]["hp"] == 18, "link half loss no recursion")
	s["enemies"][0]["hp"] = 11
	s["enemies"][1]["hp"] = 10
	play(s, "card.hit")
	check(s["battle_flags"].get("pairs", 0) == 1, "pair resolves after card")
	check(s["status"] == "victory", "pair immediate victory")
	check(s["enemies"][0].get("departed", "") == "paired", "pair departure distinct from death")
	s = fixture(3)
	play(s, "card.tie", 0, {"second_target": 1})
	play(s, "card.tie", 0, {"second_target": 2})
	check(s["enemies"][1].get("tie", "") == "", "retie clears previous partner")
	s = fixture()
	play(s, "card.tie", 0, {"second_target": 1})
	s["enemies"][0]["hp"] = 10
	s["enemies"][1]["hp"] = 10
	rules.end_turn(s)
	check(s["status"] == "victory", "pair check at enemy phase end")
	check(rules.has_method("shake_card"), "shake action exists")
	if rules.has_method("shake_card"):
		s = fixture()
		var uid: String = s["hand"][0]["uid"]
		rules.shake_card(s, 0)
		check(s["hand"].size() == 5 and rules.find_card(s["hand"], uid) < 0, "shake exchanges a card")
		check(rules.shake_card(s, 0)[0].get("type") == "invalid_action", "shake once each turn")
	check(fixture() == fixture(), "same seed reproducible")
	more_rules()
	hook_cycle_test()
	return {"passed": passed, "failed": failures.size(), "failures": failures}

func ops(s: Dictionary, operations: Array, first: int = 0, second: int = 1) -> Array:
	var events: Array = []
	rules.apply_ops(s, operations, {"source": "card.test", "target": first, "choices": {"second_target": second}, "is_attack_card": true}, events)
	return events

func more_rules() -> void:
	var s: Dictionary = fixture()
	ops(s, [{"op": "bind", "amount": 40}])
	check(s["enemies"][0]["binds"] == 12, "bind capped twelve")
	rules.end_turn(s)
	check(s["enemies"][0]["binds"] == 6, "unused binds retained across turn")
	s = fixture(1)
	s["enemies"][0]["intent_override"] = {"type": "guard", "amount": 4}
	ops(s, [{"op": "bind", "amount": 5}])
	rules.end_turn(s)
	check(s["enemies"][0]["binds"] == 5, "nonattacker retains all binds")
	s["enemies"][0]["intent_override"] = {"type": "guard", "amount": 4, "shake_off": "half"}
	rules.end_turn(s)
	check(s["enemies"][0]["binds"] == 3, "half shake rounds removed rings down")
	s["enemies"][0]["intent_override"] = {"type": "guard", "amount": 4, "shake_off": "all"}
	rules.end_turn(s)
	check(s["enemies"][0]["binds"] == 0, "full shake clears all binds")
	s = fixture(1)
	ops(s, [{"op": "bind", "amount": 4}])
	s["enemies"][0]["intent_override"] = {"type": "attack", "amount": 8, "ignore_binds": 2}
	check(rules.forecast(s)["damage"] == 6, "ignore binds forecast")
	rules.end_turn(s)
	check(s["player"]["hp"] == 34 and s["enemies"][0]["binds"] == 2, "ignore binds consumes only available rings")
	s = fixture(1)
	ops(s, [{"op": "bind", "amount": 5}])
	s["enemies"][0]["intent_override"] = {"type": "guard", "amount": 6, "eat_binds_to_guard": true}
	rules.end_turn(s)
	check(s["enemies"][0]["binds"] == 0 and s["enemies"][0]["guard"] == 11, "drawer eats rings into armor")
	s = fixture()
	ops(s, [{"op": "tie"}])
	s["enemies"][0]["guard"] = 4
	ops(s, [{"op": "damage", "amount": 5}])
	check(s["enemies"][0]["hp"] == 19 and s["enemies"][1]["hp"] == 20, "link uses hp loss after armor")
	ops(s, [{"op": "link_full"}, {"op": "damage", "amount": 5}])
	check(s["enemies"][0]["hp"] == 14 and s["enemies"][1]["hp"] == 15, "full link nonrecursive")
	s = fixture()
	s["enemies"][1]["pair_tag"] = "lint"
	ops(s, [{"op": "tie"}])
	s["enemies"][0]["hp"] = 10
	s["enemies"][1]["hp"] = 10
	rules.check_pairs(s, [])
	check(s["battle_flags"]["pairs"] == 0, "different kinds never pair normally")
	s["enemies"][1]["pair_tag"] = "sock"
	s["enemies"][0]["max_hp"] = 21
	s["enemies"][0]["hp"] = 11
	rules.check_pairs(s, [])
	check(s["battle_flags"]["pairs"] == 1, "threshold ceil for odd max hp")
	s = fixture()
	ops(s, [{"op": "tie"}])
	ops(s, [{"op": "damage", "amount": 25}])
	rules.check_pairs(s, [])
	check(s["enemies"][0]["departed"] == "scattered" and s["battle_flags"]["pairs"] == 0, "dead target cannot pair")
	s = fixture()
	ops(s, [{"op": "bind_all", "amount": 3}, {"op": "tie_leftmost"}])
	check(s["enemies"][0]["binds"] == 3 and s["enemies"][1]["binds"] == 3 and rules.partner_slot(s, 0) == 1, "all binds and leftmost tie")
	ops(s, [{"op": "move_binds", "amount": 2}])
	check(s["enemies"][0]["binds"] == 0 and s["enemies"][1]["binds"] == 8, "move rings and bonus")
	ops(s, [{"op": "unbind_damage", "amount": 2}], 1, 0)
	check(s["enemies"][1]["binds"] == 0 and s["enemies"][1]["hp"] == 4, "wring consumes all binds into damage")
	s = fixture()
	ops(s, [{"op": "idle_if_binds", "amount": 3, "threshold": 3}])
	check(s["enemies"][0]["binds"] == 3, "knot fallback binds")
	ops(s, [{"op": "idle_if_binds", "amount": 3, "threshold": 3}])
	check(s["enemies"][0]["idle_override"], "knot idles bound enemy")
	s = fixture(1)
	ops(s, [{"op": "bind", "amount": 7}, {"op": "recoil_if_fully_bound", "amount": 4}])
	rules.end_turn(s)
	check(s["enemies"][0]["hp"] == 16 and s["enemies"][0]["binds"] == 1, "full attack blocked recoil")
	s = fixture(1)
	ops(s, [{"op": "bind", "amount": 4}, {"op": "recoil_if_fully_bound", "amount": 4}])
	rules.end_turn(s)
	check(s["enemies"][0]["hp"] == 20, "partial multiattack does not recoil")
	s = fixture()
	ops(s, [{"op": "double_binds_this_turn"}, {"op": "bind_both", "amount": 2}])
	check(s["enemies"][0]["binds"] == 4 and s["enemies"][1]["binds"] == 4, "vow doubles both ends")
	rules.end_turn(s)
	ops(s, [{"op": "bind", "amount": 2}])
	check(s["enemies"][0]["binds"] == 2, "vow expires next turn")
	s = fixture()
	ops(s, [{"op": "next_turn_refill", "amount": 7}])
	rules.end_turn(s)
	check(s["hand"].size() == 7, "next turn refill seven")
	rules.draw(s, 5, [])
	check(s["hand"].size() == 7, "hand hard cap seven")
	s = fixture()
	ops(s, [{"op": "extra_shake", "amount": 1}])
	rules.shake_card(s, 0)
	check(rules.shake_card(s, 0)[0]["type"] == "shake_card", "extra shake allows second")
	s = fixture()
	ops(s, [{"op": "tie"}])
	s["enemies"][1]["cycle_index"] = 1
	s["enemies"][0]["intent_override"] = {"type": "guard", "amount": 7}
	ops(s, [{"op": "swap_intent_with_partner"}])
	check(rules.forecast(s)["intents"][1]["type"] == "guard" and rules.forecast(s)["intents"][0]["type"] == "attack", "swap planned intents")
	s = fixture()
	ops(s, [{"op": "tie"}])
	s["enemies"][0]["hp"] = 15
	s["enemies"][1]["hp"] = 15
	ops(s, [{"op": "pair_threshold_override", "threshold": 0.75, "amount": 2}])
	rules.check_pairs(s, [])
	check(s["battle_flags"]["pairs"] == 1, "one pair raises threshold to seventyfive")
	s = fixture()
	ops(s, [{"op": "pair_threshold_override", "threshold": 0.75, "amount": 2}])
	check(s["enemies"][0]["binds"] == 2 and s["enemies"][1]["binds"] == 2, "one pair fallback binds all")
	s = fixture()
	s["hand"] = []
	s["battle_flags"]["pairs"] = 2
	ops(s, [{"op": "per_pair_draw_energy"}])
	check(s["hand"].size() == 2 and s["energy"] == 5, "pick up draws and recovers per pair")
	s = fixture(1)
	s["player"]["guard"] = 100
	rules.end_turn(s)
	check(s["player"]["hp"] == 34 and s["player"]["guard"] == 0, "legacy player guard never absorbs damage")
	s = fixture(2)
	s["player"]["hp"] = 1
	s["spare_rope_available"] = true
	rules.end_turn(s)
	check(s["spare_rope_used"] and s["player"]["hp"] == 0, "rope once; later uncovered hit can defeat")
	check(s["enemies"][0]["binds"] == 2 and s["enemies"][1]["binds"] == 0, "rope applies five to every enemy immediately")
	s = fixture()
	s["hand"] = [rules.new_card(s, "card.tie")]
	var before: Dictionary = s.duplicate(true)
	var preview: Dictionary = rules.preview(s, 0, 0, {"second_target": 1})
	check(preview["valid"] and s == before and preview["state"]["enemies"][0]["tie"] != "", "dual target preview pure")
	var count: int = 0
	for action: Dictionary in rules.legal_actions(s):
		if action["type"] == "play_card":
			count += 1
			check(action["target_index"] != action["choices"]["second_target"], "legal dual targets differ")
	check(count == 2, "both dual target orders enumerated")
	s = fixture()
	ops(s, [{"op": "tie"}, {"op": "swap_intent_with_partner"}, {"op": "bind", "amount": 3}, {"op": "idle_if_binds", "amount": 3}])
	check(rules.forecast(s)["intents"][0]["type"] == "idle", "knot overrides swapped attack")
	s = fixture()
	ops(s, [{"op": "tie"}])
	s["enemies"][1]["guard"] = 9
	ops(s, [{"op": "damage", "amount": 6}])
	check(s["enemies"][1]["hp"] == 17 and s["enemies"][1]["guard"] == 9, "link directly loses hp bypassing partner armor")


func hook_cycle_test() -> void:
	var custom: RefCounted = Rules.new({"cards": [{"id": "card.test", "starterCount": 10, "cost": 1, "ops": []}], "enemies": [{"id": "enemy.test", "hp": 20, "intents": [{"type": "idle"}]}], "relics": [{"id": "relic.loop", "trigger": "bind_applied", "when": {"amount": 1}, "ops": [{"op": "bind", "amount": 1}]}]})
	var s: Dictionary = custom.start({"enemies": ["enemy.test"]}, {"relics": ["relic.loop"]}, 1)["state"]
	custom.bind_enemy(s, 0, 1, [])
	check(s["enemies"][0]["binds"] == 2, "custom hook does not recursively retrigger itself")
	custom.bind_enemy(s, 0, 1, [])
	check(s["enemies"][0]["binds"] == 4, "separate hook dispatches remain available")
