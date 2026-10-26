extends Node
## Version 1 transaction snapshots. Never replace unsupported future saves.

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://save.json"
const MAX_BYTES: int = 1024 * 1024
var _read_only_paths: Dictionary = {}

func default_state() -> Dictionary:
	return {"version": SAVE_VERSION, "meta": {}, "run": null, "settings": {"master": 1.0, "music": 0.7, "sfx": 0.8}}

func load_state(path: String = SAVE_PATH) -> Dictionary:
	if not _safe_path(path):
		return {"ok": false, "state": default_state(), "error": "unsafe_path", "recovered": false}
	if not FileAccess.file_exists(path):
		return {"ok": true, "state": default_state(), "error": "", "recovered": false}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_read_only_paths[path] = true
		return {"ok": false, "state": default_state(), "error": "read_failed", "recovered": false, "readonly": true}
	if file.get_length() > MAX_BYTES:
		file.close()
		return _recover(path, "too_large")
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	file.close()
	if parse_error == OK and parser.data is Dictionary and int(parser.data.get("version", 0)) > SAVE_VERSION:
		_read_only_paths[path] = true
		return {"ok": false, "state": default_state(), "error": "future_version", "recovered": false, "readonly": true}
	if parse_error != OK or not _valid_state(parser.data):
		return _recover(path, "invalid_save")
	return {"ok": true, "state": parser.data, "error": "", "recovered": false}

func save_state(state: Dictionary, path: String = SAVE_PATH) -> Error:
	if _read_only_paths.has(path):
		return ERR_UNAVAILABLE
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
	if not (value.get("meta") is Dictionary and value.get("settings") is Dictionary and (value.get("run") == null or value.get("run") is Dictionary)):
		return false
	if not _valid_meta(value["meta"]) or not _valid_run(value["run"]):
		return false
	if not _json_safe(value, 0):
		return false
	for key: String in ["master", "music", "sfx"]:
		var volume: Variant = value["settings"].get(key, 1.0)
		if not (volume is int or volume is float) or not is_finite(float(volume)) or float(volume) < 0.0 or float(volume) > 1.0:
			return false
	return true

func _json_safe(value: Variant, depth: int) -> bool:
	if depth > 64:
		return false
	if value == null or value is bool or value is int or value is String:
		return true
	if value is float:
		return is_finite(value)
	if value is Array:
		for child: Variant in value:
			if not _json_safe(child, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false

func _safe_path(path: String) -> bool:
	return path.begins_with("user://") and not path.contains("..")

func _recover(path: String, reason: String) -> Dictionary:
	var backup: String = path + ".corrupt-%s-%s" % [str(int(Time.get_unix_time_from_system())), str(Time.get_ticks_usec())]
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))
	if rename_error != OK:
		# If a backup cannot be made, never replace the only copy with defaults.
		_read_only_paths[path] = true
	return {"ok": false, "state": default_state(), "error": reason, "recovered": rename_error == OK, "backup": backup if rename_error == OK else "", "readonly": rename_error != OK}

func _valid_meta(meta: Dictionary) -> bool:
	for key: String in ["returned", "replica_cards", "memorials", "services", "seen_relics"]:
		if meta.has(key) and not _string_array(meta[key]):
			return false
	for key: String in ["boss_defeated", "knot_found", "ending_seen"]:
		if meta.has(key) and not meta[key] is bool:
			return false
	if meta.has("once_events") and not meta["once_events"] is Dictionary:
		return false
	if meta.has("runs_started") and not _whole_number(meta["runs_started"], 0, 1000000):
		return false
	return true

func _valid_run(run: Variant) -> bool:
	if run == null or (run is Dictionary and run.is_empty()):
		return true
	if not run is Dictionary or not run.get("phase") in ["departure", "path", "battle_ready", "return", "hub"]:
		return false
	for key: String in ["hp", "max_hp", "segment", "seed"]:
		if not run.has(key) or not _whole_number(run[key], 0, 9007199254740991):
			return false
	if float(run["max_hp"]) < 1 or float(run["hp"]) > float(run["max_hp"]) or not int(run["segment"]) in range(1, 8):
		return false
	for key: String in ["deck", "relics", "keepsakes", "commissions", "departure_offers", "removed_cards", "replica_cards"]:
		if not _string_array(run.get(key)):
			return false
	for key: String in ["wishes", "wish_missed", "acquired_segments", "rng_states", "next_battle", "current_node", "battle_request", "battle_checkpoint", "stats", "pending_card"]:
		if not run.get(key) is Dictionary:
			return false
	for key: String in ["path", "history", "pending_stories", "rewards"]:
		if not run.get(key) is Array:
			return false
	if run["path"].size() != 7 or run["deck"].is_empty() or run["deck"].size() > 12:
		return false
	for row: Variant in run["path"]:
		if not row is Array or row.is_empty() or row.size() > 2:
			return false
		for node: Variant in row:
			if not _valid_node(node):
				return false
	for record: Variant in run["pending_stories"]:
		if not record is Dictionary or not record.get("id") is String:
			return false
	for key: String in ["number", "battle_attempt", "return_index"]:
		if not _whole_number(run.get(key), 0, 1000000):
			return false
	for key: String in ["first_trip", "spare_rope_available", "spare_rope_used", "first_card_reward_seen"]:
		if not run.get(key) is bool:
			return false
	for key: String in ["route", "rewards", "shuffle", "battle"]:
		if not _valid_rng(run["rng_states"].get(key)):
			return false
	for key: String in ["nodes", "battles", "turns", "retries"]:
		if not _whole_number(run["stats"].get(key), 0, 9007199254740991):
			return false
	if not run["battle_request"].is_empty() and not _valid_request(run["battle_request"]):
		return false
	if run["phase"] == "battle_ready" and not _valid_node(run["current_node"]):
		return false
	if run.has("resume_battle") and (not _valid_battle(run["resume_battle"]) or run["battle_request"].is_empty()):
		return false
	return true

func _valid_battle(battle: Variant) -> bool:
	if not battle is Dictionary or battle.get("schema") != "battle/1" or battle.get("status") != "player":
		return false
	for key: String in ["player", "rng", "encounter", "start_snapshot", "turn_flags", "battle_flags", "modifiers"]:
		if not battle.get(key) is Dictionary:
			return false
	for key: String in ["hand", "draw_pile", "discard", "enemies", "relics", "keepsakes"]:
		if not battle.get(key) is Array:
			return false
	for key: String in ["hand", "draw_pile", "discard"]:
		for card: Variant in battle[key]:
			if not card is Dictionary or not card.get("id") is String or not card.get("uid") is String:
				return false
	for enemy: Variant in battle["enemies"]:
		if not enemy is Dictionary or not enemy.get("id") is String or not enemy.get("intent") is Dictionary or not enemy.has("hp"):
			return false
	for key: String in ["hp", "max_hp", "guard"]:
		if not _whole_number(battle["player"].get(key), 0, 9007199254740991):
			return false
	for key: String in ["seed", "turn", "energy", "next_uid", "next_turn_energy", "next_draw_penalty", "retaliate", "guard_multiplier", "retry_attempt", "resolution_depth"]:
		if not _whole_number(battle.get(key), 0, 9007199254740991):
			return false
	for key: String in ["battle", "shuffle"]:
		if not _valid_rng(battle["rng"].get(key)):
			return false
	return battle["battle_flags"].get("uses") is Dictionary and _valid_request(battle["start_snapshot"], "run")

func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum

func _string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for entry: Variant in value:
		if not entry is String:
			return false
	return true

func _valid_node(node: Variant) -> bool:
	if not node is Dictionary or not node.get("id") is String or not node.get("type") in ["battle", "elite", "boss", "event", "campfire", "trade"]:
		return false
	for key: String in ["star_ids", "wish_ids", "heart_ids"]:
		if not _string_array(node.get(key)):
			return false
	return _whole_number(node.get("segment"), 1, 7) and node.get("hint") is String

func _valid_rng(rng: Variant) -> bool:
	if not rng is Dictionary:
		return false
	return _whole_number(rng.get("state"), 0, 4294967295) and _whole_number(rng.get("seed"), 0, 4294967295) and _whole_number(rng.get("draws"), 0, 9007199254740991)

func _valid_request(request: Variant, run_key: String = "run_state") -> bool:
	if not request is Dictionary or not request.get("encounter") is Dictionary or not request.get(run_key) is Dictionary or not _whole_number(request.get("seed"), 0, 4294967295):
		return false
	var encounter: Dictionary = request["encounter"]
	var initial: Dictionary = request[run_key]
	if not encounter.get("id") is String or not _string_array(encounter.get("enemies")) or not _string_array(initial.get("deck")):
		return false
	return _whole_number(initial.get("hp"), 0, 9007199254740991) and _whole_number(initial.get("max_hp"), 1, 9007199254740991)
