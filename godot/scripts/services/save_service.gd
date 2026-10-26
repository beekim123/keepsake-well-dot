extends Node
## Versioned safe-read/write foundation only. D0 has no expedition to resume.

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://save.json"
const MAX_BYTES: int = 1024 * 1024

func default_state() -> Dictionary:
	return {"version": SAVE_VERSION, "meta": {}, "run": null, "settings": {"master": 1.0, "music": 0.7, "sfx": 0.8}}

func load_state(path: String = SAVE_PATH) -> Dictionary:
	if not _safe_path(path):
		return {"ok": false, "state": default_state(), "error": "unsafe_path", "recovered": false}
	if not FileAccess.file_exists(path):
		return {"ok": true, "state": default_state(), "error": "", "recovered": false}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "state": default_state(), "error": "read_failed", "recovered": false}
	if file.get_length() > MAX_BYTES:
		file.close()
		return _recover(path, "too_large")
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not _valid_state(parser.data):
		return _recover(path, "invalid_save")
	return {"ok": true, "state": parser.data, "error": "", "recovered": false}

func save_state(state: Dictionary, path: String = SAVE_PATH) -> Error:
	if not _safe_path(path) or not _valid_state(state):
		return ERR_INVALID_DATA
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state, "\t") + "\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	# Rename in the same directory is atomic; failure leaves the old save untouched.
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))

func _valid_state(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.get("version", -1) != SAVE_VERSION:
		return false
	return value.get("meta") is Dictionary and value.get("settings") is Dictionary and (value.get("run") == null or value.get("run") is Dictionary)

func _safe_path(path: String) -> bool:
	return path.begins_with("user://") and not path.contains("..")

func _recover(path: String, reason: String) -> Dictionary:
	var backup: String = path + ".corrupt-%s-%s" % [str(int(Time.get_unix_time_from_system())), str(Time.get_ticks_usec())]
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))
	return {"ok": false, "state": default_state(), "error": reason, "recovered": rename_error == OK, "backup": backup if rename_error == OK else ""}
