extends RefCounted
## Permanent, JSON-only state. Definitions are injected, never read from disk.
var definitions: Dictionary
var config: Dictionary

func _init(tables: Dictionary = {}) -> void:
	definitions = tables
	config = _first(tables.get("meta", []))

func create() -> Dictionary:
	return {"version": 1, "runs_started": 0, "returned": [], "replica_cards": [], "memorials": [], "services": [], "seen_relics": [], "once_events": {}, "boss_defeated": false, "knot_found": false, "ending_seen": false, "last_end_reason": ""}

func available(meta: Dictionary) -> Array:
	var all_ids: Array = config.get("commission_ids", [])
	if meta.get("returned", []).is_empty():
		return [config.get("first_commission_id", "keepsake.ring")]
	var result: Array = []
	for id: String in all_ids:
		if not id in meta.get("returned", []):
			result.append(id)
	return result

func grant_return(meta: Dictionary, keepsake: Dictionary, wish: bool) -> Array:
	var id: String = keepsake.get("id", "")
	if id.is_empty() or id in meta["returned"]:
		return []
	meta["returned"].append(id)
	meta["memorials"].append(id)
	var card: String = keepsake.get("replica_plus_card_id" if wish else "replica_card_id", "")
	if not card.is_empty() and not card in meta["replica_cards"]:
		meta["replica_cards"].append(card)
	var events: Array = [{"type": "keepsake_returned", "id": id, "wish": wish}, {"type": "replica_unlocked", "id": card}]
	for service: Dictionary in config.get("services", []):
		if meta["returned"].size() >= int(service.get("returned", 1)) and not service["id"] in meta["services"]:
			meta["services"].append(service["id"])
			events.append({"type": "service_unlocked", "id": service["id"]})
	return events

func ending_ready(meta: Dictionary) -> bool:
	return meta.get("returned", []).size() >= int(config.get("ending_return_count", 3)) and meta.get("boss_defeated", false) and not meta.get("ending_seen", false)

func _first(value: Variant) -> Dictionary:
	if value is Array:
		return value[0] if not value.is_empty() else {}
	return value if value is Dictionary else {}
