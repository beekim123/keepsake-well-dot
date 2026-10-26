extends RefCounted
## Explicit reproducible QA fixtures. Never loaded in release; the app routes
## all debug flags to user://d1-debug.json, never the human save.
const Bot = preload("res://scripts/core/policy_bot.gd")

func apply_arguments(app: Control, args: PackedStringArray) -> void:
	if not OS.is_debug_build():
		return
	var jump: String = ""
	var gifts: Array[String] = []
	for argument: String in args:
		if argument.begins_with("--jump="):
			jump = argument.trim_prefix("--jump=")
		elif argument.begins_with("--give="):
			gifts.append(argument.trim_prefix("--give="))
		elif argument == "--meta=returned_2":
			app.meta = app.run_rules.new_meta()
			for id: String in ["keepsake.ring", "keepsake.mianmian"]:
				app.run_rules.meta_rules.grant_return(app.meta, app.get_node("/root/ContentCatalog").entry(id), true)
	if jump.is_empty() and gifts.is_empty():
		return
	app.selected_commissions = app.run_rules.available_commissions(app.meta).slice(0, 1)
	app._start_run()
	if app.run.get("phase") == "departure":
		app.run_rules.choose_departure(app.run, 0)
	for id: String in gifts:
		if not app.get_node("/root/ContentCatalog").has_entry(id):
			continue
		if id.begins_with("relic.") and not id in app.run["relics"]:
			app.run["relics"].append(id)
		elif id.begins_with("card.") and app.run["deck"].size() < 12:
			app.run["deck"].append(id)
		elif id.begins_with("keepsake.") and not id in app.run["keepsakes"]:
			app.run["keepsakes"].append(id)
			app.run["wishes"][id] = false
			app.run["acquired_segments"][id] = 1
	if not jump.is_empty():
		app.run["segment"] = 7 if jump == "boss" else clampi(int(jump), 1, 7)
	app._route_phase()
	if jump == "boss":
		app._choose_path(0)

var _captured: Array[String] = []
var _capture_failed: bool = false

func capture(app: Control) -> void:
	if not OS.is_debug_build():
		return
	if DisplayServer.get_name() == "headless":
		push_error("D1 screenshots require an authorized visible GUI launch")
		app.get_tree().quit(1)
		return
	var folder: String = ProjectSettings.globalize_path("res://../artifacts/screenshots")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		push_error("D1 screenshot folder unavailable")
		app.get_tree().quit(1)
		return
	_capture_failed = false
	var result: Dictionary = await play_campaign(app, _capture_stage.bind(app, folder))
	if not result.get("ok", false) or _capture_failed:
		push_error("D1 actual capture campaign failed: " + JSON.stringify(result))
		app.get_tree().quit(1)
		return
	# Only this final, explicitly named stress screenshot uses a synthetic
	# encounter/deck modifier fixture. Campaign receipts are already final.
	var fixture: Dictionary = {"hp": 40, "max_hp": 40, "deck": app.get_node("/root/ContentCatalog").table("meta")[0]["starter_deck"], "relics": ["relic.crooked_compass", "relic.open_ink"], "keepsakes": []}
	app.battle = app.battle_rules.start({"id": "debug.four_enemies", "enemies": ["boss.sock_snake", "enemy.sock_kid", "enemy.sock_kid", "enemy.sock_kid"]}, fixture, 247)["state"]
	app.run = {"current_node": {"type": "boss"}}
	app._show_battle()
	await _capture_stage("d1-fixture-four-enemies-eight-cards", app, folder)
	app.run = {}
	app.battle = {}
	app._show_hut()
	result["fixture_captures"] = ["d1-fixture-four-enemies-eight-cards"]
	var receipt: FileAccess = FileAccess.open(folder.path_join("d1-capture-receipt.json"), FileAccess.WRITE)
	if receipt == null:
		push_error("D1 capture receipt could not be written")
		app.get_tree().quit(1)
		return
	receipt.store_string(JSON.stringify(result, "\t") + "\n")
	receipt.close()
	print("D1_SCREENSHOTS: " + JSON.stringify(result))
	app.get_node("/root/AudioService").stop_all()
	await app.get_tree().create_timer(0.15).timeout
	app.get_tree().quit(1 if _capture_failed else 0)

func play_campaign(app: Control, on_stage: Callable = Callable()) -> Dictionary:
	# This runner can also be regression-tested headlessly. It never captures
	# headless pixels, never loads the human save, and never manufactures wins.
	if not OS.is_debug_build() or app._save_path == "user://save.json":
		return {"ok": false, "error": "requires_isolated_debug_save"}
	_captured.clear()
	var begun: int = Time.get_ticks_msec()
	var seeds: Array[int] = [147, 148, 149, 150, 151]
	var stories: Array = []
	var nodes: Array[String] = []
	var returns_seen: Array = []
	var commands: int = 0
	# This is the sole fresh-QA-state reset. Every subsequent permanent change
	# is produced by RunRules acknowledging an actually earned return/story.
	app.meta = app.run_rules.new_meta()
	app.run = {}
	app.battle = {}
	app.selected_commissions = []
	app.settings["intro_seen"] = false
	app._debug_seed = seeds[0]
	app._show_title()
	await _stage("d1-title", on_stage)
	app._title_continue()
	while app.screen == "story":
		await _stage("d1-story-intro-page-%02d" % (int(app._story.index) + 1), on_stage)
		if app._story.index == 0:
			await _stage("d1-intro", on_stage)
		app._next_story()
	await _stage("d1-notebook", on_stage)
	app._continue_game()
	await _stage("d1-hut", on_stage)
	app._show_commissions()
	await _stage("d1-commissions", on_stage)
	app._show_prepare()
	await _stage("d1-prepare", on_stage)
	app._start_run()
	await _stage("d1-path", on_stage)
	app._choose_path(0)
	await _stage("d1-battle", on_stage)
	app._battle_view.select_card(0)
	await _stage("d1-battle-preview", on_stage)
	app._battle_view.cancel_selection()
	# Deliberate, documented QA input: end turns without defending. This is a
	# real defeat followed by the real retry button, not a forced HP fixture.
	for ignored: int in range(60):
		if app.screen != "battle":
			break
		app._battle_command({"type": "end_turn", "keep_index": -1})
		commands += 1
		await app.get_tree().process_frame
	if app.screen != "defeat":
		return {"ok": false, "error": "tutorial_did_not_reach_actual_defeat", "screen": app.screen}
	await _stage("d1-defeat-actual-tutorial", on_stage)
	app._retry_battle()
	await _stage("d1-retry-actual-tutorial", on_stage)
	var bot: RefCounted = Bot.new(app.get_node("/root/ContentCatalog").definitions())
	var trips: int = 1
	for step: int in range(2400):
		if app.screen == "hut":
			returns_seen = app.meta["returned"].duplicate()
			await _stage("d1-hut-after-trip-%d" % trips, on_stage)
			if app.meta.get("ending_seen", false):
				app._show_book()
				await _stage("d1-notebook-locked-next-layer", on_stage)
				app._continue_game()
				var complete: bool = app.meta["returned"].size() == 3 and app.meta["boss_defeated"] and app.meta["ending_seen"]
				return {"ok": complete, "stage": "actual-legal-campaign", "trips": trips, "seed_sequence": seeds.slice(0, trips), "commands": commands, "elapsed_seconds": (Time.get_ticks_msec() - begun) / 1000.0, "returned": returns_seen, "replica_cards": app.meta["replica_cards"].duplicate(), "boss_defeated": app.meta["boss_defeated"], "ending_seen": app.meta["ending_seen"], "stories": stories, "node_types": nodes, "campaign_captures": _captured.duplicate(), "intentional_test_inputs": ["tutorial ended turns without defense, then used actual assisted retry"]}
			if trips >= seeds.size():
				return {"ok": false, "error": "campaign_incomplete_after_seed_sequence", "returned": returns_seen, "meta": app.meta.duplicate(true)}
			app.selected_commissions = app.run_rules.available_commissions(app.meta).slice(0, 2)
			app._debug_seed = seeds[trips]
			app._show_commissions()
			await _stage("d1-commissions-trip-%d" % (trips + 1), on_stage)
			app._show_prepare()
			await _stage("d1-prepare-trip-%d" % (trips + 1), on_stage)
			app._start_run()
			trips += 1
			continue
		var before_wishes: Dictionary = app.run.get("wishes", {}).duplicate(true)
		var before_items: Array = app.run.get("keepsakes", []).duplicate()
		match app.screen:
			"departure":
				await _stage("d1-departure-choice-trip-%d" % trips, on_stage)
				app._choose_departure(0)
			"battle":
				var encounter: String = str(app.battle.get("encounter", {}).get("id", "battle")).replace(".", "-")
				await _stage("d1-battle-" + encounter, on_stage)
				for warning: Dictionary in app.battle_rules.forecast(app.battle).get("warnings", []):
					await _stage("d1-boss-warning-%d" % int(warning.get("turns", 0)), on_stage)
				var action: Dictionary = bot.choose_action(app.battle, app.battle_rules)
				if action.is_empty():
					return {"ok": false, "error": "no_legal_battle_action", "encounter": encounter}
				app._battle_command(action)
				commands += 1
			"defeat":
				await _stage("d1-defeat-trip-%d-segment-%d" % [trips, int(app.run["segment"])], on_stage)
				if int(app.run.get("battle_attempt", 0)) >= 6:
					return {"ok": false, "error": "retry_guard", "run": app.run.duplicate(true)}
				app._retry_battle()
				await _stage("d1-retry-trip-%d-segment-%d" % [trips, int(app.run["segment"])], on_stage)
			"reward":
				await _stage("d1-reward-trip-%d-segment-%d" % [trips, int(app.run["segment"])], on_stage)
				app._choose_reward(bot.choose_reward(app.run_rules.reward_choices(app.run), app.run))
			"path":
				await _stage("d1-path-trip-%d-segment-%d" % [trips, int(app.run["segment"])], on_stage)
				app._choose_path(_path_pick(app.run_rules.path_choices(app.run)))
			"node":
				var node: Dictionary = app.run["current_node"]
				if not str(node["type"]) in nodes:
					nodes.append(str(node["type"]))
				await _stage("d1-node-" + str(node["id"]).replace(".", "-"), on_stage)
				if node["type"] == "trade":
					app._prepare_trade("card", 0)
					await _stage("d1-trade-offers-trip-%d" % trips, on_stage)
					app._choose_trade(0)
				else:
					app._choose_node(_node_pick(app.run_rules.node_choices(app.run)))
			"replacement":
				await _stage("d1-deck-replacement", on_stage)
				app._replace_card(0)
			"reveal": app._route_phase()
			"story":
				var story: Dictionary = app._story_record.duplicate(true)
				if not stories.has(story):
					stories.append(story)
				await _stage("d1-" + str(story["id"]).replace(".", "-") + "-page-%02d" % (int(app._story.index) + 1), on_stage)
				app._next_story()
			_: return {"ok": false, "error": "unexpected_screen", "screen": app.screen}
		if app.screen == "reveal":
			for id: String in app.run.get("keepsakes", []):
				if not id in before_items:
					await _stage("d1-keepsake-" + id.replace(".", "-"), on_stage)
			for id: String in app.run.get("wishes", {}):
				if app.run["wishes"][id] and not before_wishes.get(id, false):
					await _stage("d1-wish-" + id.replace(".", "-"), on_stage)
		await app.get_tree().process_frame
	return {"ok": false, "error": "campaign_command_guard", "screen": app.screen, "trips": trips, "commands": commands}

func _path_pick(choices: Array) -> int:
	var selected: int = 0
	var best: int = -1
	for index: int in range(choices.size()):
		var node: Dictionary = choices[index]
		var score: int = node.get("star_ids", []).size() * 20 + node.get("heart_ids", []).size() * 10
		if node["type"] == "campfire": score += 4
		if node["type"] == "event": score += 2
		if score > best:
			best = score
			selected = index
	return selected

func _node_pick(choices: Array) -> String:
	var selected: String = str(choices[0]["id"])
	var best: int = -999
	for choice: Dictionary in choices:
		var score: int = int(choice.get("preview", {}).get("hp", 0))
		for op: Dictionary in choice.get("ops", []):
			if op["op"] == "complete_wish": score += 100
		if choice["id"] == "rest": score += 1
		if score > best:
			best = score
			selected = str(choice["id"])
	return selected

func _stage(name: String, callback: Callable) -> void:
	if name in _captured:
		return
	_captured.append(name)
	if callback.is_valid():
		await callback.call(name)

func _capture_stage(name: String, app: Control, folder: String) -> void:
	await app.get_tree().create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var result: Error = app.get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))
	if result != OK:
		_capture_failed = true
		push_error("D1 screenshot failed: " + name)
