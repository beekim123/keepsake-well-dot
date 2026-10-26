extends RefCounted
## Optional R2 checkpoint lives beside legacy progress, never inside the old run.
const VERSION: int = 1

static func inspect(value: Variant, saves: Node, rules: RefCounted) -> Dictionary:
	if value == null: return {"ok": true, "state": {}, "error": "", "readonly": false}
	if not value is Dictionary: return _invalid("invalid_tutorial")
	var version: Variant = value.get("version")
	if not (version is int or version is float) or not is_finite(float(version)): return _invalid("invalid_tutorial")
	if float(version) > VERSION: return {"ok": false, "state": {}, "error": "future_tutorial", "readonly": true}
	if float(version) != VERSION: return _invalid("invalid_tutorial")
	if not value.get("phase") is String or not value["phase"] in ["opening", "battle", "complete", "done"]: return _invalid("invalid_tutorial")
	var seed_value: Variant = value.get("seed")
	if not (seed_value is int or seed_value is float) or not is_finite(float(seed_value)) or float(seed_value) != floor(float(seed_value)) or float(seed_value) < 0 or float(seed_value) > 4294967295:
		return _invalid("invalid_tutorial")
	if value["phase"] == "battle":
		var battle: Variant = value.get("battle")
		# Older SaveService assumes scalar discriminators; reject hostile/malformed
		# optional values before calling its otherwise useful full battle guard.
		if not battle is Dictionary or not battle.get("schema") is String or not battle.get("status") is String: return _invalid("invalid_tutorial")
		if not rules.is_tutorial_state_valid(value.get("battle")) or not saves._valid_battle(value.get("battle")):
			return _invalid("invalid_tutorial")
		if int(value["battle"].get("seed", -1)) != int(seed_value): return _invalid("invalid_tutorial")
	if value["phase"] in ["complete", "done"] and not value.get("won") is bool: return _invalid("invalid_tutorial")
	return {"ok": true, "state": value.duplicate(true), "error": "", "readonly": false}

static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "state": {}, "error": reason, "readonly": false}
