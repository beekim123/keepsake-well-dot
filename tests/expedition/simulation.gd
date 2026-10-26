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
	report = {"stage": "rope-and-pair-initial", "full_simulation_implemented": true, "trips": 0, "campaigns_completed": 0, "errors": [], "strategies": {}, "encounters": {}, "relics": {}, "actual_battle_attempts": 0, "turns": 0, "nodes": 0, "boss_retries": 0}
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
	report["seed_protocol"] = {"trip_seed_start": 10000, "trip_seed_step": 7919, "same_seed_schedule_per_reward_strategy": true, "battle_policy": "competent / random_legal / no_pairs", "commission_policy": "take up to two; prioritize stars then hearts", "retry_policy": "up to two assisted retries after actual defeat"}
	for strategy: String in ["competent", "random_legal", "no_pairs"]:
		var meta: Dictionary = expedition.new_meta()
		print("SIM_STRATEGY_START: " + strategy)
		report["strategies"][strategy] = _new_stats()
		var strategy_count: int = count / 3 + (1 if ["competent", "random_legal", "no_pairs"].find(strategy) < count % 3 else 0)
		for index: int in range(strategy_count):
			if meta["ending_seen"]: meta = expedition.new_meta()
			var seed_value: int = 10000 + index * 7919
			print("SIM_TRIP: %s %d seed=%d" % [strategy, index + 1, seed_value])
			var result: Dictionary = play_trip(meta, seed_value, strategy)
			if not result["ok"]:
				report["errors"].append(result)
				break
			report["trips"] += 1
			if meta["ending_seen"]: report["campaigns_completed"] += 1
	if not report["errors"].is_empty(): return report
	report["boss_retry_probe"] = _retry_probe(maxi(1, count / 6))
	for strategy: String in report["strategies"]:
		var data: Dictionary = report["strategies"][strategy]
		data["boss_win_rate"] = _rate(data["boss_wins"], data["boss_attempts"])
		data["boss_first_attempt_win_rate"] = _rate(data["boss_first_wins"], data["boss_first_attempts"])
		data["normal_win_rate"] = _rate(data["normal_wins"], data["normal_attempts"])
		data["elite_win_rate"] = _rate(data["elite_wins"], data["elite_attempts"])
		data["normal_average_turns"] = _rate(data["normal_turns"], data["normal_attempts"])
		data["normal_average_hp_loss"] = _rate(data["normal_hp_loss"], data["normal_attempts"])
		data["elite_average_turns"] = _rate(data["elite_turns"], data["elite_attempts"])
		data["elite_first_win_rate"] = _rate(data["elite_first_wins"], data["elite_first_attempts"])
		data["pair_opportunity_success_rate"] = _rate(data["paired_battles"], data["pair_opportunities"])
		data["average_relics_per_trip"] = _rate(data["relics_acquired"], data["trips"])
		data["boss_cumulative_win_rate"] = _rate(data["boss_completed_trips"], data["boss_first_attempts"])
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
	report["paired_relic_probe"] = _relic_probe(maxi(1, mini(10, count / 30)))
	report["targets"] = _targets()
	report["elapsed_seconds"] = float(Time.get_ticks_msec() - started) / 1000.0
	report["timing_note"] = "Formula estimate from actual turns × %s sec + actual visited nodes × %s sec; excludes story reading, reward choice and UI interaction; not observed human playtime." % [balance["simulation_turn_seconds"], balance["simulation_node_seconds"]]
	report["relic_note"] = "Main ownership totals are observational; paired_relic_probe uses competent policy, fresh permanent progress and identical seed schedule, with exactly one extra starting relic. Subsequent rewards and route choices can diverge as real consequences."
	report["completed"] = report["errors"].is_empty() and int(report["trips"]) == count
	return report

func play_trip(meta: Dictionary, seed_value: int, strategy: String, initial_relic: String = "") -> Dictionary:
	var selected: Array = expedition.available_commissions(meta)
	selected = selected.slice(0, 2 if "double_commission" in meta["services"] else 1)
	var started: Dictionary = expedition.start_run(meta, selected, seed_value)
	if not started["ok"]: return {"ok": false, "reason": "start", "seed": seed_value}
	var run: Dictionary = started["run"]
	if not initial_relic.is_empty(): run["relics"].append(initial_relic)
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
				expedition.choose_departure(run, policy_rng.range_int(0, offers.size() - 1) if strategy == "random_legal" else bot.choose_reward(offers, run, strategy))
			"path": expedition.choose_path(run, _pick_path(run, policy_rng))
			"node":
				var choices: Array = expedition.node_choices(run)
				var selected_choice: String = _pick_node(run, choices)
				expedition.choose_node(run, selected_choice, meta)
			"replacement": expedition.replace_card(run, bot.choose_replacement(run, strategy, policy_rng.range_int(0, run["deck"].size() - 1)) if strategy == "random_legal" else bot.choose_replacement(run, strategy))
			"reward":
				var offers: Array = expedition.reward_choices(run)
				var index: int = policy_rng.range_int(0, offers.size() - 1) if strategy == "random_legal" else bot.choose_reward(offers, run, strategy)
				expedition.choose_reward(run, index)
			"battle_ready":
				var battle: Dictionary = expedition.start_battle(run, battle_rules)
				state = battle["state"]
				if state.is_empty(): return {"ok": false, "reason": "battle_start", "seed": seed_value, "events": battle["events"]}
			"battle":
				var hp_start: int = int(state["player"]["hp"])
				var terminal_events: Array = []
				var actions: int = 0
				while state["status"] == "player" and actions < 3000 and int(state["turn"]) <= 300:
					actions += 1
					var action: Dictionary = bot.choose_action(state, battle_rules, strategy)
					if action.is_empty(): return {"ok": false, "reason": "no_legal_action", "seed": seed_value}
					terminal_events = battle_rules.apply_action(state, action)
					if not terminal_events.is_empty() and terminal_events[0].get("type", "") == "invalid_action": return {"ok": false, "reason": "illegal_policy_action", "action": action, "events": terminal_events, "seed": seed_value}
				if state["status"] == "player": return {"ok": false, "reason": "policy_action_or_turn_budget", "seed": seed_value, "strategy": strategy, "deck": run["deck"].duplicate(), "battle": state.duplicate(true)}
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
	stats["relics_acquired"] += run["relics"].size()
	if run.get("boss_won", false): stats["boss_completed_trips"] += 1
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

func _record_battle(run: Dictionary, state: Dictionary, hp_start: int, strategy: String) -> void:
	var won: bool = state["status"] == "victory"
	var type: String = run["current_node"]["type"]
	var category: String = "normal" if type == "battle" else type
	var stats: Dictionary = report["strategies"][strategy]
	if category == "normal":
		stats["normal_turns"] += int(state["turn"])
		stats["normal_hp_loss"] += maxi(0, hp_start - int(state["player"]["hp"]))
		if state["encounter"].get("pair_opportunity", false):
			stats["pair_opportunities"] += 1
			if int(state["battle_flags"]["pairs"]) > 0: stats["paired_battles"] += 1
	if category == "elite":
		stats["elite_turns"] += int(state["turn"])
		if int(run["battle_attempt"]) == 0:
			stats["elite_first_attempts"] += 1
			stats["elite_first_wins"] += 1 if won else 0
	stats["hp_loss"] += maxi(0, hp_start - int(state["player"]["hp"]))
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
				while state["status"] == "player" and actions < 3000 and int(state["turn"]) <= 300:
					actions += 1
					var action: Dictionary
					if policy == "random_legal":
						var legal: Array = battle_rules.legal_actions(state)
						action = legal[rng.range_int(0, legal.size() - 1)]
					else: action = bot.choose_action(state, battle_rules)
					battle_rules.apply_action(state, action)
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

func _new_stats() -> Dictionary:
	return {"trips": 0, "boss_attempts": 0, "boss_first_attempts": 0, "boss_wins": 0, "boss_first_wins": 0, "normal_attempts": 0, "normal_wins": 0, "elite_attempts": 0, "elite_wins": 0, "retries": 0, "turns": 0, "nodes": 0, "battles": 0, "normal_turns": 0, "normal_hp_loss": 0, "elite_first_attempts": 0, "elite_first_wins": 0, "elite_turns": 0, "pair_opportunities": 0, "paired_battles": 0, "relics_acquired": 0, "boss_completed_trips": 0, "hp_loss": 0}

func _relic_probe(samples: int) -> Dictionary:
	var main_report: Dictionary = report
	var result: Dictionary = {"scope": "Paired full seven-node trips; same seed, starter deck, HP and fresh meta, competent policy, with/without one starting relic; all earned rewards and real retry effects retained.", "samples_per_relic": samples, "seed_start": 930000, "seed_step": 83, "probe_trips": 0, "relics": {}, "impact_at_least_ten_percent": 0, "errors": []}
	for relic: Dictionary in expedition.definitions.get("relics", []):
		print("SIM_RELIC_PROBE: " + str(relic["id"]))
		var paired: Dictionary = {"owned": {"turns": 0, "hp_loss": 0, "trips": 0}, "absent": {"turns": 0, "hp_loss": 0, "trips": 0}, "samples": []}
		for index: int in range(samples):
			var pair_sample: Dictionary = {"seed": 930000 + index * 83}
			for mode: String in ["absent", "owned"]:
				report = {"strategies": {"competent": _new_stats()}, "encounters": {}, "relics": {}, "actual_battle_attempts": 0, "turns": 0, "nodes": 0, "boss_retries": 0, "errors": []}
				var meta: Dictionary = expedition.new_meta()
				var trip: Dictionary = play_trip(meta, pair_sample["seed"], "competent", str(relic["id"]) if mode == "owned" else "")
				if not trip.get("ok", false):
					result["errors"].append({"relic": relic["id"], "mode": mode, "result": trip})
					continue
				var stats: Dictionary = report["strategies"]["competent"]
				pair_sample[mode] = {"turns": stats["turns"], "hp_loss": stats["hp_loss"], "boss_won": stats["boss_completed_trips"]}
				paired[mode]["turns"] += int(stats["turns"])
				paired[mode]["hp_loss"] += int(stats["hp_loss"])
				paired[mode]["trips"] += 1
				result["probe_trips"] += 1
			paired["samples"].append(pair_sample)
		for mode: String in ["absent", "owned"]:
			paired[mode]["average_turns"] = _rate(paired[mode]["turns"], paired[mode]["trips"])
			paired[mode]["average_hp_loss"] = _rate(paired[mode]["hp_loss"], paired[mode]["trips"])
		paired["turn_relative_difference"] = _rate(absf(float(paired["owned"]["average_turns"]) - float(paired["absent"]["average_turns"])), paired["absent"]["average_turns"])
		paired["hp_loss_relative_difference"] = _rate(absf(float(paired["owned"]["average_hp_loss"]) - float(paired["absent"]["average_hp_loss"])), paired["absent"]["average_hp_loss"])
		paired["impact_at_least_ten_percent"] = maxf(paired["turn_relative_difference"], paired["hp_loss_relative_difference"]) >= 0.1
		if paired["impact_at_least_ten_percent"]: result["impact_at_least_ten_percent"] += 1
		result["relics"][relic["id"]] = paired
	report = main_report
	for error: Dictionary in result["errors"]: report["errors"].append(error)
	return result

func _targets() -> Dictionary:
	var competent: Dictionary = report["strategies"].get("competent", {})
	var random: Dictionary = report["strategies"].get("random_legal", {})
	var result: Dictionary = {}
	var specs: Array = [
		["normal_turns", competent.get("normal_average_turns", 0), 3.0, 4.5],
		["normal_hp_loss", competent.get("normal_average_hp_loss", 0), 2.0, 6.0],
		["random_normal_win_rate", random.get("normal_win_rate", 0), 0.7, 1.0],
		["pair_opportunity_rate", competent.get("pair_opportunity_success_rate", 0), 0.5, 1.0],
		["elite_turns", competent.get("elite_average_turns", 0), 5.0, 7.0],
		["elite_first_win_rate", competent.get("elite_first_win_rate", 0), 0.85, 1.0],
		["boss_first_win_rate", competent.get("boss_first_attempt_win_rate", 0), 0.7, 0.85],
		["boss_cumulative_two_retries", competent.get("boss_cumulative_win_rate", 0), 0.97, 1.0],
		["relics_with_ten_percent_impact", report["paired_relic_probe"]["impact_at_least_ten_percent"], 10, 15],
		["estimated_seconds", competent.get("estimated_seconds_per_trip", 0), 600, 900],
		["relics_per_trip", competent.get("average_relics_per_trip", 0), 2, 4]]
	for spec: Array in specs: result[spec[0]] = {"actual": spec[1], "min": spec[2], "max": spec[3], "met": float(spec[1]) >= float(spec[2]) and float(spec[1]) <= float(spec[3])}
	return result
