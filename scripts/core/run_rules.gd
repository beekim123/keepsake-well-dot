extends RefCounted
## Expedition coordinator. Every command validates before mutation.
const RNG = preload("res://scripts/core/rng.gd")
const MetaState = preload("res://scripts/core/meta_state.gd")
const RunState = preload("res://scripts/core/run_state.gd")
const PathGen = preload("res://scripts/core/path_gen.gd")
const Nodes = preload("res://scripts/core/nodes.gd")
var definitions: Dictionary
var balance: Dictionary
var config: Dictionary
var meta_rules: RefCounted
var run_factory: RefCounted
var path_rules: RefCounted
var node_rules: RefCounted
var keepsakes: Dictionary = {}
var encounters: Dictionary = {}
var enemies: Dictionary = {}

func _init(tables: Dictionary = {}) -> void:
	definitions = tables
	balance = tables.get("balance", [{}])[0]
	config = tables.get("meta", [{}])[0]
	meta_rules = MetaState.new(tables)
	run_factory = RunState.new(tables)
	path_rules = PathGen.new(tables)
	node_rules = Nodes.new(tables)
	for item: Dictionary in tables.get("keepsakes", []): keepsakes[item["id"]] = item
	for item: Dictionary in tables.get("encounters", []): encounters[item["id"]] = item
	for item: Dictionary in tables.get("enemies", []): enemies[item["id"]] = item

func new_meta() -> Dictionary:
	return meta_rules.create()

func normalize_meta(value: Dictionary) -> Dictionary:
	# Add known defaults without dropping forward-compatible or presentation
	# metadata from a loaded save when a later expedition starts.
	var result: Dictionary = value.duplicate(true)
	result.merge(new_meta(), false)
	return result

func available_commissions(meta: Dictionary) -> Array:
	return meta_rules.available(normalize_meta(meta))

func requires_first_run(meta: Dictionary) -> bool:
	return not str(config.get("first_commission_id", "keepsake.ring")) in meta.get("returned", [])

func is_first_run(run: Dictionary) -> bool:
	return run.get("route_mode", "") == "first_run"

func start_first_run(meta: Dictionary, seed_value: int) -> Dictionary:
	if not requires_first_run(meta): return {"ok": false, "events": _invalid("first_run_complete")}
	if path_rules.config.get("first_run", {}).is_empty(): return {"ok": false, "events": _invalid("first_run_missing")}
	return _start_run(meta, [config.get("first_commission_id", "keepsake.ring")], seed_value, true)

func start_run(meta: Dictionary, commission_ids: Array, seed_value: int) -> Dictionary:
	# Preserve the original API and deterministic seven-node route for legacy
	# checkpoints, simulations and later trips. The first-ten-minute UI opts in.
	return _start_run(meta, commission_ids, seed_value)

func _start_run(meta: Dictionary, commission_ids: Array, seed_value: int, first_run: bool = false) -> Dictionary:
	if seed_value < 0 or seed_value > 0xffffffff: return {"ok": false, "events": _invalid("seed_out_of_range")}
	var available: Array = available_commissions(meta)
	var max_count: int = int(balance.get("max_commissions", 2)) if "double_commission" in meta.get("services", []) else 1
	var retry_only: bool = available.is_empty() and not meta.get("boss_defeated", false) and config.get("allow_uncommissioned_boss_retry", false)
	if commission_ids.size() > max_count or (commission_ids.is_empty() and not retry_only): return {"ok": false, "events": _invalid("commissions")}
	var seen: Array = []
	for id: Variant in commission_ids:
		if not id is String or not id in available or id in seen: return {"ok": false, "events": _invalid("commissions")}
		seen.append(id)
	var normalized: Dictionary = normalize_meta(meta)
	var run: Dictionary = run_factory.create(normalized, commission_ids, seed_value)
	if first_run:
		run["route_mode"] = "first_run"
		run["first_trip"] = true
	run["path"] = path_rules.generate(run, normalized)
	if not first_run and "departure_choice" in normalized["services"]:
		run["phase"] = "departure"
		run["departure_offers"] = node_rules.relic_offers(run, int(balance["departure_offer_count"]))
	normalized["runs_started"] = run["number"]
	for row: Array in run["path"]:
		for node: Dictionary in row:
			var event: Dictionary = node_rules.events_by_id.get(node["id"], {})
			if event.get("once_per_save", false): normalized["once_events"][node["id"]] = true
	_replace_dict(meta, normalized)
	return {"ok": true, "run": run, "events": [{"type": "run_start", "seed": seed_value, "number": run["number"]}]}

func choose_departure(run: Dictionary, index: int) -> Array:
	if run.get("phase", "") != "departure" or index < 0 or index >= run["departure_offers"].size(): return _invalid("departure")
	var id: String = run["departure_offers"][index]
	run["relics"].append(id)
	run["departure_offers"] = []
	run["phase"] = "path"
	return [{"type": "relic_get", "id": id}, {"type": "path_ready", "segment": run["segment"]}]

func path_choices(run: Dictionary) -> Array:
	return path_rules.choices(run)

func choose_path(run: Dictionary, index: int) -> Array:
	var choices: Array = path_choices(run)
	if index < 0 or index >= choices.size(): return _invalid("path")
	var events: Array = path_rules.drift_skipped(run, index)
	var node: Dictionary = run["path"][int(run["segment"]) - 1][index].duplicate(true)
	run["current_node"] = node
	run["stats"]["nodes"] += 1
	run["history"].append({"segment": run["segment"], "index": index, "type": node["type"], "id": node["id"]})
	run["phase"] = "battle_ready" if node["type"] in ["battle", "elite", "boss"] else "node"
	run["battle_request"] = {}
	run["battle_checkpoint"] = {}
	run["battle_attempt"] = 0
	events.append({"type": "path_pick", "node": node.duplicate(true)})
	return events

func start_battle(run: Dictionary, battle_rules: RefCounted) -> Dictionary:
	if run.get("phase", "") != "battle_ready": return {"state": {}, "events": _invalid("battle_start")}
	if run.has("resume_battle"):
		var resumed: Dictionary = run["resume_battle"].duplicate(true)
		run.erase("resume_battle")
		run["phase"] = "battle"
		run["battle_checkpoint"] = resumed.duplicate(true)
		return {"state": resumed, "events": [{"type": "battle_start", "resumed": true, "encounter": resumed["encounter"]["id"]}]}
	if run["battle_request"].is_empty():
		var id: String = run["current_node"]["id"]
		var encounter: Dictionary = encounters.get(id, {}).duplicate(true)
		if encounter.is_empty() and enemies.has(id): encounter = {"id": id, "enemies": [id], "tier": run["current_node"].get("tier", 1)}
		if encounter.is_empty(): return {"state": {}, "events": _invalid("encounter")}
		if is_first_run(run) and run["current_node"].has("tutorial_id"):
			encounter["tutorial_id"] = run["current_node"]["tutorial_id"]
		var battle_rng: RefCounted = RNG.new(run["rng_states"]["battle"])
		var shuffle_rng: RefCounted = RNG.new(run["rng_states"]["shuffle"])
		var battle_seed: int = battle_rng.next_u32()
		var shuffle_seed: int = shuffle_rng.next_u32()
		run["rng_states"]["battle"] = battle_rng.snapshot()
		run["rng_states"]["shuffle"] = shuffle_rng.snapshot()
		var initial: Dictionary = {}
		for key: String in ["hp", "max_hp", "deck", "relics", "keepsakes", "spare_rope_available", "spare_rope_used", "next_battle", "bind_bonus"]:
			initial[key] = run[key].duplicate(true) if run[key] is Array or run[key] is Dictionary else run[key]
		initial["battle_seed"] = battle_seed
		initial["shuffle_seed"] = shuffle_seed
		run["battle_request"] = {"encounter": encounter.duplicate(true), "run_state": initial, "seed": battle_seed}
	var request: Dictionary = run["battle_request"]
	var result: Dictionary = battle_rules.start(request["encounter"], request["run_state"], int(request["seed"]))
	if result.get("state", {}).is_empty(): return result
	run["phase"] = "battle"
	run["battle_checkpoint"] = result["state"].duplicate(true)
	return result

func retry_battle(run: Dictionary, battle_rules: RefCounted, defeat_state: Dictionary) -> Dictionary:
	if run.get("phase", "") != "defeat" or not _valid_terminal(run, defeat_state, "defeat"): return {"state": {}, "events": _invalid("retry")}
	var attempt: int = int(run["battle_attempt"]) + 1
	var result: Dictionary = battle_rules.retry(defeat_state, attempt)
	if result.get("state", {}).is_empty(): return result
	run["battle_attempt"] = attempt
	run["stats"]["retries"] += 1
	run["phase"] = "battle"
	run["battle_checkpoint"] = result["state"].duplicate(true)
	return result

func complete_battle(run: Dictionary, meta: Dictionary, state: Dictionary, battle_events: Array = []) -> Array:
	if run.get("phase", "") != "battle" or not state.get("status", "") in ["victory", "defeat"]: return _invalid("battle_not_finished")
	var status: String = state["status"]
	if not _valid_terminal(run, state, status): return _invalid("battle_mismatch")
	var terminal_present: bool = false
	for event: Dictionary in battle_events:
		if event.get("type", "") == status: terminal_present = true
	if not terminal_present: return _invalid("battle_terminal_event_missing")
	run["hp"] = int(state["player"]["hp"])
	run["max_hp"] = int(state["player"]["max_hp"])
	run["spare_rope_used"] = state.get("spare_rope_used", run["spare_rope_used"])
	run["stats"]["battles"] += 1
	run["stats"]["turns"] += int(state.get("turn", 0))
	if status == "defeat":
		run["phase"] = "defeat"
		return [{"type": "defeat", "segment": run["segment"]}]
	var events: Array = _collect_keepsakes(run)
	var bonus: int = int(run["next_battle"].get("extra_relic_rewards", 0))
	run["next_battle"] = {}
	for id: String in node_rules.relic_offers(run, bonus):
		run["relics"].append(id)
		events.append({"type": "relic_get", "id": id, "bonus": true})
	if run["current_node"]["type"] == "boss":
		var first: bool = not meta.get("boss_defeated", false)
		meta["boss_defeated"] = true
		meta["knot_found"] = true
		run["boss_won"] = true
		if state["battle_flags"].get("peaceful", false): events.append({"type": "peaceful_victory", "text_id": "ui.rope.peaceful_victory"})
		events.append_array(_end(run, meta, "boss", first))
		return events
	run["last_battle_pairs"] = int(state["battle_flags"].get("pairs", 0))
	run["reward_queue"] = []
	run["rewards"] = _make_rewards(run)
	run["phase"] = "reward"
	events.append({"type": "reward_ready", "choices": run["rewards"].duplicate(true)})
	_track_seen(meta, run)
	return events

func _valid_terminal(run: Dictionary, state: Dictionary, status: String) -> bool:
	if state.get("schema", "") != "battle/1" or state.get("status", "") != status or run.get("battle_request", {}).is_empty(): return false
	if state.get("encounter", {}).get("id", "") != run["battle_request"]["encounter"].get("id", ""): return false
	if int(state.get("seed", -1)) != int(run["battle_request"]["seed"]): return false
	if not state.get("player", {}) is Dictionary or not state["player"].has("hp"): return false
	if status == "defeat": return int(state["player"]["hp"]) == 0
	if int(state["player"]["hp"]) <= 0 or state.get("enemies", []).is_empty(): return false
	for enemy: Dictionary in state["enemies"]:
		if int(enemy.get("hp", 1)) > 0 and str(enemy.get("departed", "")).is_empty(): return false
	return true

func reward_choices(run: Dictionary) -> Array:
	return run.get("rewards", []).duplicate(true) if run.get("phase", "") in ["reward", "replacement"] else []

func _make_rewards(run: Dictionary) -> Array:
	var result: Array = []
	if run["current_node"]["type"] == "elite":
		run["reward_kind"] = "elite"
		for id: String in node_rules.relic_offers(run, int(balance["reward_elite_relics"])): result.append({"kind": "relic", "id": id})
		return result
	run["reward_kind"] = "cards"
	if int(run.get("last_battle_pairs", 0)) > 0:
		var thanks: Array = []
		var count: int = int(balance["reward_normal_relics"])
		for id: String in run["relics"]: count += int(_definition("relics", id).get("rules", {}).get("thanks_options_bonus", 0))
		if is_first_run(run) and not run.get("first_thanks_seen", false):
			for choice: Dictionary in path_rules.config["first_run"].get("first_thanks", []):
				if not choice["id"] in run["relics"]: thanks.append(choice.duplicate(true))
			if thanks.size() < count:
				var exclude: Array = []
				for choice: Dictionary in thanks: exclude.append(choice["id"])
				for id: String in node_rules.relic_offers(run, count - thanks.size(), exclude): thanks.append({"kind": "relic", "id": id})
		else:
			for id: String in node_rules.relic_offers(run, count): thanks.append({"kind": "relic", "id": id})
		run["first_thanks_seen"] = true
		if not thanks.is_empty(): run["reward_queue"].append(thanks)
	if is_first_run(run) and int(run["segment"]) == 1:
		result = path_rules.config["first_run"]["first_rewards"].duplicate(true)
	else:
		for id: String in node_rules.card_offers(run, int(balance["reward_normal_cards"]), "", [], not run["first_card_reward_seen"]): result.append({"kind": "card", "id": id})
	run["first_card_reward_seen"] = true
	return result

func _definition(category: String, id: String) -> Dictionary:
	for row: Dictionary in node_rules.definitions.get(category, []):
		if row["id"] == id: return row
	return {}

func _next_reward(run: Dictionary) -> Array:
	if not run.get("reward_queue", []).is_empty():
		run["rewards"] = run["reward_queue"].pop_front()
		run["reward_kind"] = "thanks"
		run["phase"] = "reward"
		return [{"type": "reward_ready", "thanks": true, "choices": run["rewards"].duplicate(true)}]
	return _advance(run)

func choose_reward(run: Dictionary, index: int, replace_index: int = -1) -> Array:
	if run.get("phase", "") == "replacement" and run["pending_card"].get("source", "") == "node": return replace_card(run, replace_index)
	if not run.get("phase", "") in ["reward", "replacement"]: return _invalid("reward")
	if index == -1 and run["phase"] == "reward": return _next_reward(run)
	if index < 0 or index >= run["rewards"].size(): return _invalid("reward")
	var choice: Dictionary = run["rewards"][index]
	var events: Array = []
	if choice["kind"] == "card" and run["deck"].size() >= int(balance["deck_limit"]):
		if replace_index == -1:
			run["pending_card"] = {"id": choice["id"], "source": "reward", "reward_index": index}
			run["phase"] = "replacement"
			return [{"type": "replacement_required", "id": choice["id"]}]
		if replace_index < 0 or replace_index >= run["deck"].size(): return _invalid("replacement")
		var removed: String = run["deck"][replace_index]
		run["removed_cards"].append(removed)
		run["deck"][replace_index] = choice["id"]
		events.append({"type": "card_replaced", "id": choice["id"], "removed": removed})
	elif choice["kind"] == "card":
		run["deck"].append(choice["id"])
		events.append({"type": "card_get", "id": choice["id"]})
	else:
		if choice["id"] in run["relics"]: return _invalid("owned_relic")
		run["relics"].append(choice["id"])
		events.append({"type": "relic_get", "id": choice["id"]})
	run["pending_card"] = {}
	events.append_array(_next_reward(run))
	return events

func cancel_replacement(run: Dictionary) -> Array:
	if run.get("phase", "") != "replacement": return _invalid("replacement")
	run["phase"] = "reward" if run["pending_card"].get("source", "") == "reward" else "node"
	run["pending_card"] = {}
	return [{"type": "replacement_cancelled"}]

func replace_card(run: Dictionary, index: int) -> Array:
	if run.get("phase", "") != "replacement" or index < 0 or index >= run["deck"].size(): return _invalid("replacement")
	var pending: Dictionary = run["pending_card"]
	if pending["source"] == "reward": return choose_reward(run, int(pending["reward_index"]), index)
	var proposed: Dictionary = pending["proposed_run"].duplicate(true)
	var removed: String = proposed["deck"][index]
	proposed["deck"][index] = pending["id"]
	proposed["removed_cards"].append(removed)
	var events: Array = pending["events"].duplicate(true)
	events.append({"type": "card_replaced", "id": pending["id"], "removed": removed})
	_replace_dict(run, proposed)
	events.append_array(_complete_node(run))
	return events

func node_choices(run: Dictionary) -> Array:
	return node_rules.choices(run)

func choose_node(run: Dictionary, choice_id: String, meta: Dictionary = {}) -> Array:
	var selected: Dictionary = {}
	for choice: Dictionary in node_choices(run):
		if choice["id"] == choice_id: selected = choice
	if selected.is_empty(): return _invalid("node_choice")
	var proposed: Dictionary = run.duplicate(true)
	var events: Array = node_rules.resolve(proposed, selected)
	if not proposed["pending_card"].is_empty():
		var id: String = proposed["pending_card"]["id"]
		proposed["pending_card"] = {}
		run["pending_card"] = {"id": id, "source": "node", "proposed_run": proposed, "events": events}
		run["phase"] = "replacement"
		return [{"type": "replacement_required", "id": id}]
	_replace_dict(run, proposed)
	if int(run["hp"]) <= 0:
		events.append_array(_end(run, meta, "defeat"))
	else:
		events.append_array(_complete_node(run, meta))
	return events

func prepare_trade(run: Dictionary, kind: String, give_index: int) -> Array:
	if run.get("phase", "") != "node" or run["current_node"].get("type", "") != "trade" or not kind in ["relic", "card"]: return _invalid("trade")
	var owned: Array = run["relics"] if kind == "relic" else run["deck"]
	if give_index < 0 or give_index >= owned.size(): return _invalid("trade_item")
	var count: int = int(balance["trade_offer_count"])
	var cache_key: String = kind + ":" + str(owned[give_index])
	if not run.has("trade_cache"): run["trade_cache"] = {}
	if not run["trade_cache"].has(cache_key):
		run["trade_cache"][cache_key] = node_rules.relic_offers(run, count) if kind == "relic" else node_rules.card_offers(run, count, node_rules.cards[owned[give_index]]["type"], [owned[give_index]])
	var offers: Array = run["trade_cache"][cache_key].duplicate()
	run["trade"] = {"kind": kind, "give_index": give_index, "give_id": owned[give_index], "offers": offers}
	return [{"type": "trade_ready", "trade": run["trade"].duplicate(true)}]

func trade_choices(run: Dictionary) -> Array:
	return run.get("trade", {}).get("offers", []).duplicate() if run.get("phase", "") == "node" else []

func choose_trade(run: Dictionary, index: int) -> Array:
	var offers: Array = trade_choices(run)
	if run.get("phase", "") != "node" or run["current_node"].get("type", "") != "trade" or index < 0 or index >= offers.size(): return _invalid("trade")
	var trade: Dictionary = run["trade"]
	var owned: Array = run["relics"] if trade["kind"] == "relic" else run["deck"]
	var give: int = int(trade["give_index"])
	if give >= owned.size() or owned[give] != trade["give_id"]: return _invalid("trade_item_changed")
	if trade["kind"] == "card": run["removed_cards"].append(owned[give])
	owned[give] = offers[index]
	var events: Array = [{"type": "trade", "kind": trade["kind"], "given": trade["give_id"], "received": offers[index]}]
	run.erase("trade")
	events.append_array(_complete_node(run))
	return events

func end_run(run: Dictionary, meta: Dictionary, reason: String = "voluntary") -> Array:
	if is_first_run(run) and reason == "voluntary": return _invalid("first_run_return_after_fire")
	if (reason == "voluntary" and run.get("phase", "") != "path") or (reason == "defeat" and run.get("phase", "") != "defeat") or not reason in ["voluntary", "defeat"]: return _invalid("end_run")
	return _end(run, meta, reason)

func _end(run: Dictionary, meta: Dictionary, reason: String, boss_first: bool = false) -> Array:
	run["phase"] = "return"
	run["end_reason"] = reason
	meta["last_end_reason"] = reason
	run["pending_stories"] = []
	if boss_first: run["pending_stories"].append({"id": config["boss_knot_story_id"]})
	run["pending_stories"].append({"id": config["pulled_home_story_id"] if reason == "defeat" else config["back_up_story_id"]})
	for id: String in run["keepsakes"]:
		if id in meta.get("returned", []): continue
		var wish: bool = run["wishes"].get(id, false)
		run["pending_stories"].append({"id": keepsakes[id]["return_story_id"], "keepsake_id": id, "wish": wish, "card_id": keepsakes[id]["replica_plus_card_id" if wish else "replica_card_id"]})
	run["return_index"] = 0
	_track_seen(meta, run)
	return [{"type": "run_end", "reason": reason}, {"type": "story_ready", "story": pending_story(run)}]

func pending_story(run: Dictionary) -> Dictionary:
	if run.get("phase", "") != "return" or run.get("pending_stories", []).is_empty(): return {}
	return run["pending_stories"][0].duplicate(true)

func acknowledge_story(run: Dictionary, meta: Dictionary, expected_story_id: String = "") -> Array:
	var story: Dictionary = pending_story(run)
	if story.is_empty() or (not expected_story_id.is_empty() and story["id"] != expected_story_id): return _invalid("story")
	var events: Array = []
	if story.has("keepsake_id"):
		events.append_array(meta_rules.grant_return(meta, keepsakes[story["keepsake_id"]], story["wish"]))
		run["keepsakes"].erase(story["keepsake_id"])
	if story["id"] == config["ending_story_id"]:
		meta["ending_seen"] = true
		events.append({"type": "demo_complete"})
	run["pending_stories"].pop_front()
	run["return_index"] += 1
	if run["pending_stories"].is_empty() and meta_rules.ending_ready(meta): run["pending_stories"].append({"id": config["ending_story_id"]})
	if run["pending_stories"].is_empty():
		run["phase"] = "hub"
		events.append({"type": "hub_enter", "reason": run["end_reason"]})
	else: events.append({"type": "story_ready", "story": pending_story(run)})
	return events

func safe_checkpoint(run: Dictionary, meta: Dictionary) -> Dictionary:
	if run.is_empty(): return {"ok": true, "meta": meta.duplicate(true), "run": null}
	var phase: String = run.get("phase", "")
	var safe_phases: Array = ["departure", "path", "battle_ready", "battle", "defeat", "return", "hub"]
	if is_first_run(run): safe_phases.append_array(["reward", "node", "replacement"])
	if not phase in safe_phases: return {"ok": false}
	var saved: Dictionary = run.duplicate(true)
	if phase in ["battle", "defeat"]:
		saved["phase"] = "battle_ready"
		# Full start snapshot preserves retry assistance and spent spare rope.
		saved["resume_battle"] = run["battle_checkpoint"].duplicate(true)
	return {"ok": true, "meta": meta.duplicate(true), "run": null if phase == "hub" else saved}

func legal_commands(run: Dictionary) -> Array:
	var result: Array = []
	match run.get("phase", ""):
		"departure":
			for i: int in range(run["departure_offers"].size()): result.append({"type": "choose_departure", "index": i})
		"path":
			for i: int in range(path_choices(run).size()): result.append({"type": "choose_path", "index": i})
			if not is_first_run(run): result.append({"type": "end_run", "reason": "voluntary"})
		"battle_ready": result.append({"type": "start_battle"})
		"defeat": result = [{"type": "retry_battle"}, {"type": "end_run", "reason": "defeat"}]
		"node":
			for choice: Dictionary in node_choices(run): result.append({"type": "choose_node", "id": choice["id"]})
			if run["current_node"]["type"] == "trade": result.append({"type": "prepare_trade"})
		"reward":
			for i: int in range(run["rewards"].size()): result.append({"type": "choose_reward", "index": i})
			result.append({"type": "choose_reward", "index": -1})
		"replacement":
			for i: int in range(run["deck"].size()): result.append({"type": "replace_card", "index": i})
			result.append({"type": "cancel_replacement"})
		"return": result.append({"type": "acknowledge_story"})
	return result

func _collect_keepsakes(run: Dictionary) -> Array:
	var events: Array = []
	for id: String in run["current_node"].get("star_ids", []):
		if id in run["keepsakes"]: continue
		run["keepsakes"].append(id)
		run["wishes"][id] = false
		run["acquired_segments"][id] = run["segment"]
		events.append({"type": "keepsake_get", "id": id})
	return events

func _complete_node(run: Dictionary, meta: Dictionary = {}) -> Array:
	var events: Array = _collect_keepsakes(run)
	events.append_array(_advance(run, meta))
	return events

func _advance(run: Dictionary, meta: Dictionary = {}) -> Array:
	var segment: int = int(run["segment"])
	for node: Dictionary in run["path"][segment - 1]:
		for id: String in node["wish_ids"]:
			if not run["wishes"].get(id, false):
				# A ring may still rest at the later fixed fire.
				var later: bool = false
				for row: Array in run["path"].slice(segment):
					for future: Dictionary in row:
						if id in future["wish_ids"]: later = true
				if not later: run["wish_missed"][id] = true
	run["rewards"] = []
	run["reward_kind"] = ""
	run["current_node"] = {}
	run.erase("trade")
	run.erase("trade_cache")
	if is_first_run(run) and segment == int(path_rules.config["first_run"]["return_after_segment"]):
		return _end(run, meta, "first_run")
	run["segment"] = segment + 1
	run["phase"] = "path"
	return [{"type": "path_ready", "segment": run["segment"]}]

func _track_seen(meta: Dictionary, run: Dictionary) -> void:
	if not meta.has("seen_relics"): meta["seen_relics"] = []
	for id: String in run["relics"]:
		if not id in meta["seen_relics"]: meta["seen_relics"].append(id)

func _invalid(reason: String) -> Array:
	return [{"type": "invalid", "reason": reason}]

func _replace_dict(target: Dictionary, source: Dictionary) -> void:
	target.clear()
	for key: Variant in source: target[key] = source[key]
