extends RefCounted
const RunRules = preload("res://scripts/core/run_rules.gd")
const BattleRules = preload("res://scripts/core/battle_rules.gd")
const PolicyBot = preload("res://scripts/core/policy_bot.gd")
var passed: int = 0
var failed: int = 0
var rules: RefCounted

func run(definitions: Dictionary) -> Dictionary:
	passed = 0
	failed = 0
	rules = RunRules.new(definitions)
	_test_paths()
	_test_invalid()
	_test_nodes()
	_test_return()
	_test_rewards()
	_test_battle_bridge()
	_test_campaign()
	_test_drift_and_failure()
	_test_all_event_outcomes()
	_test_path_hint_identity()
	_test_aunt_event_eligibility()
	return {"passed": passed, "failed": failed}

func check(condition: bool, label: String) -> void:
	if condition: passed += 1
	else:
		failed += 1
		printerr("FAIL " + label)

func _meta(returned: Array = ["keepsake.ring"]) -> Dictionary:
	var meta: Dictionary = rules.new_meta()
	for id: String in returned: rules.meta_rules.grant_return(meta, rules.keepsakes[id], true)
	return meta

func _test_paths() -> void:
	for seed_value: int in range(300):
		var meta: Dictionary = _meta()
		var result: Dictionary = rules.start_run(meta, ["keepsake.mianmian", "keepsake.letter"], seed_value)
		var run: Dictionary = result["run"]
		var path: Array = run["path"]
		check(path.size() == 7, "seven segments")
		var events: Array = []
		var places: Dictionary = {}
		var wishes: Dictionary = {}
		for row: Array in path:
			for node: Dictionary in row:
				if node["type"] == "event": events.append(node["id"])
				for id: String in node["star_ids"]: places[id] = node["segment"]
				for id: String in node["wish_ids"]: wishes[id] = node["segment"]
		var unique: Dictionary = {}
		for id: String in events: unique[id] = true
		check(events.size() == unique.size(), "events do not repeat seed " + str(seed_value))
		check(places.values().has(2) and places.values().has(4), "dual mission distinct segments 2/4")
		for id: String in places:
			check((places[id] == 2 and wishes[id] == 3) or (places[id] == 4 and wishes[id] == 5), "wish follows pickup")
		check(path[2][0]["type"] != path[2][1]["type"], "segment3 distinct types")
		check(path[1][0]["type"] == "event" or path[1][1]["type"] == "event", "segment2 contains event")
		check(path[3][0]["type"] == "elite" and path[3][1]["type"] == "campfire", "segment4 elite/fire")
		# Missing the first star must drift to sibling, never the wish node.
		run["phase"] = "path"
		run["segment"] = 2
		var skipped: String = path[1][0]["star_ids"][0]
		rules.choose_path(run, 1)
		for node: Dictionary in path[2]: check(not (skipped in node["star_ids"] and skipped in node["wish_ids"]), "no same-node wish after drift")
	var first: Dictionary = rules.start_run(rules.new_meta(), ["keepsake.ring"], 88)["run"]
	check(first["path"][0][0]["id"] == "enc.tutorial", "tutorial first trip")
	check(first["path"][3][0]["star_ids"] == ["keepsake.ring"], "ring first elite")
	check(first["path"][5][0]["wish_ids"] == ["keepsake.ring"], "ring fixed later fire")
	var encoded: String = JSON.stringify(first)
	check(JSON.parse_string(encoded) != null, "run state serializable")

func _test_invalid() -> void:
	var meta: Dictionary = rules.new_meta()
	var before: Dictionary = meta.duplicate(true)
	check(not rules.start_run(meta, [], 1)["ok"] and meta == before, "invalid zero commissions no mutation")
	check(not rules.start_run(meta, ["keepsake.ring"], -1)["ok"] and meta == before, "negative seed rejected before mutation")
	check(not rules.start_run(meta, ["keepsake.ring"], 0x100000000)["ok"] and meta == before, "oversized seed rejected before mutation")
	check(not rules.start_run(meta, ["keepsake.letter"], 1)["ok"] and meta == before, "first commission ring only")
	var run: Dictionary = rules.start_run(meta, ["keepsake.ring"], 1)["run"]
	before = run.duplicate(true)
	rules.choose_path(run, 99)
	check(run == before, "invalid path no mutation")
	rules.choose_reward(run, 0)
	check(run == before, "invalid reward phase no mutation")
	rules.choose_node(run, "leave")
	check(run == before, "invalid node phase no mutation")
	check(not rules.start_run(_meta(), ["keepsake.letter", "keepsake.letter"], 1)["ok"], "duplicate commissions rejected")

func _node_run(type: String, id: String = "") -> Dictionary:
	var run: Dictionary = rules.start_run(rules.new_meta(), ["keepsake.ring"], 2)["run"]
	run["phase"] = "node"
	run["segment"] = 4
	run["current_node"] = {"type": type, "id": id, "star_ids": []}
	return run

func _test_nodes() -> void:
	var run: Dictionary = _node_run("campfire")
	run["hp"] = 20
	rules.choose_node(run, "dry_rope")
	check(run["hp"] == 20 and run["max_hp"] == 44, "max HP is not heal")
	run = _node_run("campfire")
	run["hp"] = 20
	run["keepsakes"] = ["keepsake.ring"]
	run["acquired_segments"]["keepsake.ring"] = 3
	rules.choose_node(run, "rest")
	check(run["hp"] == 32 and run["wishes"]["keepsake.ring"], "rest heals and earlier ring wish")
	run = _node_run("campfire")
	run["current_node"]["star_ids"] = ["keepsake.ring"]
	rules.choose_node(run, "rest")
	check("keepsake.ring" in run["keepsakes"] and not run["wishes"]["keepsake.ring"], "same-fire pickup cannot wish")
	for event: Dictionary in rules.definitions["events"]:
		run = _node_run("event", event["id"])
		for choice: Dictionary in rules.node_choices(run): check(choice.has("text") and choice.has("preview") and choice["preview"].has("hp"), "visible choice outcome " + event["id"])
	run = _node_run("event", "event.echo_mailbox")
	run["deck"].append_array(["card.knock", "card.brace"])
	var before: Dictionary = run.duplicate(true)
	rules.choose_node(run, "shout")
	check(run["phase"] == "replacement" and run["deck"] == before["deck"], "full deck proposes replacement")
	rules.cancel_replacement(run)
	check(run == before, "cancel node replacement exact no mutation")
	run = _node_run("trade")
	run["relics"] = ["relic.lone_glove"]
	rules.prepare_trade(run, "card", 0)
	for id: String in rules.trade_choices(run): check(rules.node_rules.cards[id]["type"] == "attack", "trade same card type")
	var old_size: int = run["deck"].size()
	rules.choose_trade(run, 0)
	check(run["deck"].size() == old_size and run["phase"] == "path", "one trade replacement no currency")
	before = run.duplicate(true)
	rules.choose_trade(run, 0)
	check(run == before, "second trade rejected")

func _test_return() -> void:
	var meta: Dictionary = rules.new_meta()
	var run: Dictionary = rules.start_run(meta, ["keepsake.ring"], 100)["run"]
	run["keepsakes"] = ["keepsake.ring"]
	run["wishes"]["keepsake.ring"] = true
	rules.end_run(run, meta)
	check(run["phase"] == "return" and meta["returned"].is_empty(), "return story precedes grant")
	rules.acknowledge_story(run, meta)
	var checkpoint: Dictionary = rules.safe_checkpoint(run, meta)
	var resumed_meta: Dictionary = JSON.parse_string(JSON.stringify(checkpoint["meta"]))
	var resumed_run: Dictionary = JSON.parse_string(JSON.stringify(checkpoint["run"]))
	rules.acknowledge_story(resumed_run, resumed_meta)
	check(resumed_meta["returned"] == ["keepsake.ring"] and resumed_meta["replica_cards"] == ["card.vow_plus"], "midreturn reload grants plus once")
	var before: Dictionary = resumed_meta.duplicate(true)
	rules.acknowledge_story(resumed_run, resumed_meta)
	check(before == resumed_meta, "repeat story completion idempotent")
	check("departure_choice" in resumed_meta["services"] and "double_commission" in resumed_meta["services"], "first return unlocks services")
	meta = _meta(["keepsake.ring", "keepsake.mianmian", "keepsake.letter"])
	check("spare_rope" in meta["services"], "second return unlocks spare rope")
	var result: Dictionary = rules.start_run(meta, [], 101)
	check(result["ok"], "all returned no boss allows zero-commission retry")
	run = result["run"]
	meta["boss_defeated"] = true
	run["phase"] = "path"
	rules.end_run(run, meta)
	rules.acknowledge_story(run, meta)
	check(rules.pending_story(run).get("id") == "story.ending", "ending follows return sequence")
	rules.acknowledge_story(run, meta)
	check(meta["ending_seen"] and run["phase"] == "hub", "ending completes once")

func _test_rewards() -> void:
	var run: Dictionary = _node_run("battle")
	run["segment"] = 1
	run["phase"] = "reward"
	run["rewards"] = rules._make_rewards(run)
	check(run["rewards"].size() == 3 and run["rewards"][0]["id"] == "relic.lone_glove", "first glove offer guaranteed")
	check(run["rewards"][0]["kind"] == "relic" and run["rewards"][1]["kind"] == "relic" and run["rewards"][2]["kind"] == "card", "ordinary two relic one card")
	var meta: Dictionary = _meta()
	run = rules.start_run(meta, ["keepsake.letter"], 40)["run"]
	rules.choose_departure(run, 0)
	run["current_node"] = {"type": "battle", "id": "enc.t1_a", "star_ids": []}
	run["rewards"] = rules._make_rewards(run)
	check(run["rewards"][2]["id"] == "card.vow_plus", "first card reward unlocked replica")
	for offer: Dictionary in run["rewards"]:
		if offer["kind"] == "relic": check(not offer["id"] in run["relics"], "owned relic excluded")
	run["phase"] = "reward"
	run["deck"].append_array(["card.knock", "card.brace"])
	var before: Dictionary = run.duplicate(true)
	rules.choose_reward(run, 2)
	check(run["phase"] == "replacement" and run["deck"] == before["deck"], "reward replacement pending only")
	rules.cancel_replacement(run)
	check(run == before, "reward cancel exact rollback")
	rules.choose_reward(run, 2)
	rules.replace_card(run, 0)
	check(run["deck"].size() == 12 and run["deck"][0] == "card.vow_plus", "card cap replacement retains size")
	check("card.knock" in run["removed_cards"], "removed card excluded future offers")
	run["current_node"] = {"type": "elite"}
	var elite: Array = rules._make_rewards(run)
	check(elite.size() == 3, "elite three offers")
	for offer: Dictionary in elite: check(offer["kind"] == "relic", "elite only relics")

func _play_battle(state: Dictionary, battle: RefCounted, passive: bool = false) -> Array:
	var bot: RefCounted = PolicyBot.new(rules.definitions)
	var events: Array = []
	var attempts: int = 0
	while state["status"] == "player" and attempts < 20000:
		attempts += 1
		var action: Dictionary = {"type": "end_turn", "keep_index": -1} if passive else bot.choose_action(state, battle)
		events = battle.play_card(state, action["hand_index"], action["target_index"], action["choices"]) if action["type"] == "play_card" else battle.end_turn(state, action.get("keep_index", -1))
	check(attempts < 20000, "battle policy terminates without manufactured win")
	return events

func _test_battle_bridge() -> void:
	var battle: RefCounted = BattleRules.new(rules.definitions)
	var meta: Dictionary = rules.new_meta()
	var run: Dictionary = rules.start_run(meta, ["keepsake.ring"], 777)["run"]
	run["hp"] = 10
	rules.choose_path(run, 0)
	var route_rng: Dictionary = run["rng_states"]["route"].duplicate(true)
	var reward_rng: Dictionary = run["rng_states"]["rewards"].duplicate(true)
	var result: Dictionary = rules.start_battle(run, battle)
	var state: Dictionary = result["state"]
	check(run["rng_states"]["route"] == route_rng and run["rng_states"]["rewards"] == reward_rng, "battle seed independent of route rewards")
	var before: Dictionary = run.duplicate(true)
	rules.complete_battle(run, meta, state, [])
	check(run == before, "nonterminal battle cannot award win")
	var checkpoint: Dictionary = rules.safe_checkpoint(run, meta)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(checkpoint["run"]))
	var replay: Dictionary = rules.start_battle(restored, battle)
	
	check(JSON.parse_string(JSON.stringify(replay["state"])) == JSON.parse_string(JSON.stringify(state)), "battle-start JSON checkpoint exact replay")
	var events: Array = _play_battle(state, battle, true)
	rules.complete_battle(run, meta, state, events)
	check(run["phase"] == "defeat" and run["hp"] == 0, "actual defeat bridge")
	result = rules.retry_battle(run, battle, state)
	state = result["state"]
	check(run["battle_attempt"] == 1 and state["player"]["hp"] == 20 and state["enemies"][0]["max_hp"] == 10, "retry actual half-health floor plus20percent enemy reduction")
	checkpoint = rules.safe_checkpoint(run, meta)
	restored = JSON.parse_string(JSON.stringify(checkpoint["run"]))
	replay = rules.start_battle(restored, battle)
	check(JSON.parse_string(JSON.stringify(replay["state"])) == JSON.parse_string(JSON.stringify(state)), "retry checkpoint keeps assistance and exact shuffle")
	var original_for_replay: Dictionary = state.duplicate(true)
	var replay_events: Array = _play_battle(replay["state"], battle)
	_play_battle(original_for_replay, battle)
	check(JSON.parse_string(JSON.stringify(replay["state"])) == JSON.parse_string(JSON.stringify(original_for_replay)), "JSON restored retry battle deterministic terminal result")
	check(not replay_events.is_empty(), "restored battle emits real terminal event")
	events = _play_battle(state, battle)
	check(state["status"] == "victory", "actual retry victory")
	rules.complete_battle(run, meta, state, events)
	check(run["phase"] == "reward", "actual victory offers rewards")
	before = run.duplicate(true)
	rules.complete_battle(run, meta, state, events)
	check(run == before, "repeated battle completion cannot duplicate grants")

func _test_campaign() -> void:
	var battle: RefCounted = BattleRules.new(rules.definitions)
	var meta: Dictionary = rules.new_meta()
	for trip: int in range(2):
		var missions: Array = rules.available_commissions(meta)
		var run: Dictionary = rules.start_run(meta, missions, 600 + trip)["run"]
		var state: Dictionary = {}
		var guard: int = 0
		while run["phase"] != "hub" and guard < 150:
			guard += 1
			match run["phase"]:
				"departure": rules.choose_departure(run, 0)
				"path":
					var choices: Array = rules.path_choices(run)
					var index: int = 0
					for i: int in range(choices.size()):
						if not choices[i]["star_ids"].is_empty() or not choices[i]["heart_ids"].is_empty(): index = i
					rules.choose_path(run, index)
				"battle_ready": state = rules.start_battle(run, battle)["state"]
				"battle":
					var events: Array = _play_battle(state, battle)
					rules.complete_battle(run, meta, state, events)
				"defeat": state = rules.retry_battle(run, battle, state)["state"]
				"reward": rules.choose_reward(run, 0)
				"node":
					var choices: Array = rules.node_choices(run)
					var choice_id: String = choices[0]["id"]
					for choice: Dictionary in choices:
						if choice.has("when"): choice_id = choice["id"]
					rules.choose_node(run, choice_id, meta)
				"replacement": rules.replace_card(run, 0)
				"return":
					var expected: String = rules.pending_story(run)["id"]
					rules.acknowledge_story(run, meta, expected)
					var snapshot: Dictionary = meta.duplicate(true)
					rules.acknowledge_story(run, meta, expected)
					check(meta == snapshot, "stale story acknowledgement never grants next")
		check(guard < 150 and run["phase"] == "hub", "actual full seven-node expedition reaches hub")
	check(meta["returned"].size() == 3 and meta["boss_defeated"] and meta["ending_seen"], "allthree returns plusactualboss triggersending")
	check(meta["replica_cards"].size() == 3 and meta["memorials"].size() == 3, "exactlythree replicas and memorials")

func _test_drift_and_failure() -> void:
	var meta: Dictionary = _meta()
	var run: Dictionary = rules.start_run(meta, ["keepsake.mianmian", "keepsake.letter"], 914)["run"]
	run["phase"] = "path"
	run["segment"] = 2
	var id: String = run["path"][1][0]["star_ids"][0]
	rules.choose_path(run, 1)
	rules._advance(run)
	var source_index: int = 0
	for i: int in range(run["path"][2].size()):
		if id in run["path"][2][i]["star_ids"]: source_index = i
	rules.choose_path(run, source_index)
	rules._collect_keepsakes(run)
	rules._advance(run)
	check(run["wish_missed"].get(id, false), "missed event opportunity stays unavailable after delayed pickup")
	for choice: Dictionary in rules.path_choices(run): check(not id in choice["heart_ids"], "no stale heart after missed opportunity")
	# Repeatedly skip a ring through the final drift boundary.
	run = rules.start_run(rules.new_meta(), ["keepsake.ring"], 915)["run"]
	run["segment"] = 4
	rules.choose_path(run, 1)
	rules.choose_node(run, "rest")
	check("keepsake.ring" in run["path"][4][0]["star_ids"], "missed elite star drifts to fifth segment")
	rules.choose_path(run, 1)
	check("keepsake.ring" in run["path"][6][0]["star_ids"], "fifth missed star falls to boss not fire")
	# Obtained keepsakes survive failure and return in acquisition order.
	meta = _meta()
	run = rules.start_run(meta, ["keepsake.mianmian", "keepsake.letter"], 916)["run"]
	run["phase"] = "defeat"
	run["keepsakes"] = ["keepsake.letter", "keepsake.mianmian"]
	run["wishes"] = {"keepsake.letter": false, "keepsake.mianmian": true}
	rules.end_run(run, meta, "defeat")
	check(run["keepsakes"].size() == 2, "failure keeps already obtained keepsakes")
	rules.acknowledge_story(run, meta)
	check(rules.pending_story(run)["keepsake_id"] == "keepsake.letter", "return follows acquisition order not commission order")
	rules.acknowledge_story(run, meta)
	check(rules.pending_story(run)["keepsake_id"] == "keepsake.mianmian", "second acquired returns second")
	rules.acknowledge_story(run, meta)
	check(meta["returned"] == ["keepsake.ring", "keepsake.letter", "keepsake.mianmian"], "all acquired on failure permanently returned")
	check("card.deliver" in meta["replica_cards"] and "card.whisper_plus" in meta["replica_cards"], "normal and plus grant exactly according to wish")
	# Actual spare rope preview and state agree outside battle too.
	run = _node_run("event", "event.mud_glint")
	run["hp"] = 4
	run["spare_rope_available"] = true
	var before: Dictionary = run.duplicate(true)
	var preview: Dictionary = rules.node_choices(run)[0]["preview"]
	check(run == before and preview["hp"] == 1 and preview["spare_rope_used"], "node preview exact spare-rope save without mutation")
	rules.choose_node(run, "reach", rules.new_meta())
	check(run["hp"] == 1 and run["spare_rope_used"] and run["next_battle"]["start_guard"] == 10, "node spare rope once-per-run state")
	# Trade offers cannot be rerolled by reopening the same give item.
	run = _node_run("trade")
	rules.prepare_trade(run, "card", 0)
	before = run.duplicate(true)
	rules.prepare_trade(run, "card", 0)
	check(run == before, "reopening same trade cannot reroll offers")
	# Aunt event may appear only during run 2/3 and at most once per save.
	meta = rules.new_meta()
	for number: int in range(1, 5):
		run = rules.start_run(meta, ["keepsake.ring"], 919 + number)["run"]
		for row: Array in run["path"]:
			for node: Dictionary in row:
				if node["id"] == "event.aunt_mark": check(number in [2, 3] and meta["once_events"].get("event.aunt_mark", false), "aunt marker uses save-once run window")
	# Empty commissioned retry traverses a real full expedition and ends demo.
	meta = _meta(["keepsake.ring", "keepsake.mianmian", "keepsake.letter"])
	run = rules.start_run(meta, [], 920)["run"]
	var battle: RefCounted = BattleRules.new(rules.definitions)
	var state: Dictionary = {}
	var guard: int = 0
	while run["phase"] != "hub" and guard < 150:
		guard += 1
		match run["phase"]:
			"departure": rules.choose_departure(run, 0)
			"path": rules.choose_path(run, 0)
			"battle_ready": state = rules.start_battle(run, battle)["state"]
			"battle": rules.complete_battle(run, meta, state, _play_battle(state, battle))
			"defeat": state = rules.retry_battle(run, battle, state)["state"]
			"reward": rules.choose_reward(run, 0)
			"node": rules.choose_node(run, rules.node_choices(run)[0]["id"], meta)
			"replacement": rules.replace_card(run, 0)
			"return": rules.acknowledge_story(run, meta)
	check(guard < 150 and meta["boss_defeated"] and meta["ending_seen"], "actual zero-commission boss retry reaches ending without deadlock")
	check(meta["replica_cards"].size() == 3 and meta["memorials"].size() == 3, "boss-only retry cannot duplicate return grants")

func _test_all_event_outcomes() -> void:
	var cases: Array = [
		["event.lonely_bench", "sit", "heal", 8],
		["event.lonely_bench", "friend", "friend", 1],
		["event.echo_mailbox", "shout", "card", "attack"],
		["event.mud_glint", "reach", "mud", 5],
		["event.laundry_granny", "help", "start_guard", 8],
		["event.laundry_granny", "ask", "card", "guard"],
		["event.soap_tub", "soak", "heal", 12],
		["event.soap_tub", "bubble", "bubble", 1],
		["event.aunt_mark", "follow", "max_hp", 5]
	]
	for test: Array in cases:
		var run: Dictionary = _node_run("event", test[0])
		run["hp"] = 20
		var before: Dictionary = run.duplicate(true)
		var choices: Array = rules.node_choices(run)
		check(run == before, "event previews never mutate " + test[0])
		var preview: Dictionary = {}
		for choice: Dictionary in choices:
			if choice["id"] == test[1]: preview = choice["preview"]
		var events: Array = rules.choose_node(run, test[1])
		check(run["hp"] == preview["hp"] and run["max_hp"] == preview["max_hp"], "actual outcome agrees with preview " + test[0])
		match test[2]:
			"heal": check(run["hp"] == 20 + int(test[3]), "event heal exact")
			"friend": check(run["next_battle"]["extra_enemies"] == ["enemy.lonely_sock"] and run["next_battle"]["extra_relic_rewards"] == 1, "friend adds enemy plus earned-victory bonus")
			"card": check(run["deck"].size() == 11 and rules.node_rules.cards[run["deck"][-1]]["type"] == test[3], "event card matches promised type")
			"mud": check(run["hp"] == 15 and run["relics"].size() == 1, "mud trades exact HP for unowned relic")
			"start_guard": check(run["next_battle"]["start_guard"] == 8, "granny deferred battle guard")
			"bubble": check(run["next_battle"]["cancel_first_attack"], "bubble first attack protection")
			"max_hp": check(run["max_hp"] == 45 and run["hp"] == 20, "aunt event maximum-only bonus")
		if test[1] in ["ask", "follow"]:
			var story: bool = false
			for event: Dictionary in events:
				if event["type"] == "story": story = true
			check(story, "story event emits narrative request")
	for data: Array in [["event.lonely_bench", "mianmian", "keepsake.mianmian", 8], ["event.echo_mailbox", "read_letter", "keepsake.letter", 6]]:
		var run: Dictionary = _node_run("event", data[0])
		run["hp"] = 20
		run["keepsakes"] = [data[2]]
		run["acquired_segments"][data[2]] = 2
		rules.choose_node(run, data[1])
		check(run["wishes"][data[2]] and run["hp"] == 20 + int(data[3]), "visible conditional wish choice completes with promised heal")

func _test_path_hint_identity() -> void:
	var orderings: Dictionary = {}
	var seen_events: Dictionary = {}
	var special: Dictionary = rules.definitions["path"][0]["special_hints"]
	for seed_value: int in range(64):
		var meta: Dictionary = _meta()
		meta["runs_started"] = 1
		var run_state: Dictionary = rules.start_run(meta, ["keepsake.mianmian", "keepsake.letter"], seed_value)["run"]
		for row: Array in run_state["path"]:
			for node: Dictionary in row:
				if node["type"] != "event": continue
				var event: Dictionary = rules.node_rules.events_by_id[node["id"]]
				var expected: String = str(special.get(node["id"], event["name"]))
				seen_events[node["id"]] = true
				check(node["hint"] == expected, "event sign hint belongs to its actual event, including ordinary paths")
				if node["wish_ids"].is_empty(): continue
				var id: String = node["wish_ids"][0]
				var segment: int = int(node["segment"])
				if segment == 3: orderings[id] = true
				run_state["phase"] = "path"
				run_state["segment"] = segment
				run_state["keepsakes"] = [id]
				run_state["acquired_segments"][id] = segment - 1
				run_state["wish_missed"][id] = false
				var before: Dictionary = run_state.duplicate(true)
				for visible: Dictionary in rules.path_choices(run_state):
					if visible["id"] == node["id"]:
						check(visible["hint"] == expected and id in visible["heart_ids"], "both wish-order variants display the actual heart event hint")
				check(run_state == before, "hint presentation preserves route state and RNG")
				# A missed wish loses its heart, never its event identity or hint.
				run_state["wish_missed"][id] = true
				for visible: Dictionary in rules.path_choices(run_state):
					if visible["id"] == node["id"]:
						check(visible["hint"] == expected and visible["heart_ids"].is_empty(), "non-heart fallback keeps the same truthful event hint")
				# Simulate a previously saved type-wide hint without touching a file.
				node["hint"] = special["event.echo_mailbox"] if node["id"] != "event.echo_mailbox" else rules.node_rules.events_by_id["event.lonely_bench"]["name"]
				before = run_state.duplicate(true)
				for visible: Dictionary in rules.path_choices(run_state):
					if visible["id"] == node["id"]: check(visible["hint"] == expected, "legacy saved hint corrected in read-only path view")
				check(run_state == before, "legacy hint correction does not rewrite active save data")
	check(orderings.has("keepsake.mianmian") and orderings.has("keepsake.letter"), "hint regression covers both 2-to-3 and 4-to-5 wish orderings")
	check(seen_events.size() >= 5, "generated hint regression includes ordinary non-heart events")
	# Exercise every content fallback directly, independent of route eligibility.
	# In particular, the save-once aunt event need not be rolled by these seeds.
	for event: Dictionary in rules.definitions["events"]:
		var run_state: Dictionary = rules.start_run(_meta(), ["keepsake.mianmian", "keepsake.letter"], 4242)["run"]
		run_state["phase"] = "path"
		run_state["segment"] = 3
		run_state["path"][2][0] = {"id": event["id"], "type": "event", "segment": 3, "hint": special["event.echo_mailbox"], "star_ids": [], "wish_ids": [], "heart_ids": []}
		var before: Dictionary = run_state.duplicate(true)
		var visible: Dictionary = rules.path_choices(run_state)[0]
		check(visible["hint"] == str(special.get(event["id"], event["name"])), "all six event definitions use their own explicit-or-name hint")
		check(visible["heart_ids"].is_empty() and run_state == before, "ordinary fallback corrects only display, never save bytes")

func _test_aunt_event_eligibility() -> void:
	var numeric_json: Array = JSON.parse_string("[2,3]")
	check(numeric_json[0] is float, "eligibility regression uses actual JSON-loaded numeric values")
	check(not rules.path_rules._run_number_allowed(1, numeric_json), "aunt event excludes run one")
	check(rules.path_rules._run_number_allowed(2, numeric_json), "aunt event allows JSON run two")
	check(rules.path_rules._run_number_allowed(3, numeric_json), "aunt event allows JSON run three")
	check(not rules.path_rules._run_number_allowed(4, numeric_json), "aunt event excludes run four")
	var integer_tables: Dictionary = rules.definitions.duplicate(true)
	for event: Dictionary in integer_tables["events"]:
		if event["id"] == "event.aunt_mark": event["run_numbers"] = [2, 3]
	var integer_rules: RefCounted = RunRules.new(integer_tables)
	var appeared: Dictionary = {1: false, 2: false, 3: false, 4: false}
	var repeated_after_save: int = 0
	for number: int in range(1, 5):
		for seed_value: int in range(32):
			var meta: Dictionary = _meta()
			meta["runs_started"] = number - 1
			var int_meta: Dictionary = meta.duplicate(true)
			var previously_excluded_meta: Dictionary = meta.duplicate(true)
			previously_excluded_meta["once_events"]["event.aunt_mark"] = true
			var run_state: Dictionary = rules.start_run(meta, ["keepsake.mianmian", "keepsake.letter"], seed_value)["run"]
			var int_run: Dictionary = integer_rules.start_run(int_meta, ["keepsake.mianmian", "keepsake.letter"], seed_value)["run"]
			check(run_state["path"] == int_run["path"] and run_state["rng_states"] == int_run["rng_states"], "JSON and integer eligibility use the identical random draw protocol")
			var previously_excluded_run: Dictionary = rules.start_run(previously_excluded_meta, ["keepsake.mianmian", "keepsake.letter"], seed_value)["run"]
			var same_topology: bool = true
			for row_index: int in range(run_state["path"].size()):
				for node_index: int in range(run_state["path"][row_index].size()):
					for key: String in ["type", "segment", "tier", "star_ids", "wish_ids"]:
						if run_state["path"][row_index][node_index][key] != previously_excluded_run["path"][row_index][node_index][key]: same_topology = false
			check(same_topology, "restored event eligibility preserves seeded topology and mission placement")
			if number in [1, 4]:
				check(run_state["path"] == previously_excluded_run["path"] and run_state["rng_states"] == previously_excluded_run["rng_states"], "out-of-window routes preserve all seeded outputs")
			else:
				check(int(run_state["rng_states"]["route"]["draws"]) == int(previously_excluded_run["rng_states"]["route"]["draws"]) + 1, "eligible unseen aunt adds only its one shuffle draw")
			var found: int = 0
			var all_events: Dictionary = {}
			var event_count: int = 0
			for row: Array in run_state["path"]:
				for node: Dictionary in row:
					if node["type"] == "event":
						event_count += 1
						all_events[node["id"]] = true
					if node["id"] == "event.aunt_mark": found += 1
			check(event_count == all_events.size() and found <= 1, "restored aunt eligibility never duplicates an event within a route")
			if number in [1, 4]: check(found == 0, "aunt generation respects excluded run window")
			if found > 0:
				appeared[number] = true
				check(meta["once_events"].get("event.aunt_mark", false), "offered aunt event records the save-once marker")
				var next_meta: Dictionary = JSON.parse_string(JSON.stringify(meta))
				# Keep the next generation inside the eligible window to verify
				# the persisted once marker, rather than merely passing run four.
				next_meta["runs_started"] = 2
				var next_run: Dictionary = rules.start_run(next_meta, ["keepsake.mianmian", "keepsake.letter"], seed_value + 1000)["run"]
				for row: Array in next_run["path"]:
					for node: Dictionary in row:
						if node["id"] == "event.aunt_mark": repeated_after_save += 1
	check(appeared[2] and appeared[3] and not appeared[1] and not appeared[4], "aunt event is reachable on seeded run two and three, never one or four")
	check(repeated_after_save == 0, "JSON-restored save-once aunt event cannot recur")
