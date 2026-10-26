extends RefCounted
## Presentation-only scheduling. Private deterministic draws never touch core RNG.
var records: Array = []
var saved_once: Dictionary = {}
var run_once: Dictionary = {}
var battle_once: Dictionary = {}
var cooldown_until: float = -1.0
var speaker_until: Dictionary = {}
var serial: int = 0
var seed_value: int = 0

func configure(definitions: Array, saved: Dictionary = {}, seed: int = 0) -> void:
	records = definitions.duplicate(true)
	saved_once = saved.duplicate(true)
	seed_value = seed

func begin_run(seed: int) -> void:
	seed_value = seed
	run_once.clear()
	begin_battle()

func begin_battle() -> void:
	battle_once.clear()
	speaker_until.clear()
	cooldown_until = -1.0

func consider(event: String, context: Dictionary, now: float) -> Dictionary:
	var eligible: Array = []
	for record: Dictionary in records:
		if record.get("event", "") != event or _seen(record) or not _matches(record.get("when", {}), context):
			continue
		var priority: bool = bool(record.get("priority", false))
		if not priority and (now < cooldown_until or now < float(speaker_until.get(record.get("speaker", ""), -1.0))):
			continue
		serial += 1
		var draw: float = float(absi(hash(str(seed_value) + ":" + str(serial) + ":" + str(record.get("id", "")))) % 10000) / 10000.0
		if draw >= float(record.get("chance", 1.0)):
			continue
		eligible.append(record)
	if eligible.is_empty():
		return {}
	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return bool(a.get("priority", false)) and not bool(b.get("priority", false)))
	var chosen: Dictionary = eligible[0]
	var lines: Array = chosen.get("lines", [])
	if lines.is_empty():
		return {}
	var line: String = str(lines[absi(hash(str(serial) + str(seed_value))) % lines.size()])
	var duration: float = 2.5 + float(line.length()) * 0.08
	var speaker: String = str(chosen.get("speaker", "narrator"))
	cooldown_until = now + 4.0
	speaker_until[speaker] = now + duration
	match str(chosen.get("once", "none")):
		"save": saved_once[chosen["id"]] = true
		"run": run_once[chosen["id"]] = true
		"battle": battle_once[chosen["id"]] = true
	return {"id": chosen["id"], "speaker": speaker, "text": line, "once": chosen.get("once", "none"), "duration": duration, "priority": bool(chosen.get("priority", false)), "lock_seconds": 1.5 if chosen.get("priority", false) else 0.0}

func _seen(record: Dictionary) -> bool:
	var id: String = str(record.get("id", ""))
	match str(record.get("once", "none")):
		"save": return saved_once.has(id)
		"run": return run_once.has(id)
		"battle": return battle_once.has(id)
	return false

func _matches(conditions: Dictionary, context: Dictionary) -> bool:
	for key: String in conditions:
		if key == "minions_at_least":
			if int(context.get("minions", 0)) < int(conditions[key]): return false
		elif key in ["keepsake_id", "enemy_id"]:
			if context.get(key, "") != conditions[key] and not conditions[key] in context.get("keepsakes" if key == "keepsake_id" else "enemy_ids", []): return false
		elif context.get(key) != conditions[key]:
			return false
	return true
