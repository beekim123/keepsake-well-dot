extends Control
## Model-only town scene with live text. Sequencing/grants stay entirely in
## StoryPlayer/RunRules; absent identities never borrow an unrelated portrait.
signal advance_requested
const UI = preload("res://scripts/view/ui_factory.gd")
const SimpleUI = preload("res://scripts/view/remedy/simple_ui.gd")
var page: Dictionary = {}
var fast: bool = false
var characters_per_second: float = 30.0
var revealed: bool = false
var _text: Label
var _elapsed: float = 0.0
var _spoken: int = -1
var _body: String = ""
var _speaker: String = "narrator"
var _active: bool = true

func configure(definition: Dictionary, speed: float = 30.0, instant: bool = false) -> void:
	page = definition.duplicate(true)
	characters_per_second = maxf(1.0, speed)
	fast = instant

func _ready() -> void:
	theme = SimpleUI.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture: Control = Control.new()
	picture.name = "Illustration"
	picture.size = Vector2(640, 360)
	picture.clip_contents = true
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	UI.texture(picture, AssetCatalog, "board.r3_simple_town", Rect2(0, 0, 640, 360))
	_speaker = str(page.get("speaker", "narrator"))
	# Old layer metadata is used only to decide which *identity* is present.
	# It is never rendered and no young/ghost/unknown person is substituted.
	var identities: Array[String] = []
	for layer: Dictionary in page.get("layers", []):
		identities.append(str(layer.get("art", "")))
	if identities.has("big.asui") or identities.has("char.asui") or _speaker == "char.asui":
		_model_actor(picture, "StoryAsui", "char.r3_simple_asui", Vector2(220, 322))
	if identities.has("big.ma_ye") or identities.has("char.ma_ye") or _speaker == "npc.maye":
		_model_actor(picture, "StoryMaye", "char.r3_simple_ma_ye", Vector2(566, 190))
	if page.get("tone", "") != "memory" and (identities.has("big.mai_aunt") or _speaker == "npc.mai_aunt"):
		_model_actor(picture, "StoryAunt", "char.r3_simple_mai_aunt", Vector2(382, 312))
	_model_keepsakes(picture, identities)
	var panel: Panel = UI.frame(self, "StoryText", Rect2(116, 54, 408, 114))
	panel.add_theme_stylebox_override("panel", SimpleUI.style("ui.r3_simple_panel"))
	var speaker: Dictionary = ContentCatalog.entry("speaker." + _speaker)
	var caption: String = str(page.get("caption", ""))
	var speaker_name: String = str(speaker.get("text", "")) if _speaker != "narrator" else ""
	var heading: String = speaker_name + (" · " if not speaker_name.is_empty() and not caption.is_empty() else "") + caption
	UI.paragraph(panel, heading, Rect2(28, 22, 352, 20), UI.INK)
	_body = str(page.get("text", ""))
	_text = UI.paragraph(panel, _body, Rect2(28, 50 if not heading.is_empty() else 28, 352, 44), UI.INK)
	_text.visible_characters = -1 if fast else 0
	revealed = fast

func _model_keepsakes(parent: Node, identities: Array[String]) -> void:
	# Only objects explicitly present in the original page can appear. Multiple
	# layers of the same object (for example its glow) share one admitted icon.
	var objects: Array[String] = []
	for source_id: String in identities:
		var semantic_id: String = source_id
		match source_id:
			"prop.ring_glow": semantic_id = "keepsake.ring"
			"prop.mianmian_scarf": semantic_id = "keepsake.mianmian"
			"prop.letter_stamp", "prop.letter_words": semantic_id = "keepsake.letter"
		if not semantic_id.begins_with("keepsake."): continue
		semantic_id = semantic_id.trim_suffix("_large")
		if semantic_id not in objects: objects.append(semantic_id)
	for index: int in range(objects.size()):
		var semantic_id: String = objects[index]
		var art_id: String = SimpleUI.item_art(semantic_id)
		if art_id.is_empty(): continue
		var x: float = 320.0 - 24.0 + (index - (objects.size() - 1) * 0.5) * 52.0
		var icon: TextureRect = UI.texture(parent, AssetCatalog, art_id, Rect2(x, 270, 48, 48))
		icon.name = "StoryKeepsake_" + semantic_id.trim_prefix("keepsake.")
		icon.set_meta("semantic_art_id", semantic_id)

func _model_actor(parent: Node, actor_name: String, id: String, anchor_position: Vector2) -> void:
	if not AssetCatalog.has_asset(id): return
	var actor: Sprite2D = Sprite2D.new()
	actor.name = actor_name
	actor.texture = AssetCatalog.texture(id)
	actor.centered = false
	actor.offset = -AssetCatalog.anchor(id)
	actor.position = anchor_position
	# The model's bread-holding pose faces right. In the return scene the aunt
	# stands to the hero's right, so mirror the same pixels to face the speaker.
	actor.flip_h = actor_name == "StoryAunt"
	parent.add_child(actor)

func _process(delta: float) -> void:
	if revealed or not _active or _text == null: return
	_elapsed += delta
	var count: int = mini(_body.length(), int(_elapsed * characters_per_second))
	_text.visible_characters = count
	if int(count / 2) != _spoken and count < _body.length():
		_spoken = int(count / 2)
		AudioService.play_voice(_speaker, count)
	if count >= _body.length(): reveal()

func reveal() -> void:
	revealed = true
	if _text != null: _text.visible_characters = -1

func request_advance() -> bool:
	if not revealed:
		reveal()
		return false
	advance_requested.emit()
	return true

func suspend(value: bool) -> void:
	_active = not value
	_suspend_sprites(self, value)

func _suspend_sprites(parent: Node, paused: bool) -> void:
	for child: Node in parent.get_children():
		if child is AnimatedSprite2D:
			if paused: child.pause()
			else: child.play()
		_suspend_sprites(child, paused)
