extends Node
## Versioned transaction snapshots. Never replace unsupported future saves.

const SAVE_VERSION: int = 2
const SAVE_PATH: String = "user://save.json"
const MAX_BYTES: int = 1024 * 1024
const BattleRules = preload("res://scripts/core/battle_rules.gd")
var _read_only_paths: Dictionary = {}

func default_state() -> Dictionary:
	return {"version": SAVE_VERSION, "meta": {}, "run": null, "settings": {"master": 1.0, "music": 0.7, "sfx": 0.8, "text_speed": 30, "window_scale": 2, "fullscreen": false}}

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
	if parse_error == OK and parser.data is Dictionary and _whole_number(parser.data.get("version"), SAVE_VERSION + 1, 9007199254740991):
		_read_only_paths[path] = true
		return {"ok": false, "state": default_state(), "error": "future_version", "recovered": false, "readonly": true}
	if parse_error == OK and parser.data is Dictionary and parser.data.get("run") is Dictionary:
		var route: Variant = parser.data["run"].get("route_mode")
		if route is String and route != "first_run":
			_read_only_paths[path] = true
			return {"ok": false, "state": default_state(), "error": "future_route", "recovered": false, "readonly": true}
	if parse_error == OK and parser.data is Dictionary and _whole_number(parser.data.get("version"), 1, 1):
		parser.data = migrate_state(parser.data, ContentCatalog.definitions())
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
	if not _whole_number(value.get("version"), SAVE_VERSION, SAVE_VERSION):
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
	var presentation: Dictionary = value["settings"]
	for key: String in ["intro_seen", "hut_seen", "instant_text", "fullscreen", "first_run_flow", "first_return_story_seen"]:
		if presentation.has(key) and not presentation[key] is bool: return false
	for key: String in ["banter_once", "banter_run_once", "decoration_once", "intro_enemies"]:
		if not presentation.has(key): continue
		if not presentation[key] is Dictionary: return false
		for flag: Variant in presentation[key]:
			if not flag is String or not presentation[key][flag] is bool: return false
	if presentation.has("text_speed") and not _whole_number(presentation["text_speed"], 1, 9999): return false
	if presentation.has("window_scale") and not _whole_number(presentation["window_scale"], 1, 3): return false
	if presentation.has("banter_seed") and not _whole_number(presentation["banter_seed"], -1, 9007199254740991): return false
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
	if not run is Dictionary or not run.get("phase") is String:
		return false
	if run.has("route_mode") and (not run["route_mode"] is String or run["route_mode"] != "first_run"):
		return false
	if run.has("reward_kind") and (not run["reward_kind"] is String or not run["reward_kind"] in ["", "cards", "thanks", "elite"]): return false
	if run.has("bind_bonus") and not _whole_number(run["bind_bonus"], 0, 1000000): return false
	if run.has("reward_queue"):
		if not run["reward_queue"] is Array: return false
		for group: Variant in run["reward_queue"]:
			if not group is Array or group.is_empty() or group.size() > 3: return false
			for reward: Variant in group:
				if not reward is Dictionary or reward.get("kind") != "relic" or not _known_id(reward.get("id"), "relic."): return false
	var short_route: bool = run.get("route_mode", "") == "first_run"
	var phases: Array = ["departure", "path", "battle_ready", "return", "hub"]
	if short_route: phases.append_array(["reward", "node", "replacement"])
	if not run["phase"] in phases: return false
	var station_count: int = 4 if short_route else 7
	for key: String in ["hp", "max_hp", "segment", "seed"]:
		if not run.has(key) or not _whole_number(run[key], 0, 9007199254740991):
			return false
	if float(run["max_hp"]) < 1 or float(run["hp"]) > float(run["max_hp"]) or not int(run["segment"]) in range(1, station_count + 1):
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
	if run["path"].size() != station_count or run["deck"].is_empty() or run["deck"].size() > 12:
		return false
	var row_index: int = 0
	for row: Variant in run["path"]:
		row_index += 1
		if not row is Array or row.is_empty() or row.size() > 2:
			return false
		for node: Variant in row:
			if not _valid_node(node) or int(node["segment"]) != row_index:
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
	if run["phase"] in ["battle_ready", "reward", "node", "replacement"] and not _valid_node(run["current_node"]):
		return false
	if run.has("resume_battle") and (not _valid_battle(run["resume_battle"]) or run["battle_request"].is_empty()):
		return false
	if short_route and not _valid_first_run(run): return false
	return true

func _valid_first_run(run: Dictionary) -> bool:
	# New safe phases can be resumed directly, so validate the semantic IDs the
	# controller/rules will dereference, not only their container shapes. This
	# leaves unknown extension fields intact and does not migrate legacy routes.
	if not run["first_trip"] or run["commissions"] != ["keepsake.ring"]: return false
	for field: String in ["deck", "removed_cards", "replica_cards", "relics", "keepsakes"]:
		var prefix: String = "relic." if field == "relics" else ("keepsake." if field == "keepsakes" else "card.")
		for id: String in run[field]:
			if not _known_id(id, prefix): return false
	for field: String in ["wishes", "wish_missed"]:
		for id: Variant in run[field]:
			if not _known_id(id, "keepsake.") or not run[field][id] is bool: return false
	for id: Variant in run["acquired_segments"]:
		if not _known_id(id, "keepsake.") or not _whole_number(run["acquired_segments"][id], 1, 4): return false
	for row: Array in run["path"]:
		for node: Dictionary in row:
			if not _valid_first_node(node): return false
	if not run["current_node"].is_empty():
		if not _valid_node(run["current_node"]) or not _valid_first_node(run["current_node"]): return false
		var node: Dictionary = run["current_node"]
		if int(node["segment"]) != int(run["segment"]): return false
		var found: bool = false
		for candidate: Dictionary in run["path"][int(run["segment"]) - 1]:
			if candidate["id"] == node["id"] and candidate["type"] == node["type"]: found = true
		if not found: return false
	if run["phase"] == "node" and not run["current_node"]["type"] in ["event", "campfire"]: return false
	if run["phase"] in ["battle_ready", "reward", "replacement"] and not run["current_node"]["type"] in ["battle", "elite"]: return false
	if run["phase"] in ["reward", "replacement"]:
		if run["rewards"].is_empty() or run["rewards"].size() > 3: return false
		for reward: Variant in run["rewards"]:
			if not reward is Dictionary or not reward.get("kind") is String or not reward["kind"] in ["card", "relic"] or not _known_id(reward.get("id"), reward["kind"] + "."): return false
	if run["phase"] == "replacement":
		var pending: Dictionary = run["pending_card"]
		if not _known_id(pending.get("id"), "card.") or not pending.get("source") is String or pending["source"] != "reward" or not _whole_number(pending.get("reward_index"), 0, run["rewards"].size() - 1): return false
		var choice: Dictionary = run["rewards"][int(pending["reward_index"])]
		if choice["kind"] != "card" or choice["id"] != pending["id"]: return false
	for record: Dictionary in run["pending_stories"]:
		if not _known_id(record.get("id"), "story.") or not ContentCatalog.entry(record["id"]).get("pages") is Array: return false
		if record.has("keepsake_id"):
			if not _known_id(record["keepsake_id"], "keepsake.") or not record.get("wish") is bool or not record.get("card_id") is String: return false
			var keepsake: Dictionary = ContentCatalog.entry(record["keepsake_id"])
			if not record["keepsake_id"] in run["keepsakes"] or record["id"] != keepsake["return_story_id"]: return false
			if record["card_id"] != keepsake["replica_plus_card_id" if record["wish"] else "replica_card_id"]: return false
	return true

func _valid_first_node(node: Dictionary) -> bool:
	var type_name: String = node["type"]
	var id: String = node["id"]
	if type_name == "campfire":
		if id != "campfire": return false
	elif type_name == "battle":
		if not _known_id(id, "enc."): return false
	elif type_name == "elite":
		if not _known_id(id, "elite."): return false
	elif type_name == "event":
		if not _known_id(id, "event."): return false
	else: return false
	for field: String in ["star_ids", "wish_ids", "heart_ids"]:
		for item: String in node[field]:
			if not _known_id(item, "keepsake."): return false
	return true

func _known_id(id: Variant, prefix: String) -> bool:
	return id is String and id.begins_with(prefix) and ContentCatalog.has_entry(id)

func _valid_battle(battle: Variant) -> bool:
	if not battle is Dictionary or not battle.get("schema") is String or not battle.get("status") is String or battle["schema"] != "battle/1" or battle["status"] != "player":
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
	if not _whole_number(battle["battle_flags"].get("pairs"), 0, 1000000) or not battle["battle_flags"].get("keepsake_uses") is Dictionary: return false
	for used: Variant in battle["battle_flags"]["keepsake_uses"].values():
		if not used is bool: return false
	for key: String in ["shakes_used", "ties_played", "extra_shakes"]:
		if not _whole_number(battle["turn_flags"].get(key), 0, 1000000): return false
	for enemy: Variant in battle["enemies"]:
		if not enemy is Dictionary or not enemy.get("id") is String or not enemy.get("intent") is Dictionary or not enemy.has("hp"):
			return false
		if not _whole_number(enemy.get("binds"), 0, 12) or not enemy.get("tie") is String or not enemy.get("departed") is String or not enemy["departed"] in ["", "paired", "scattered"]: return false
		if not enemy.get("uid") is String or not enemy.get("pair_tag") is String: return false
		for key: String in ["max_hp", "guard", "cycle_index", "guard_cycles", "weaken"]:
			if not _whole_number(enemy.get(key), 0, 1000000): return false
	for key: String in ["hp", "max_hp", "guard"]:
		if not _whole_number(battle["player"].get(key), 0, 9007199254740991):
			return false
	for key: String in ["seed", "turn", "energy", "next_uid", "next_turn_energy", "next_draw_penalty", "retaliate", "guard_multiplier", "retry_attempt", "resolution_depth"]:
		if not _whole_number(battle.get(key), 0, 9007199254740991):
			return false
	for key: String in ["battle", "shuffle"]:
		if not _valid_rng(battle["rng"].get(key)):
			return false
	if battle.has("tutorial") and not BattleRules.new(ContentCatalog.definitions()).is_tutorial_state_valid(battle): return false
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
	if not node is Dictionary or not node.get("id") is String or not node.get("type") is String or not node.get("type") in ["battle", "elite", "boss", "event", "campfire", "trade"]:
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

func migrate_state(value: Dictionary, definitions: Dictionary) -> Dictionary:
	var migrated: Dictionary = value.duplicate(true)
	if not _whole_number(migrated.get("version"), 1, 1): return migrated
	if not _valid_legacy_migration(migrated): return migrated
	var Meta = preload("res://scripts/core/meta_state.gd")
	var meta_rules: RefCounted = Meta.new(definitions)
	var meta: Dictionary = migrated["meta"]
	var defaults: Dictionary = meta_rules.create()
	for key: String in defaults:
		if not meta.has(key): meta[key] = defaults[key]
	var old_run: Variant = migrated.get("run")
	if old_run is Dictionary:
		for id: Variant in old_run.get("keepsakes", []):
			for data: Dictionary in definitions.get("keepsakes", []):
				if data["id"] == id: meta_rules.grant_return(meta, data, bool(old_run.get("wishes", {}).get(id, false)))
		meta["last_end_reason"] = "voluntary"
	migrated["version"] = SAVE_VERSION
	migrated["run"] = null
	for key: String in migrated["settings"].keys():
		if key.contains("tutorial") or key in ["first_run_flow", "first_return_story_seen"]: migrated["settings"].erase(key)
	migrated["settings"]["rope_tutorial_pending"] = true
	return migrated

func _valid_legacy_migration(value: Dictionary) -> bool:
	# Validate every container read by grant_return before touching legacy data.
	# Leave malformed input at version 1 so load_state takes the backup/recovery path.
	if not _json_safe(value, 0) or not value.get("meta") is Dictionary or not value.get("settings") is Dictionary: return false
	if not _valid_meta(value["meta"]): return false
	var old_run: Variant = value.get("run")
	if old_run == null: return true
	if not old_run is Dictionary or not _string_array(old_run.get("keepsakes", [])) or not old_run.get("wishes", {}) is Dictionary: return false
	for id: Variant in old_run.get("wishes", {}):
		if not id is String or not old_run["wishes"][id] is bool: return false
	return true
