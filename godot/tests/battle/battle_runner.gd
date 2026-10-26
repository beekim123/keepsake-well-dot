extends SceneTree
## Standalone headless D1 battle runner. File IO belongs only to this adapter;
## BattleSuite receives ordinary JSON definitions and does not use autoloads.
const Suite = preload("res://tests/battle/battle_suite.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var definitions: Dictionary = {}
	var source_root: String = OS.get_environment("KEEPSAKE_CONTENT_ROOT")
	if source_root.is_empty():
		source_root = ProjectSettings.globalize_path("res://").path_join("../content/data").simplify_path()
	for table_name: String in ["cards", "relics", "keepsakes", "enemies", "encounters", "events", "path", "meta", "balance", "ui"]:
		var path: String = source_root.path_join(table_name + ".json")
		if FileAccess.file_exists(path):
			definitions[table_name] = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result: Dictionary = Suite.new().run(definitions)
	print("D1_BATTLE_TEST_RESULT: " + JSON.stringify(result))
	quit(0 if int(result.get("failed", 1)) == 0 and int(result.get("passed", 0)) > 0 else 1)
