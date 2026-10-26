class_name BattleState
extends RefCounted
## State is deliberately JSON-only, with stable card and enemy instance IDs.
static func create(seed_value: int, run: Dictionary) -> Dictionary:
	return {
		"schema": "battle/1", "seed": seed_value, "status": "player", "turn": 0,
		"player": {"hp": int(run.get("hp", 40)), "max_hp": int(run.get("max_hp", 40)), "guard": 0},
		"energy": 0, "hand": [], "draw_pile": [], "discard": [], "enemies": [],
		"relics": run.get("relics", []).duplicate(true), "keepsakes": run.get("keepsakes", []).duplicate(true),
		"turn_flags": {}, "battle_flags": {"cards_played": 0, "pairs": 0, "keepsake_uses": {}, "uses": {}, "victory_pending": false},
		"modifiers": run.get("next_battle", {}).duplicate(true), "rng": {}, "next_uid": 0,
		"bind_bonus": int(run.get("bind_bonus", 0)), "next_turn_refill": 0, "next_turn_energy": 0, "next_draw_penalty": 0, "retaliate": 0, "guard_multiplier": 1,
		"spare_rope_available": bool(run.get("spare_rope_available", false)),
		"spare_rope_used": bool(run.get("spare_rope_used", false)), "retry_attempt": 0,
		"start_snapshot": {}, "encounter": {}, "warnings": [], "resolution_depth": 0
	}

static func new_card(state: Dictionary, card_id: String) -> Dictionary:
	state["next_uid"] += 1
	return {"uid": "card_%d" % state["next_uid"], "id": card_id}

static func living_slots(state: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for index: int in range(state["enemies"].size()):
		if int(state["enemies"][index]["hp"]) > 0 and str(state["enemies"][index].get("departed", "")).is_empty():
			result.append(index)
	return result

static func find_card(cards: Array, uid: Variant) -> int:
	for index: int in range(cards.size()):
		if str(cards[index].get("uid", "")) == str(uid):
			return index
	return -1
