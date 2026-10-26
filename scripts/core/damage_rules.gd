class_name DamageRules
extends RefCounted
## D0's deliberately small pure-rule seam. It does not implement a battle loop.
## Input is immutable; guarding absorbs damage before HP, and HP cannot go negative.

static func apply_damage(target: Dictionary, amount: int) -> Dictionary:
	var next: Dictionary = target.duplicate(true)
	var guard_before: int = maxi(0, int(target.get("guard", 0)))
	var hp_before: int = maxi(0, int(target.get("hp", 0)))
	var incoming: int = maxi(0, amount)
	var blocked: int = mini(guard_before, incoming)
	var hp_damage: int = mini(hp_before, incoming - blocked)
	next["guard"] = guard_before - blocked
	next["hp"] = hp_before - hp_damage
	return {
		"state": next,
		"events": [{"type": "damage", "amount": incoming, "blocked": blocked, "hp_damage": hp_damage}]
	}
