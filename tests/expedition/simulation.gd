extends RefCounted
## Actual seven-node expeditions, using only BattleRules and legal PolicyBot actions.
const RunRules = preload("res://scripts/core/run_rules.gd")
const BattleRules = preload("res://scripts/core/battle_rules.gd")
const PolicyBot = preload("res://scripts/core/policy_bot.gd")
const RNG = preload("res://scripts/core/rng.gd")
var expedition: RefCounted
var battle_rules: RefCounted
var bot: RefCounted
var balance: Dictionary
var report: Dictionary = {}

func run(definitions: Dictionary, count: int = 300) -> Dictionary:
	report = {"stage": "d1-expedition", "full_simulation_implemented": true, "trips": 0, "campaigns_completed": 0, "errors": [], "strategies": {}, "encounters": {}, "relics": {}, "actual_battle_attempts": 0, "turns": 0, "nodes": 0, "boss_retries": 0}
	report["requested_trips"] = count
	report["completed"] = false
	if count <= 0:
		report["errors"].append({"reason": "invalid_requested_trips"})
		return report
	expedition = RunRules.new(definitions)
	battle_rules = BattleRules.new(definitions)
	bot = PolicyBot.new(definitions)
	balance = definitions["balance"][0]
	var started: int = Time.get_ticks_msec()
	report["seed_protocol"] = {"trip_seed_start": 10000, "trip_seed_step": 7919, "same_seed_schedule_per_reward_strategy": true, "battle_policy": "defensive legal-action heuristic", "commission_policy": "take up to two; prioritize stars then hearts", "retry_policy": "up to two assisted retries after actual defeat"}
	for strategy: String in ["random_rewards", "biased_rewards"]:
		var meta: Dictionary = expedition.new_meta()
		report["strategies"][strategy] = {"trips": 0, "boss_attempts": 0, "boss_first_attempts": 0, "boss_wins": 0, "boss_first_wins": 0, "normal_attempts": 0, "normal_wins": 0, "elite_attempts": 0, "elite_wins": 0, "retries": 0, "turns": 0, "nodes": 0, "battles": 0}
		var strategy_count: int = count / 2 + (count % 2 if strategy == "random_rewards" else 0)
		for index: int in range(strategy_count):
			if meta["ending_seen"]: meta = expedition.new_meta()
			var seed_value: int = 10000 + index * 7919
			var result: Dictionary = play_trip(meta, seed_value, strategy)
			if not result["ok"]:
				report["errors"].append(result)
				break
			report["trips"] += 1
			if meta["ending_seen"]: report["campaigns_completed"] += 1
	report["boss_retry_probe"] = _retry_probe(maxi(1, count / 6))
	for strategy: String in report["strategies"]:
		var data: Dictionary = report["strategies"][strategy]
		data["boss_win_rate"] = _rate(data["boss_wins"], data["boss_attempts"])
		data["boss_first_attempt_win_rate"] = _rate(data["boss_first_wins"], data["boss_first_attempts"])
		data["normal_win_rate"] = _rate(data["normal_wins"], data["normal_attempts"])
		data["elite_win_rate"] = _rate(data["elite_wins"], data["elite_attempts"])
		data["average_battles_per_trip"] = _rate(data["battles"], data["trips"])
		data["estimated_seconds_per_trip"] = _rate(int(data["turns"]) * int(balance["simulation_turn_seconds"]) + int(data["nodes"]) * int(balance["simulation_node_seconds"]), data["trips"])
	for encounter: String in report["encounters"]:
		var data: Dictionary = report["encounters"][encounter]
		data["win_rate"] = _rate(data["wins"], data["attempts"])
		data["average_turns"] = _rate(data["turns"], data["attempts"])
		data["average_hp_loss"] = _rate(data["hp_loss"], data["attempts"])
	for relic: String in report["relics"]:
		var data: Dictionary = report["relics"][relic]
		data["boss_win_rate_when_owned"] = _rate(data["boss_wins"], data["boss_attempts"])
		var total_boss: Dictionary = report["encounters"].get("boss.sock_snake", {"attempts": 0, "wins": 0})
		data["boss_attempts_when_absent"] = int(total_boss["attempts"]) - int(data["boss_attempts"])
		data["boss_win_rate_when_absent"] = _rate(int(total_boss["wins"]) - int(data["boss_wins"]), data["boss_attempts_when_absent"])
		data["observed_win_rate_difference"] = float(data["boss_win_rate_when_owned"]) - float(data["boss_win_rate_when_absent"])
	report["elapsed_seconds"] = float(Time.get_ticks_msec() - started) / 1000.0
	report["timing_note"] = "Formula estimate from actual turns × %s sec + actual visited nodes × %s sec; excludes story reading, reward choice and UI interaction; not observed human playtime." % [balance["simulation_turn_seconds"], balance["simulation_node_seconds"]]
	report["relic_note"] = "Observational ownership association, not causal effect; randomized and biased reward strategies share the same defensive battle policy."
	report["completed"] = report["errors"].is_empty() and int(report["trips"]) == count
	return report

func play_trip(meta: Dictionary, seed_value: int, strategy: String) -> Dictionary:
	var selected: Array = expedition.available_commissions(meta)
	selected = selected.slice(0, 2 if "double_commission" in meta["services"] else 1)
	var started: Dictionary = expedition.start_run(meta, selected, seed_value)
	if not started["ok"]: return {"ok": false, "reason": "start", "seed": seed_value}
	var run: Dictionary = started["run"]
	var policy_rng: RefCounted = RNG.new(RNG.derive(seed_value, "simulation_policy"))
	var steps: int = 0
	var state: Dictionary = {}
	var stats: Dictionary = report["strategies"][strategy]
	while run["phase"] != "hub" and steps < 1000:
		steps += 1
		match run["phase"]:
			"departure":
				var offers: Array = []
				for id: String in run["departure_offers"]: offers.append({"kind": "relic", "id": id})
				expedition.choose_departure(run, policy_rng.range_int(0, offers.size() - 1) if strategy == "random_rewards" else bot.choose_reward(offers, run, "defensive"))
			"path": expedition.choose_path(run, _pick_path(run, policy_rng))
			"node":
				var choices: Array = expedition.node_choices(run)
				var selected_choice: String = _pick_node(run, choices)
				expedition.choose_node(run, selected_choice, meta)
			"replacement": expedition.replace_card(run, _replacement_index(run))
			"reward":
				var offers: Array = expedition.reward_choices(run)
				var index: int = policy_rng.range_int(0, offers.size() - 1) if strategy == "random_rewards" else bot.choose_reward(offers, run, "defensive")
				expedition.choose_reward(run, index)
			"battle_ready":
				var battle: Dictionary = expedition.start_battle(run, battle_rules)
				state = battle["state"]
				if state.is_empty(): return {"ok": false, "reason": "battle_start", "seed": seed_value, "events": battle["events"]}
			"battle":
				var hp_start: int = int(state["player"]["hp"])
				var terminal_events: Array = []
				var actions: int = 0
				while state["status"] == "player" and actions < 20000:
					actions += 1
					var action: Dictionary = bot.choose_action(state, battle_rules, "defensive")
					if action.is_empty(): return {"ok": false, "reason": "no_legal_action", "seed": seed_value}
					terminal_events = battle_rules.play_card(state, int(action["hand_index"]), int(action.get("target_index", -1)), action.get("choices", {})) if action["type"] == "play_card" else battle_rules.end_turn(state, int(action.get("keep_index", -1)))
				if state["status"] == "player": return {"ok": false, "reason": "policy_action_budget", "seed": seed_value}
				_record_battle(run, state, hp_start, strategy)
				var completion: Array = expedition.complete_battle(run, meta, state, terminal_events)
				if completion.is_empty() or completion[0].get("type") == "invalid": return {"ok": false, "reason": "bridge", "events": completion, "seed": seed_value}
			"defeat":
				if int(run["battle_attempt"]) < 2:
					var retry: Dictionary = expedition.retry_battle(run, battle_rules, state)
					state = retry["state"]
					stats["retries"] += 1
					if run["current_node"]["type"] == "boss": report["boss_retries"] += 1
					if state.is_empty(): return {"ok": false, "reason": "retry", "seed": seed_value}
				else: expedition.end_run(run, meta, "defeat")
			"return": expedition.acknowledge_story(run, meta, expedition.pending_story(run)["id"])
			_: return {"ok": false, "reason": "unknown_phase", "phase": run["phase"]}
	if steps >= 1000: return {"ok": false, "reason": "expedition_step_budget", "seed": seed_value}
	stats["trips"] += 1
	stats["nodes"] += run["stats"]["nodes"]
	report["nodes"] += run["stats"]["nodes"]
	return {"ok": true}

func _pick_path(run: Dictionary, rng: RefCounted) -> int:
	var choices: Array = expedition.path_choices(run)
	for i: int in range(choices.size()):
		if not choices[i]["star_ids"].is_empty(): return i
	for i: int in range(choices.size()):
		if not choices[i]["heart_ids"].is_empty(): return i
	for i: int in range(choices.size()):
		if choices[i]["type"] == "campfire" and int(run["hp"]) < int(run["max_hp"]): return i
	return rng.range_int(0, choices.size() - 1)

func _pick_node(run: Dictionary, choices: Array) -> String:
	for choice: Dictionary in choices:
		if choice.has("when"): return choice["id"]
	if run["current_node"]["type"] == "campfire": return "rest"
	for choice: Dictionary in choices:
		for op: Dictionary in choice["ops"]:
			if op["op"] == "heal" and int(run["hp"]) < int(run["max_hp"]): return choice["id"]
	for choice: Dictionary in choices:
		for op: Dictionary in choice["ops"]:
			if op["op"] in ["gain_relic", "gain_card", "max_hp"]: return choice["id"]
	return choices[0]["id"]

func _replacement_index(run: Dictionary) -> int:
	# Replace only as part of an earned card acquisition, never optimize by deletion.
	for i: int in range(run["deck"].size()):
		if run["deck"][i] == "card.knock": return i
	return 0

func _record_battle(run: Dictionary, state: Dictionary, hp_start: int, strategy: String) -> void:
	var won: bool = state["status"] == "victory"
	var type: String = run["current_node"]["type"]
	var category: String = "normal" if type == "battle" else type
	var stats: Dictionary = report["strategies"][strategy]
	stats[category + "_attempts"] += 1
	if won: stats[category + "_wins"] += 1
	stats["turns"] += int(state["turn"])
	stats["battles"] += 1
	report["actual_battle_attempts"] += 1
	report["turns"] += int(state["turn"])
	var id: String = state["encounter"]["id"]
	if not report["encounters"].has(id): report["encounters"][id] = {"attempts": 0, "wins": 0, "turns": 0, "hp_loss": 0}
	var encounter: Dictionary = report["encounters"][id]
	encounter["attempts"] += 1
	encounter["wins"] += 1 if won else 0
	encounter["turns"] += int(state["turn"])
	encounter["hp_loss"] += maxi(0, hp_start - int(state["player"]["hp"]))
	if category == "boss":
		if int(run["battle_attempt"]) == 0:
			stats["boss_first_attempts"] += 1
			stats["boss_first_wins"] += 1 if won else 0
		for relic: String in run["relics"]:
			if not report["relics"].has(relic): report["relics"][relic] = {"boss_attempts": 0, "boss_wins": 0}
			report["relics"][relic]["boss_attempts"] += 1
			report["relics"][relic]["boss_wins"] += 1 if won else 0

func _rate(numerator: Variant, denominator: Variant) -> float:
	return float(numerator) / float(denominator) if int(denominator) > 0 else 0.0

func _retry_probe(samples: int) -> Dictionary:
	var result: Dictionary = {"scope": "Controlled standalone boss battles with untouched ten-card starter deck, full HP, no relics/keepsakes/services; not additional expeditions. Retry occurs only after a real defeat.", "seeds": {"start": 800000, "step": 97}, "policies": {}}
	for policy: String in ["defensive", "random_legal"]:
		var data: Dictionary = {"samples": samples, "baseline_wins": 0, "first_retry_attempts": 0, "first_retry_wins": 0, "second_retry_attempts": 0, "second_retry_wins": 0, "actual_battle_attempts": 0, "actual_turns": 0}
		for i: int in range(samples):
			var seed_value: int = 800000 + i * 97
			var initial: Dictionary = {"hp": int(balance["max_hp"]), "max_hp": int(balance["max_hp"]), "deck": expedition.config["starter_deck"].duplicate(), "relics": [], "keepsakes": [], "spare_rope_available": false, "spare_rope_used": false}
			var state: Dictionary = battle_rules.start({"id": "boss.sock_snake", "enemies": ["boss.sock_snake"]}, initial, seed_value)["state"]
			var rng: RefCounted = RNG.new(RNG.derive(seed_value, "probe_policy"))
			for attempt: int in range(3):
				var actions: int = 0
				while state["status"] == "player" and actions < 20000:
					actions += 1
					var action: Dictionary
					if policy == "random_legal":
						var legal: Array = battle_rules.legal_actions(state)
						action = legal[rng.range_int(0, legal.size() - 1)]
					else: action = bot.choose_action(state, battle_rules)
					if action["type"] == "play_card": battle_rules.play_card(state, action["hand_index"], action["target_index"], action["choices"])
					else: battle_rules.end_turn(state, action.get("keep_index", -1))
				data["actual_battle_attempts"] += 1
				data["actual_turns"] += int(state["turn"])
				if state["status"] == "player":
					report["errors"].append({"reason": "probe_action_budget", "seed": seed_value, "policy": policy})
					break
				var won: bool = state["status"] == "victory"
				if attempt == 0:
					data["baseline_wins"] += 1 if won else 0
				elif attempt == 1:
					data["first_retry_attempts"] += 1
					data["first_retry_wins"] += 1 if won else 0
				else:
					data["second_retry_attempts"] += 1
					data["second_retry_wins"] += 1 if won else 0
				if won: break
				if attempt < 2: state = battle_rules.retry(state, attempt + 1)["state"]
		data["baseline_win_rate"] = _rate(data["baseline_wins"], samples)
		data["cumulative_success_with_one_retry"] = _rate(int(data["baseline_wins"]) + int(data["first_retry_wins"]), samples)
		data["cumulative_success_with_two_retries"] = _rate(int(data["baseline_wins"]) + int(data["first_retry_wins"]) + int(data["second_retry_wins"]), samples)
		data["conditional_first_retry_win_rate"] = _rate(data["first_retry_wins"], data["first_retry_attempts"]) if int(data["first_retry_attempts"]) > 0 else null
		data["conditional_second_retry_win_rate"] = _rate(data["second_retry_wins"], data["second_retry_attempts"]) if int(data["second_retry_attempts"]) > 0 else null
		result["policies"][policy] = data
	return result
