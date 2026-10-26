extends RefCounted
static func definitions() -> Dictionary:
	var result: Dictionary = {}
	for name: String in ["cards", "relics", "keepsakes", "enemies", "encounters", "events", "path", "meta", "balance", "ui"]:
		result[name] = JSON.parse_string(FileAccess.get_file_as_string("res://../content/data/" + name + ".json"))
	return result
