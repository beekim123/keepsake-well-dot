extends RefCounted
## Real controller QA. Captures come from a visible Godot viewport only.
## All saves use d2-debug.json; fixture battles are explicitly reported separately.
const Bot = preload("res://scripts/core/policy_bot.gd")
var shots: Array[String] = []
var events: Array = []
var capture_dir: String = ""
var app: Control
var bot: RefCounted

func run(controller: Control, folder: String = "") -> Dictionary:
	app = controller
	capture_dir = folder
	if app._save_path != "user://d2-debug.json": return {"ok": false, "error": "isolated_save_required"}
	if not folder.is_empty() and DisplayServer.get_name() == "headless": return {"ok": false, "error": "visible_window_required"}
	if not folder.is_empty(): DirAccess.make_dir_recursive_absolute(folder)
	bot = Bot.new(app.get_node("/root/ContentCatalog").definitions())
	app.meta = app.run_rules.new_meta()
	app.run = {}
	app.battle = {}
	app.settings = {"window_scale": 3}
	app._tutorial_state = {}
	app._debug_seed = 147
	app.presentation_fast = true
	if not folder.is_empty(): app.get_window().size = Vector2i(1920,1080)
	app._start_opening()
	app._launch_tutorial()
	await frames()
	var first_bind_turn: int = -1
	var stacked: bool = false
	var retained: bool = false
	var shaken: bool = false
	var pairs: int = 0
	var commands: int = 0
	for step: int in range(700):
		match app.screen:
			"r2_battle":
				var stage: Node = app._remedy_scene
				if stage.busy or stage.state.is_empty(): await frames(); continue
				var lesson: String = str(stage.state.get("tutorial", {}).get("id", ""))
				await shot("normal" if lesson == "tutorial.wet_sock" else "tutorial-two-enemies")
				var action: Dictionary = _tutorial_action(stage)
				var simulated: Dictionary = stage.state.duplicate(true)
				var projected: Array = stage.rules.apply_action(simulated,action)
				if projected.any(func(e: Dictionary) -> bool: return e.get("type") == "bind") and lesson == "tutorial.wet_sock" and first_bind_turn < 0: first_bind_turn = int(stage.state["turn"])
				var pairing: bool = projected.any(func(e: Dictionary) -> bool: return e.get("type") == "pair_formed")
				if pairing and not capture_dir.is_empty(): stage.instant_presentation = false
				if action.get("type") == "play_card" and action.get("choices", {}).has("second_target"):
					stage._view.select_card(int(action["hand_index"]))
					stage._view._enemy_clicked(int(action["target_index"]))
					await shot("second-target-selection")
					stage._view._enemy_clicked(int(action["choices"]["second_target"]))
				else: stage._view._commit(action)
				commands += 1
				events.append({"screen": "tutorial", "lesson": lesson, "action": action, "events": projected})
				if pairing:
					pairs += 1
					if not capture_dir.is_empty():
						await app.get_tree().create_timer(0.42).timeout
						await shot("pair-departure")
				while is_instance_valid(stage) and stage.busy: await frames()
				await frames()
				if app.screen == "r2_battle" and is_instance_valid(app._remedy_scene):
					var current: Node = app._remedy_scene
					if projected.any(func(e: Dictionary) -> bool: return e.get("type") == "tie_made"): await shot("tied-enemies")
					if lesson == "tutorial.wet_sock" and first_bind_turn == int(current.state.get("turn", 0)): await shot("bind-forecast-5-to-1")
					if lesson == "tutorial.wet_sock" and int(current.state["enemies"][0]["binds"]) == 8:
						stacked = true
						await shot("tutorial-stack-eight")
					if lesson == "tutorial.wet_sock" and int(current.state["turn"]) == 3 and int(current.state["enemies"][0]["binds"]) == 3:
						retained = true
						await shot("tutorial-retained-three")
					if lesson == "tutorial.wet_sock" and projected.any(func(e: Dictionary) -> bool: return e.get("type") == "enemy_shake_off"):
						shaken = true
						await shot("tutorial-shake-off")
			"battle":
				var action: Dictionary = bot.choose_action(app.battle, app.battle_rules)
				app._battle_view._commit(action)
				commands += 1
			"path":
				await shot("route-back")
				app._path_card_clicked(0)
				await shot("route-front")
				app._path_card_clicked(0)
			"reward":
				await shot("thanks" if app.run.get("reward_kind") == "thanks" else "card-reward")
				app._choose_reward(bot.choose_reward(app.run_rules.reward_choices(app.run),app.run))
			"replacement": app._replace_card(bot.choose_replacement(app.run))
			"node":
				if app.run.get("current_node", {}).get("type") == "campfire": await shot("rest-lantern")
				var choices: Array = app.run_rules.node_choices(app.run)
				if choices.is_empty(): return {"ok": false, "error": "empty_node"}
				app._choose_node(str(choices[0]["id"]))
			"story": app._next_story()
			"reveal", "stamp": app._route_phase()
			"defeat": return {"ok": false, "error": "first_trip_defeat", "commands": commands}
			"hut":
				return {"ok": stacked and retained and shaken and first_bind_turn > 0 and first_bind_turn <= 3 and pairs > 0 and "keepsake.ring" in app.meta.get("returned", []), "stacked_eight": stacked, "retained_three": retained, "shake_off_seen": shaken, "control_policy": "Follow tutorial_status.guide; target healthier end for pair_hits; battle bot only in free play", "first_bind_turn": first_bind_turn, "tutorial_pairs": pairs, "commands": commands, "screen": app.screen, "shots": shots.duplicate(), "returned": app.meta["returned"].duplicate(), "events": events.duplicate(true), "save_path": app._save_path, "window_size": str(app.get_window().size)}
			_: return {"ok": false, "error": "unexpected_screen", "screen": app.screen}
		await frames()
	return {"ok": false, "error": "flow_guard", "screen": app.screen}

func frames(count: int = 2) -> void:
	for ignored: int in range(count): await app.get_tree().process_frame

func _tutorial_action(stage: Node) -> Dictionary:
	var status: Dictionary = stage.rules.tutorial_status(stage.state)
	var guide: String = str(status.get("guide", "none"))
	var legal: Array = stage.rules.legal_actions(stage.state)
	if guide == "end_turn":
		for action: Dictionary in legal:
			if action["type"] == "end_turn": return action
	elif guide in ["drag_enemy", "drag_board", "pair_hits"]:
		var alive: Array = stage.rules.living_slots(stage.state)
		var target: int = int(alive[0]) if not alive.is_empty() else -1
		if guide == "pair_hits":
			for slot: int in alive:
				if int(stage.state["enemies"][slot]["hp"]) > int(stage.state["enemies"][target]["hp"]): target = slot
		for action: Dictionary in legal:
			if action["type"] == "play_card" and int(action.get("target_index",-1)) in [-1,target]: return action
	return bot.choose_action(stage.state,stage.rules)

func shot(id: String, repeat: bool = false) -> void:
	if capture_dir.is_empty() or (id in shots and not repeat): return
	await frames()
	await RenderingServer.frame_post_draw
	var image: Image = app.get_viewport().get_texture().get_image()
	var result: Error = image.save_png(capture_dir.path_join(id + ".png"))
	if result == OK: shots.append(id)
	else: push_error("Could not capture visible viewport: " + id)

func special_scenarios() -> Dictionary:
	if not OS.is_debug_build() or app == null or app._save_path != "user://d2-debug.json": return {"ok": false, "error": "isolated_save_required"}
	# Explicit QA equipment fixtures; enemy HP, intentions, damage, ties, departure,
	# and outcomes are produced only by RunRules/BattleRules and actual callbacks.
	var records: Array = []
	app.meta = app.run_rules.new_meta()
	app.run = app.run_rules.start_run(app.meta,["keepsake.ring"],147)["run"]
	app.run["segment"] = 3
	app._last_events = []
	app._show_path()
	for index: int in range(app.run_rules.path_choices(app.run).size()): app._path_card_clicked(index)
	await shot("route-seven-segment3")
	_prepare_scenario("elite")
	await frames()
	app._battle_view.select_keepsake("keepsake.ring")
	await frames()
	await shot("elite-chew-intent")
	app._battle_view.request_end_turn()
	await frames()
	await shot("elite-chewed-wrap")
	records.append({"kind": "elite", "events": app._last_events.duplicate(true), "guard": app.battle["enemies"][0]["guard"], "binds": app.battle["enemies"][0]["binds"]})
	var chewed: bool = int(app.battle["enemies"][0]["guard"]) == 9 and int(app.battle["enemies"][0]["binds"]) == 0
	_prepare_scenario("boss")
	await frames()
	await shot("boss-stage")
	app.presentation_fast = false
	app._show_enemy_intro()
	await shot("boss-intro")
	app._close_overlay()
	app.presentation_fast = true
	var peaceful: bool = false
	for step: int in range(90):
		if app.screen != "battle": break
		var action: Dictionary = _peace_action()
		if action.is_empty(): break
		var played_id: String = str(app.battle["hand"][int(action["hand_index"])]["id"]) if action.get("type") == "play_card" else ""
		var trial: Dictionary = app.battle.duplicate(true)
		var outcome: Array = app.battle_rules.apply_action(trial, action)
		var peace: bool = bool(trial.get("battle_flags", {}).get("peaceful", false))
		if peace and not capture_dir.is_empty():
			app.presentation_fast = false
			app._lock_until = 0
		app._battle_view._commit(action)
		records.append({"kind": "boss", "action": action, "events": outcome})
		await frames()
		if played_id == "card.whisper_plus" and not capture_dir.is_empty() and app.screen == "battle" and not "future-two-intents" in shots:
			await shot("future-two-intents")
			var pointer: InputEventMouseMotion = InputEventMouseMotion.new()
			pointer.position = Vector2(338,166)
			pointer.global_position = pointer.position
			app.get_viewport().push_input(pointer,true)
			await app.get_tree().create_timer(0.8).timeout
			await shot("future-tooltip")
		if peace:
			peaceful = bool(app.battle.get("battle_flags", {}).get("peaceful", false))
			if not capture_dir.is_empty():
				await app.get_tree().create_timer(0.3).timeout
				await shot("boss-peaceful-departure")
			break
	return {"ok": chewed and peaceful, "chewed": chewed, "peaceful": peaceful, "records": records, "shots": shots.duplicate(), "fixture": "standard elite/boss node; debug-granted 12-card deck, 3 relics, ring and letter; seed147; no HP/intent/outcome injection"}

func _prepare_scenario(kind: String) -> void:
	if not OS.is_debug_build() or app == null or app._save_path != "user://d2-debug.json":
		push_error("Scenario preparation requires the isolated debug save")
		return
	app.meta = app.run_rules.new_meta()
	app.run = app.run_rules.start_run(app.meta,["keepsake.ring"],147)["run"]
	app.presentation_fast = true
	app._pending_terminal = false
	app._lock_until = 0
	app._last_events = []
	app.run["deck"] = ["card.whisper_plus", "card.whisper_plus", "card.whisper_plus", "card.double_tap", "card.double_tap", "card.double_tap", "card.double_tap", "card.double_tap", "card.double_tap", "card.tie", "card.tie", "card.bind"]
	app.run["keepsakes"] = ["keepsake.ring", "keepsake.letter"]
	app.run["relics"] = ["relic.open_ink", "relic.shedding_brush", "relic.tangled_earbuds"]
	app.run["segment"] = 7 if kind == "boss" else (4 if kind == "elite" else 1)
	var row: Array = app.run["path"][int(app.run["segment"])-1]
	var chosen: int = 0
	for index: int in range(row.size()):
		if row[index].get("type") == kind: chosen = index
	app._choose_path(chosen)

func _peace_action() -> Dictionary:
	var best: Dictionary = {}
	var score: float = -INF
	var rules: RefCounted = app.battle_rules
	var state: Dictionary = app.battle
	var before: Dictionary = rules.forecast(state)
	for action: Dictionary in rules.legal_actions(state):
		var trial: Dictionary = state.duplicate(true)
		rules.apply_action(trial,action)
		var value: float = 0
		if trial["battle_flags"].get("peaceful", false): return action
		if trial.get("status") in ["victory", "defeat"]: continue
		if action["type"] == "end_turn": value = -0.1
		else:
			var loss: int = int(state["enemies"][0]["hp"]) - int(trial["enemies"][0]["hp"])
			value = loss * 8.0 + (int(before["damage"]) - int(rules.forecast(trial)["damage"])) * 2.0
			if action["type"] == "shake_card": value -= 0.5
			if action.get("choices", {}).has("second_target"): value -= 100.0
			if action["type"] == "play_card":
				var card: Dictionary = rules.definition("cards",state["hand"][action["hand_index"]]["id"])
				if card["id"] == "card.whisper_plus" and int(state["enemies"][0]["binds"]) == 0 and int(action.get("target_index",-1)) == 0: value += 12.0
		if value > score: score = value; best = action
	return best
