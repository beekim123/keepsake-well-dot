extends SceneTree
## A fresh, interactive playtest title. Never reads or writes the human save.
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if not OS.is_debug_build():
		push_error("DEBUG ONLY: manual playtest is unavailable in release builds")
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument != "--seed=147":
			push_error("DEBUG ONLY: manual playtest accepts only --seed=147; no jump or autoplay flags")
			quit(1)
			return
	var saves: Node = root.get_node("SaveService")
	var result: Error = saves.save_state(saves.default_state(), "user://d2-debug.json")
	if result != OK:
		push_error("DEBUG ONLY: could not reset isolated playtest save: " + str(result))
		quit(1)
		return
	print("DEBUG ONLY: reset user://d2-debug.json; seed=147; interactive title; human save untouched")
	var app: Control = load("res://scenes/main.tscn").instantiate()
	app._save_path = "user://d2-debug.json"
	app._debug_seed = 147
	root.add_child(app)
