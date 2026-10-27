extends SceneTree
var passed: int = 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	if value: passed += 1
	else: failures.append(message)
func _run() -> void:
	var Controller: GDScript = load("res://tests/rope_pair/view_controller_fixture.gd")
	var Debug: GDScript = load("res://scripts/debug/debug_session.gd")
	var tables: Dictionary = root.get_node("ContentCatalog").definitions()
	var cases: Array = [PackedStringArray(["--jump=3"]),PackedStringArray(["--jump=boss"]),PackedStringArray(["--give=card.double_knot"]),PackedStringArray(["--jump=boss","--give=keepsake.letter"])]
	for args: PackedStringArray in cases:
		var app: Control = Controller.new()
		app._save_path = "user://d2-debug.json"
		app._debug_seed = 147
		root.add_child(app)
		app._build_background()
		app.run_rules = load("res://scripts/core/run_rules.gd").new(tables)
		app.battle_rules = load("res://scripts/core/battle_rules.gd").new(tables)
		app.meta = app.run_rules.new_meta()
		app.settings = {"first_run_flow":true}
		app.presentation_fast = true
		app.run = app.run_rules.start_first_run(app.meta,147)["run"]
		app.run_rules.choose_path(app.run,0)
		app.battle = app.run_rules.start_battle(app.run,app.battle_rules)["state"]
		check(app.run_rules.is_first_run(app.run) and app.run["phase"] == "battle", "fixture is an interrupted first-run lesson " + str(args))
		Debug.new().apply_arguments(app,args)
		check(app.run["path"].size() == 7 and not app.run_rules.is_first_run(app.run), "explicit debug fixture always creates the seven-station route " + str(args))
		if args.has("--jump=3"): check(app.run["segment"] == 3 and app.run["phase"] == "path", "jump 3 reaches the standard third station")
		if args.has("--jump=boss"): check(app.run["segment"] == 7 and app.run.get("current_node",{}).get("type") == "boss" and app.battle["enemies"][0]["id"] == "boss.sock_snake", "boss jump starts an actual seventh-station boss battle " + str(args))
		if args.has("--give=card.double_knot"): check("card.double_knot" in app.run["deck"], "card gift survives standard route creation")
		if args.has("--give=keepsake.letter"): check("keepsake.letter" in app.run["keepsakes"] and "keepsake.letter" in app.battle["keepsakes"], "keepsake gift reaches the jumped boss battle")
		app.free()
		await process_frame
	print("ROPE_DEBUG_ARGS_RESULT: " + JSON.stringify({"passed":passed,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
