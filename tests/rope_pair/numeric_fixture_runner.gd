extends SceneTree
const Suite = preload("res://tests/rope_pair/content_suite.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var catalog: Node = root.get_node("ContentCatalog")
	var changed: Dictionary = catalog.definitions()
	for enemy: Dictionary in changed["enemies"]: enemy["hp"] += 6
	changed["balance"][0]["max_hp"] += 5
	for card: Dictionary in changed["cards"]:
		for op: Dictionary in card.get("ops", []):
			if op.get("op", "") in ["damage", "bonus_hit_if_bound", "damage_if_wilted", "bind"]:
				op["amount"] += 1
				if op.has("wilted_amount"): op["wilted_amount"] += 1
	# Preserve the real two-hit pair lesson under the injected damage variation.
	for tutorial: Dictionary in changed["tutorial"]:
		if tutorial["id"] == "tutorial.pair": tutorial["enemy"]["hp"] += 2
	for relic: Dictionary in changed["relics"]:
		for key: String in ["bound_attack_bonus", "lone_attack_bonus", "scattered_partner_damage"]:
			if relic.get("rules", {}).has(key): relic["rules"][key] += 1
		for op: Dictionary in relic.get("ops", []):
			if op.get("op", "") in ["damage_both", "heal", "draw", "gain_energy", "bind_threat"]: op["amount"] += 1
	var result: Dictionary = Suite.new().run(catalog, changed)
	print("ROPE_NUMERIC_FIXTURE_RESULT: " + JSON.stringify(result))
	quit(0 if result["failed"] == 0 else 1)
