extends RefCounted
## Generates route topology first, reserves wishes, then assigns unique events.
const RNG = preload("res://scripts/core/rng.gd")
var definitions: Dictionary
var config: Dictionary
var keepsakes: Dictionary = {}

func _init(tables: Dictionary = {}) -> void:
	definitions = tables
	var paths: Variant = tables.get("path", [])
	config = paths[0] if paths is Array and not paths.is_empty() else paths if paths is Dictionary else {}
	for item: Dictionary in tables.get("keepsakes", []):
		keepsakes[item["id"]] = item

func generate(run: Dictionary, meta: Dictionary) -> Array:
	var rng: RefCounted = RNG.new(run["rng_states"]["route"])
	var path: Array = []
	for spec: Dictionary in config.get("segments", []):
		var number: int = int(spec["segment"])
		var types: Array = spec["types"].duplicate()
		var chosen: Array = []
		if number in [1, 6, 7]:
			chosen = [types[0]]
		elif number == 4:
			chosen = types.duplicate()
		elif number == 2:
			chosen = ["event", types[rng.range_int(0, types.size() - 1)]]
			rng.shuffle(chosen)
		elif number == 3:
			rng.shuffle(types)
			chosen = types.slice(0, 2)
		else:
			chosen = [types[rng.range_int(0, types.size() - 1)], types[rng.range_int(0, types.size() - 1)]]
		var row: Array = []
		for type: String in chosen:
			row.append({"type": type, "id": "", "tier": int(spec.get("tier", 1)), "segment": number, "star_ids": [], "wish_ids": [], "heart_ids": [], "hint": ""})
		path.append(row)
	var event_missions: Array = []
	var other_missions: Array = []
	for id: String in run["commissions"]:
		if keepsakes[id]["wish"]["type"] == "event_choice":
			event_missions.append(id)
		else:
			other_missions.append(id)
	rng.shuffle(event_missions)
	var occupied: Array = []
	var reserved_events: Array = []
	for i: int in range(event_missions.size()):
		var id: String = event_missions[i]
		var source: int = 2 if (event_missions.size() == 2 and i == 0) or (event_missions.size() == 1 and rng.range_int(0, 1) == 0) else 4
		var target: int = 3 if source == 2 else 5
		var node: Dictionary = path[source - 1][0]
		if source == 4:
			for possible: Dictionary in path[3]:
				if possible["type"] == "elite": node = possible
		node["star_ids"].append(id)
		occupied.append(source)
		var wish_node: Dictionary = path[target - 1][0]
		if target == 3:
			for possible: Dictionary in path[2]:
				if possible["type"] == "event": wish_node = possible
			# Preserve distinct types when the random pair omitted an event.
		wish_node["type"] = "event"
		wish_node["id"] = keepsakes[id]["wish"]["event_id"]
		wish_node["wish_ids"].append(id)
		reserved_events.append(wish_node["id"])
	for id: String in other_missions:
		var segments: Array = [2, 3, 4, 5]
		for used: int in occupied: segments.erase(used)
		var source: int = 4 if run["first_trip"] else segments[rng.range_int(0, segments.size() - 1)]
		var node: Dictionary = path[source - 1][rng.range_int(0, path[source - 1].size() - 1)]
		if run["first_trip"]:
			for possible: Dictionary in path[3]:
				if possible["type"] == "elite": node = possible
		node["star_ids"].append(id)
		occupied.append(source)
		for row: Array in path:
			for possible: Dictionary in row:
				if possible["type"] == "campfire" and int(possible["segment"]) > source: possible["wish_ids"].append(id)
	var event_pool: Array = []
	for event: Dictionary in definitions.get("events", []):
		if event["id"] in reserved_events: continue
		if event.get("once_per_save", false) and (meta.get("once_events", {}).has(event["id"]) or not int(run["number"]) in event.get("run_numbers", [2, 3])): continue
		event_pool.append(event["id"])
	rng.shuffle(event_pool)
	for row: Array in path:
		for node: Dictionary in row:
			match node["type"]:
				"event":
					if node["id"] == "": node["id"] = event_pool.pop_back()
				"battle":
					var pool: Array = config.get("tiers", {}).get(str(node["tier"]), [])
					node["id"] = config.get("tutorial_encounter_id", "enc.tutorial") if run["first_trip"] and node["segment"] == 1 else pool[rng.range_int(0, pool.size() - 1)]
				"elite": node["id"] = config.get("elite_encounter_id", "enc.elite")
				"boss": node["id"] = config.get("boss_encounter_id", "enc.boss")
				_: node["id"] = node["type"]
			var hints: Array = config.get("hints", {}).get(node["type"], [node["type"]])
			node["hint"] = hints[rng.range_int(0, hints.size() - 1)]
			if node["id"] == "event.echo_mailbox": node["hint"] = config.get("special_hints", {}).get("event.echo_mailbox", node["hint"])
			if node["type"] == "elite" and not node["star_ids"].is_empty(): node["hint"] = config.get("special_hints", {}).get("elite_keepsake", node["hint"])
	run["rng_states"]["route"] = rng.snapshot()
	return path

func drift_skipped(run: Dictionary, chosen_index: int) -> Array:
	var events: Array = []
	var segment: int = int(run["segment"])
	var row: Array = run["path"][segment - 1]
	for i: int in range(row.size()):
		if i == chosen_index: continue
		for id: String in row[i]["star_ids"].duplicate():
			var last_drift: int = int(config.get("placement", {}).get("last_drift_segment", 5))
			var next_segment: int = segment + 1 if segment < last_drift else int(config.get("placement", {}).get("fallback_segment", 7))
			var target: Dictionary = run["path"][next_segment - 1][0]
			for candidate: Dictionary in run["path"][next_segment - 1]:
				if not id in candidate["wish_ids"]:
					target = candidate
					break
			row[i]["star_ids"].erase(id)
			target["star_ids"].append(id)
			events.append({"type": "keepsake_drift", "id": id, "segment": next_segment})
	return events

func choices(run: Dictionary) -> Array:
	if run.get("phase", "") != "path": return []
	var row: Array = run["path"][int(run["segment"]) - 1].duplicate(true)
	for node: Dictionary in row:
		node["heart_ids"] = []
		for id: String in node["wish_ids"]:
			if id in run["keepsakes"] and not run["wishes"].get(id, false) and not run["wish_missed"].get(id, false) and int(run["acquired_segments"].get(id, 99)) < int(run["segment"]):
				node["heart_ids"].append(id)
	return row
