extends RefCounted
const RNG = preload("res://scripts/core/rng.gd")
var definitions: Dictionary

func _init(tables: Dictionary = {}) -> void:
	definitions = tables

func create(meta: Dictionary, commissions: Array, seed_value: int) -> Dictionary:
	var balance: Dictionary = _first(definitions.get("balance", []))
	var config: Dictionary = _first(definitions.get("meta", []))
	var streams: Dictionary = {}
	for stream: String in ["route", "rewards", "shuffle", "battle"]:
		streams[stream] = RNG.new(RNG.derive(seed_value, stream)).snapshot()
	var hp: int = int(balance.get("max_hp", balance.get("player_max_hp", 40)))
	return {"version": 1, "seed": seed_value, "number": int(meta.get("runs_started", 0)) + 1, "first_trip": int(meta.get("runs_started", 0)) == 0 and meta.get("returned", []).is_empty(), "phase": "path", "segment": 1, "hp": hp, "max_hp": hp, "deck": config.get("starter_deck", []).duplicate(), "relics": [], "keepsakes": [], "commissions": commissions.duplicate(), "wishes": {}, "wish_missed": {}, "acquired_segments": {}, "path": [], "history": [], "rng_states": streams, "next_battle": {}, "spare_rope_available": "spare_rope" in meta.get("services", []), "spare_rope_used": false, "first_card_reward_seen": false, "replica_cards": meta.get("replica_cards", []).duplicate(), "departure_offers": [], "rewards": [], "removed_cards": [], "pending_card": {}, "current_node": {}, "battle_request": {}, "battle_checkpoint": {}, "battle_attempt": 0, "pending_stories": [], "return_index": 0, "end_reason": "", "stats": {"battles": 0, "turns": 0, "nodes": 0, "retries": 0}}

func _first(value: Variant) -> Dictionary:
	if value is Array:
		return value[0] if not value.is_empty() else {}
	return value if value is Dictionary else {}
