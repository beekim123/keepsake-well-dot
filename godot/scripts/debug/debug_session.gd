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
	# These inputs are an explicit QA campaign, separate from manual progress.
	app.meta = app.run_rules.new_meta()
	app.run = {}
	app.settings["intro_seen"] = false
	app._debug_seed = 147
	app._show_title()
	await _shot(app, folder, "d1-title")
	app._title_continue()
	await _shot(app, folder, "d1-intro")
	app._skip_story()
	await _shot(app, folder, "d1-notebook")
	app._continue_game()
	await _shot(app, folder, "d1-hut")
	app._show_commissions()
	await _shot(app, folder, "d1-commissions")
	app._show_prepare()
	await _shot(app, folder, "d1-prepare")
	app._start_run()
	await _shot(app, folder, "d1-path")
	app._choose_path(0)
	await _shot(app, folder, "d1-battle")
	app._battle_view.select_card(0)
	await _shot(app, folder, "d1-battle-preview")
	app._battle_view.cancel_selection()
	var bot: RefCounted = Bot.new(app.get_node("/root/ContentCatalog").definitions())
	var captured: Dictionary = {}
	for step: int in range(1800):
		if app.screen in ["reward", "node", "defeat", "story", "reveal"] and not captured.has(app.screen):
			captured[app.screen] = true
			await _shot(app, folder, "d1-" + app.screen)
		if app.screen == "hut":
			await _shot(app, folder, "d1-hut-returned")
			break
		match app.screen:
			"battle": app._battle_command(bot.choose_action(app.battle, app.battle_rules))
			"defeat": app._retry_battle()
			"reward": app._choose_reward(bot.choose_reward(app.run_rules.reward_choices(app.run), app.run))
			"path":
				var choices: Array = app.run_rules.path_choices(app.run)
				var pick: int = 0
				for index: int in range(choices.size()):
					if not choices[index].get("star_ids", []).is_empty() or not choices[index].get("heart_ids", []).is_empty():
						pick = index
				app._choose_path(pick)
			"node": app._choose_node(str(app.run_rules.node_choices(app.run)[0]["id"]))
			"replacement": app._replace_card(0)
			"reveal": app._route_phase()
			"story": app._skip_story()
			_: break
		await app.get_tree().process_frame
	# A clearly segregated battle fixture stresses eight hands/four enemies.
	var fixture: Dictionary = {"hp": 40, "max_hp": 40, "deck": app.get_node("/root/ContentCatalog").table("meta")[0]["starter_deck"], "relics": ["relic.crooked_compass", "relic.open_ink"], "keepsakes": []}
	app.battle = app.battle_rules.start({"id": "debug.four_enemies", "enemies": ["boss.sock_snake", "enemy.sock_kid", "enemy.sock_kid", "enemy.sock_kid"]}, fixture, 247)["state"]
	app._show_battle()
	await _shot(app, folder, "d1-fixture-four-enemies-eight-cards")
	print("D1_SCREENSHOTS: authorized GUI capture; real campaign plus explicitly named stress fixture")
	app.get_node("/root/AudioService").stop_all()
	await app.get_tree().create_timer(0.15).timeout
	app.get_tree().quit(0)

func _shot(app: Control, folder: String, name: String) -> void:
	await app.get_tree().create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var result: Error = app.get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png"))
	if result != OK:
		push_error("D1 screenshot failed: " + name)
		app.get_tree().quit(1)
