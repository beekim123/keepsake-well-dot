extends RefCounted
## Presentation-only semantic aliases. New IDs are admitted model textures;
## untouched rewards/other enemies retain their honest historical source IDs.
const ACTORS: Dictionary = {
	"char.asui": "char.r3_simple_asui", "char.r2_asui": "char.r3_simple_asui",
	"char.ma_ye": "char.r3_simple_ma_ye", "char.r2_ma_ye": "char.r3_simple_ma_ye",
	"enemy.wet_sock": "enemy.r3_simple_wet_sock", "enemy.r2_wet_sock": "enemy.r3_simple_wet_sock",
	"enemy.lint_bug": "enemy.r3_simple_lint_bug", "elite.hungry_drawer": "elite.r3_simple_hungry_drawer",
	"enemy.lonely_sock": "enemy.r3_simple_lonely_sock", "enemy.stinky_insole": "enemy.r3_simple_stinky_insole",
	"enemy.clothespin": "enemy.r3_simple_clothespin", "enemy.soap_bubble": "enemy.r3_simple_soap_bubble",
	"enemy.sock_kid": "enemy.r3_simple_sock_kid", "boss.sock_snake": "boss.r3_simple_sock_snake"
}
static func actor(id: String) -> String:
	var candidate: String = str(ACTORS.get(id, id))
	return candidate if AssetCatalog.has_asset(candidate) else id

static func card_art(card: Dictionary) -> String:
	var source: String = str(card.get("art", ""))
	var approved: String = source.replace("cardart.", "cardart.r3_v2_")
	# Rejected icons and old code art never silently return for pending cards.
	return approved if AssetCatalog.has_asset(approved) else ""

static func card_frame(_card: Dictionary) -> String:
	return "ui.r3_v2_card" if AssetCatalog.has_asset("ui.r3_v2_card") else ""

static func intent(kind: String) -> String:
	match kind:
		"attack": return "ui.r3_simple_icon_attack"
		"guard", "guard_all": return "ui.r3_simple_icon_guard"
		"idle": return "intent.r2_idle"
		_: return "intent.r2_special"

static func effect(card: Dictionary, current_guard: int = 0) -> Dictionary:
	var ops: Array = card.get("ops", [])
	if ops.is_empty(): return {"icon": "intent.r2_special", "text": ""}
	var op: Dictionary = ops[0]
	var operation: String = str(op.get("op", ""))
	var value: String = str(int(op.get("amount", 0))) if op.has("amount") else ""
	var icon: String = "intent.r2_special"
	match operation:
		"damage", "damage_all", "damage_equal_guard":
			icon = intent("attack")
			if operation == "damage_equal_guard": value = str(current_guard)
			if int(op.get("times", 1)) > 1: value += "×" + str(op["times"])
			elif operation == "damage_all": value += "全"
		"gain_guard": icon = intent("guard")
		"draw", "return_from_discard": icon = "ui.icon.r2_deck"
		"next_turn_energy": icon = "ui.r3_simple_icon_energy"
		"weaken_next_attack":
			icon = intent("attack")
			value = "−" + value
		"double_guard_this_turn":
			icon = intent("guard")
			value = "×2"
		"set_intent_idle": icon = intent("idle")
	return {"icon": icon, "text": value}

static func actor_height(id: String) -> float:
	# Read existing alpha only; transparent canvas padding is not body height.
	# No crop or new pixels are produced by this presentation measurement.
	var texture: Texture2D = AssetCatalog.texture(id)
	if texture == null: return float(AssetCatalog.frame_size(id).y)
	var pixels: Image = texture.get_image()
	if pixels == null or pixels.is_empty(): return float(AssetCatalog.frame_size(id).y)
	var occupied: Rect2i = pixels.get_used_rect()
	return maxf(1.0, AssetCatalog.anchor(id).y - occupied.position.y)
