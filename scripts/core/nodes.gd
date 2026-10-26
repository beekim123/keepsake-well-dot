extends RefCounted
## Noncombat effects and reward pools, using only injected immutable definitions.
const RNG = preload("res://scripts/core/rng.gd")
var definitions: Dictionary
var balance: Dictionary
var cards: Dictionary = {}
var events_by_id: Dictionary = {}
var ui: Dictionary = {}

func _init(tables: Dictionary = {}) -> void:
	definitions = tables
	balance = tables.get("balance", [{}])[0]
	for card: Dictionary in tables.get("cards", []): cards[card["id"]] = card
	for event: Dictionary in tables.get("events", []): events_by_id[event["id"]] = event
	for item: Dictionary in tables.get("ui", []): ui[item["id"]] = item.get("text", "")

func choices(run: Dictionary) -> Array:
	if run.get("phase", "") != "node": return []
	var node: Dictionary = run["current_node"]
	var result: Array = []
	match node.get("type", ""):
		"event":
			for choice: Dictionary in events_by_id.get(node["id"], {}).get("choices", []):
				var required: String = choice.get("when", {}).get("keepsake_id", "")
				if not required.is_empty() and not can_wish(run, required): continue
				result.append(choice.duplicate(true))
		"campfire":
			var heal: int = int(balance["campfire_heal"])
			var growth: int = int(balance["campfire_max_hp"])
			result = [{"id": "rest", "text": str(ui.get("ui.d1.node_rest", "")).replace("{amount}", str(heal)), "ops": [{"op": "heal", "amount": heal}]}, {"id": "dry_rope", "text": str(ui.get("ui.d1.node_dry_rope", "")).replace("{amount}", str(growth)), "ops": [{"op": "max_hp", "amount": growth}]}]
		"trade":
			result = [{"id": "leave", "text": ui.get("ui.d1.node_trade_leave", ""), "ops": []}]
	for choice: Dictionary in result:
		choice["preview"] = preview(run, choice)
	return result

func preview(run: Dictionary, choice: Dictionary) -> Dictionary:
	# Replay effects against a private copy so lethal damage, spare rope and
	# pending replacements cannot disagree with their displayed consequences.
	var proposed: Dictionary = run.duplicate(true)
	var effect_events: Array = resolve(proposed, choice)
	return {"hp": int(proposed["hp"]), "max_hp": int(proposed["max_hp"]), "next_battle": proposed["next_battle"].duplicate(true), "spare_rope_used": proposed["spare_rope_used"], "events": effect_events, "ops": choice.get("ops", []).duplicate(true)}

func can_wish(run: Dictionary, id: String) -> bool:
	return id in run["keepsakes"] and not run["wishes"].get(id, false) and not run["wish_missed"].get(id, false) and int(run["acquired_segments"].get(id, 99)) < int(run["segment"])

func resolve(run: Dictionary, choice: Dictionary) -> Array:
	var result: Array = []
	for op: Dictionary in choice.get("ops", []):
		result.append_array(apply_op(run, op))
	if run["current_node"]["type"] == "campfire" and choice["id"] == "rest":
		for item: Dictionary in definitions.get("keepsakes", []):
			if item["wish"]["type"] == "campfire_rest" and can_wish(run, item["id"]):
				run["wishes"][item["id"]] = true
				result.append({"type": "wish_done", "id": item["id"]})
	return result

func apply_op(run: Dictionary, op: Dictionary) -> Array:
	var result: Array = []
	var amount: int = int(op.get("amount", 0))
	match op["op"]:
		"heal":
			var before: int = int(run["hp"])
			run["hp"] = mini(int(run["max_hp"]), before + amount)
			result.append({"type": "heal", "amount": int(run["hp"]) - before})
		"lose_hp":
			var before: int = int(run["hp"])
			run["hp"] = maxi(0, before - amount)
			result.append({"type": "lose_hp", "amount": before - int(run["hp"])})
			if run["hp"] == 0 and run.get("spare_rope_available", false) and not run.get("spare_rope_used", false):
				run["hp"] = int(balance["spare_rope_hp"])
				run["spare_rope_used"] = true
				run["next_battle"]["start_guard"] = int(run["next_battle"].get("start_guard", 0)) + int(balance["spare_rope_guard"])
				result.append({"type": "spare_rope"})
		"max_hp":
			run["max_hp"] = int(run["max_hp"]) + amount
			result.append({"type": "max_hp", "amount": amount})
		"complete_wish":
			var id: String = op.get("keepsake_id", "")
			if can_wish(run, id):
				run["wishes"][id] = true
				result.append({"type": "wish_done", "id": id})
		"gain_relic":
			var offers: Array = relic_offers(run, maxi(1, amount))
			for id: String in offers:
				run["relics"].append(id)
				result.append({"type": "relic_get", "id": id})
		"gain_card":
			var offers: Array = card_offers(run, 1, op.get("card_type", ""))
			if not offers.is_empty():
				if run["deck"].size() < int(balance["deck_limit"]):
					run["deck"].append(offers[0])
					result.append({"type": "card_get", "id": offers[0]})
				else:
					run["pending_card"] = {"id": offers[0], "source": "node"}
		"next_battle":
			var next: Dictionary = run["next_battle"]
			if op.has("enemy_id"):
				if not next.has("extra_enemies"): next["extra_enemies"] = []
				next["extra_enemies"].append(op["enemy_id"])
			if op.has("guard"): next["start_guard"] = int(next.get("start_guard", 0)) + int(op["guard"])
			if op.has("bonus_relics"): next["extra_relic_rewards"] = int(next.get("extra_relic_rewards", 0)) + int(op["bonus_relics"])
			if op.get("first_attack_immune", false): next["cancel_first_attack"] = true
			result.append({"type": "next_battle", "modifiers": next.duplicate(true)})
		"story": result.append({"type": "story", "id": op.get("story_id", "")})
	return result

func relic_offers(run: Dictionary, count: int, exclude: Array = []) -> Array:
	var candidates: Array = []
	for relic: Dictionary in definitions.get("relics", []):
		if not relic["id"] in run["relics"] and not relic["id"] in exclude: candidates.append(relic["id"])
	var rng: RefCounted = RNG.new(run["rng_states"]["rewards"])
	rng.shuffle(candidates)
	run["rng_states"]["rewards"] = rng.snapshot()
	return candidates.slice(0, mini(count, candidates.size()))

func card_offers(run: Dictionary, count: int, type: String = "", exclude: Array = [], guarantee_replica: bool = false) -> Array:
	var candidates: Array = []
	var replicas: Array = []
	for card: Dictionary in definitions.get("cards", []):
		var id: String = card["id"]
		if id in run["removed_cards"] or id in exclude or (not type.is_empty() and card["type"] != type): continue
		if id in run.get("replica_cards", []):
			candidates.append(id)
			replicas.append(id)
		elif card.get("pool", "") == "reward": candidates.append(id)
	var rng: RefCounted = RNG.new(run["rng_states"]["rewards"])
	rng.shuffle(candidates)
	if guarantee_replica and not replicas.is_empty():
		var guaranteed: String = replicas[rng.range_int(0, replicas.size() - 1)]
		candidates.erase(guaranteed)
		candidates.push_front(guaranteed)
	run["rng_states"]["rewards"] = rng.snapshot()
	return candidates.slice(0, mini(count, candidates.size()))
