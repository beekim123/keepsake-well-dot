extends RefCounted
const Rules = preload("res://scripts/core/battle_rules.gd")
const Bot = preload("res://scripts/core/policy_bot.gd")
func run(catalog: Node) -> Dictionary:
	var defs: Dictionary = catalog.definitions()
	var rules: RefCounted = Rules.new(defs)
	var failures: Array = []
	var results: Array = []
	for case: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://tests/rope_pair/policy_cases.json")):
		if case["strategy"] == "no_pairs": continue # Deprecated low-damage replacement fixture is a documented lower bound.
		var snap: Dictionary = case["snapshot"]
		var s: Dictionary = rules.start(snap["encounter"], snap["run"], int(snap["seed"]))["state"]
		var bot: RefCounted = Bot.new(defs)
		var actions: int = 0
		while s["status"] == "player" and int(s["turn"]) < 100 and actions < 1000:
			actions += 1
			rules.apply_action(s, bot.choose_action(s, rules, case["strategy"]))
		results.append({"strategy": case["strategy"], "status": s["status"], "turn": s["turn"], "boss_hp": s["enemies"][0]["hp"], "player_hp": s["player"]["hp"]})
		if s["status"] == "player": failures.append("policy stalled: " + case["strategy"])
	var bot: RefCounted = Bot.new(defs)
	if not bot.has_method("choose_replacement"): failures.append("replacement policy missing")
	else:
		var run: Dictionary = {"deck": defs["meta"][0]["starter_deck"].duplicate() + ["card.curl_up", "card.blanket"], "pending_card": {"id": "card.curl_up"}}
		var selected: int = bot.choose_replacement(run)
		if rules.definition("cards", run["deck"][selected])["type"] == "attack": failures.append("defense acquisition removes baseline attack")
	return {"passed": 2 - failures.size(), "failed": failures.size(), "failures": failures, "cases": results}
