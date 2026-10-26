extends Control
## A projection of BattleRules. All legal commands, HP, intents and predictions
## come from the rules object; this script never resolves combat.
const BattleActor = preload("res://scripts/view/remedy/battle_actor.gd")
const Art = preload("res://scripts/view/remedy/battle_art.gd")
const SimpleUI = preload("res://scripts/view/remedy/simple_ui.gd")
const HealthReadout = preload("res://scenes/remedy/HealthReadout.tscn")
const UI = preload("res://scripts/view/ui_factory.gd")
var rules: RefCounted
var state: Dictionary = {}
var on_command: Callable
var on_pile: Callable
var on_pause: Callable
var selected: int = -1
var target: int = -1
var hover_card: int = -1
var _legal: Array = []
var _forecast: Dictionary = {}
var _enemy_buttons: Array[Button] = []
var _enemy_values: Array[Label] = []
var _hand_buttons: Array[Button] = []
var _damage: Label
var _large: Panel
var _chooser: Panel
var _drag_origin: Vector2
var _dragging: bool = false
var _pressed_card: int = -1
var _input_ready_frame: int = 0
var _picker_actions: Array = []
var _picker_page: int = 0
var _last_invalid: Label
var _rope_layer: Control
var _rope_tiles: Array[TextureRect] = []
var _actors: Dictionary = {}
var _asui: Node2D
var _hero_health: Control
var _enemy_health: Array[Control] = []
var _hand_homes: Array[Vector2] = []
var _item_icons: Dictionary = {}
var _popups: Array = []
var _proc_icons: Array = []
var decoration_counts: Dictionary = {}
var decoration_saved: Dictionary = {}
var presentation_duration: float = 0.0
var instant_presentation: bool = false
var first_run_presentation: bool = false
var _event_queue: Array = []
var _event_clock: float = 0.0
var _highlights: Array = []
var on_decoration: Callable


func configure(battle_rules: RefCounted, battle_state: Dictionary, command: Callable, pile: Callable, pause_callback: Callable) -> void:
	rules = battle_rules
	state = battle_state
	on_command = command
	on_pile = pile
	on_pause = pause_callback

func _ready() -> void:
	_input_ready_frame = Engine.get_process_frames() + 1
	_legal = rules.legal_actions(state)
	_forecast = rules.forecast(state)
	_build()

func t(key: String, args: Dictionary = {}) -> String:
	return ContentCatalog.format_text("ui.d1." + key, args)

func _build() -> void:
	theme = SimpleUI.theme()
	# Preserve the approved far/mid/near model composition at its native size.
	for layer: String in ["far", "mid", "near"]:
		UI.texture(self, AssetCatalog, "board.r2_sock_swamp_" + layer, Rect2(0, 0, 640, 360))
	var station: Panel = UI.frame(self, "Station", Rect2(240, 3, 160, 28))
	station.add_theme_stylebox_override("panel", SimpleUI.style("ui.r3_simple_station"))
	var encounter: Dictionary = ContentCatalog.entry(str(state.get("encounter", {}).get("id", "")))
	var station_name: Label = UI.label(station, str(encounter.get("name", ContentCatalog.text("ui.r2.battle_station"))), Rect2(10, 5, 140, 18), SimpleUI.PAPER)
	station_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	station.tooltip_text = t("turn", {"turn": state.get("turn", 1)})
	var pause: Button = UI.button(self, "", Rect2(606, 5, 28, 28), on_pause, "Pause")
	pause.icon = AssetCatalog.texture("ui.icon.r2_pause")
	pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause.expand_icon = true
	pause.add_theme_constant_override("icon_max_width", 16)
	pause.tooltip_text = t("pause")
	var ma_id: String = Art.actor("char.ma_ye")
	if AssetCatalog.has_asset(ma_id):
		var ma: Node2D = BattleActor.new()
		ma.name = "MaYe"
		add_child(ma)
		ma.setup(ma_id, Vector2(52, 0))
	var enemies: Array = state.get("enemies", [])
	var boss_layout: bool = false
	for enemy: Dictionary in enemies:
		if str(enemy.get("id", "")).begins_with("boss."): boss_layout = true
	for index: int in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		var x: float = 476.0 if enemies.size() == 1 else 360.0 + index * (216.0 / maxi(1, enemies.size() - 1))
		if enemies.size() == 2: x = 410 + index * 126
		if boss_layout: x = 338 if index == 0 else 444 + (index - 1) * 72
		var width: float = 148 if boss_layout and index == 0 else 82
		var button: Button = UI.button(self, "", Rect2(x - width / 2, 88, width, 168), _enemy_clicked.bind(index), "Enemy%d" % index)
		button.disabled = int(enemy.get("hp", 0)) <= 0
		for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
		button.mouse_entered.connect(_target_hover.bind(index))
		var definition: Dictionary = ContentCatalog.entry(str(enemy.get("id", "")))
		var intent: Dictionary = _intent_for(index)
		button.tooltip_text = str(definition.get("name", enemy.get("name", ""))) + " · " + _intent_text(intent) + " · " + str(intent.get("name", "")) + "\n" + str(definition.get("rule_text", definition.get("text", definition.get("mechanic_text", ""))))
		_enemy_buttons.append(button)
		var art_id: String = Art.actor(str(definition.get("art", enemy.get("id", ""))))
		if art_id == "ui.panel.default": art_id = Art.actor(str(enemy.get("id", "")))
		if AssetCatalog.has_asset(art_id):
			var sprite: Node2D = BattleActor.new()
			button.add_child(sprite)
			sprite.direction = -1.0
			sprite.setup(art_id, Vector2(width / 2, 148))
			sprite.modulate.a = 0.25 if button.disabled else 1.0
			_actors[index] = sprite
		var actor_height: float = minf(128, Art.actor_height(art_id))
		var intent_y: float = maxf(-42, 148 - actor_height - 38)
		UI.texture(button, AssetCatalog, Art.intent(str(intent.get("type", "idle"))), Rect2(width / 2 - 28, intent_y, 28, 28))
		var amount: String = str(int(intent.get("amount", 0))) if intent.has("amount") else ""
		if int(intent.get("times", 1)) > 1: amount += "×" + str(intent["times"])
		var intent_value: Label = UI.label(button, amount, Rect2(width / 2 + 1, intent_y + 4, 46, 22), UI.PAPER, 18)
		intent_value.add_theme_color_override("font_outline_color", SimpleUI.INK)
		intent_value.add_theme_constant_override("outline_size", 2)
		var health: Control = HealthReadout.instantiate()
		health.name = "EnemyHealth%d" % index
		health.position = Vector2(x - 24, 246)
		health.bar_width = 48.0
		health.bar_height = 4.0
		add_child(health)
		health.update_values(enemy, {}, true, true)
		health.visible = not button.disabled
		_enemy_health.append(health)
		# Full textual projection remains available; the visible one uses HP bars.
		var stats: Label = UI.paragraph(button, _enemy_stat(enemy), Rect2(0, 0, width, 32), UI.PAPER)
		stats.add_theme_constant_override("line_spacing", 0)
		stats.hide()
		_enemy_values.append(stats)
		for next_intent: Dictionary in _forecast.get("next_intents", []):
			if int(next_intent.get("enemy", -1)) == index:
				button.tooltip_text += "\n" + t("next_intent", {"text": _intent_text(next_intent)})
	_inventory()
	_asui = BattleActor.new()
	_asui.name = "Hero"
	add_child(_asui)
	_asui.setup(Art.actor("char.asui"), Vector2(130, 236))
	_hero_health = HealthReadout.instantiate()
	_hero_health.name = "PlayerHealth"
	_hero_health.position = Vector2(94, 246)
	add_child(_hero_health)
	_hero_health.update_values(state.get("player", {}), _health_forecast(_forecast), true, true)
	_damage = UI.label(self, "", Rect2(16, 232, 252, 20), UI.RED)
	_damage.hide()
	var energy: TextureRect = UI.texture(self, AssetCatalog, "ui.r3_simple_icon_energy", Rect2(14, 268, 32, 32))
	energy.modulate = Color.WHITE if int(state.get("energy", 0)) > 0 else Color(0.45, 0.45, 0.5)
	UI.label(self, "%d/3" % int(state.get("energy", 0)), Rect2(18, 300, 40, 18), SimpleUI.PAPER)
	var deck: Button = UI.button(self, str(state.get("draw_pile", []).size()), Rect2(8, 326, 58, 28), on_pile.bind("draw_pile"), "DrawPile")
	deck.icon = AssetCatalog.texture("ui.icon.r2_deck")
	deck.tooltip_text = t("draw_pile", {"count": state.get("draw_pile", []).size()})
	var discard: Button = UI.button(self, str(state.get("discard", []).size()), Rect2(574, 326, 58, 28), on_pile.bind("discard"), "DiscardPile")
	discard.icon = AssetCatalog.texture("ui.icon.r2_deck")
	discard.tooltip_text = t("discard_pile", {"count": state.get("discard", []).size()})
	var end: Button = UI.button(self, t("end_turn"), Rect2(552, 264, 80, 28), request_end_turn, "EndTurn")
	var can_play: bool = false
	for action: Dictionary in _legal:
		if action.get("type") == "play_card": can_play = true
	end.modulate = UI.WARM if not can_play else Color.WHITE
	for index: int in range(state.get("hand", []).size()): _build_card(index)
	_last_invalid = UI.paragraph(self, "", Rect2(86, 42, 172, 36), UI.PAPER)
	_last_invalid.add_theme_constant_override("line_spacing", 0)
	_build_decorations()
	_update_preview()

func _health_forecast(forecast: Dictionary, projected: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"hp_loss": int(forecast.get("hp_loss", forecast.get("damage", 0))), "incoming": int(forecast.get("incoming", 0))}
	if not projected.is_empty():
		result["preview_guard"] = int(projected.get("guard", 0))
	return result

func _inventory() -> void:
	for index: int in range(2):
		var kind: String = ["relics", "keepsakes"][index]
		var ids: Array = state.get(kind, [])
		if ids.is_empty(): continue
		var lines: Array[String] = []
		var origin: Vector2 = Vector2(10, 4) if index == 0 else Vector2(490, 4)
		var button: Button = UI.button(self, "", Rect2(origin, Vector2(mini(4, ids.size()) * 28, 28)), func() -> void: _show_rules("\n\n".join(lines)))
		for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
		for item_index: int in range(ids.size()):
			var item: Variant = ids[item_index]
			var id: String = str(item.get("id", "")) if item is Dictionary else str(item)
			var definition: Dictionary = ContentCatalog.entry(id)
			var spent: bool = _item_spent(id)
			var readiness: String = ContentCatalog.text("ui.d2.relic_spent" if spent else "ui.d2.relic_ready") if ContentCatalog.has_entry("ui.d2.relic_ready") else ""
			lines.append(str(definition.get("name", "")) + " · " + readiness + "\n" + str(definition.get("text", "")) + "\n" + str(definition.get("flavor", "")))
			var art: String = SimpleUI.item_art(str(definition.get("art", id)))
			if AssetCatalog.has_asset(art) and art != "ui.panel.default" and item_index < 4:
				var icon: TextureRect = UI.texture(button, AssetCatalog, art, Rect2(2 + item_index * 28, 2, 24, 24))
				icon.modulate = Color("8d8b93") if spent else Color.WHITE
				_item_icons[id] = icon
		button.tooltip_text = "\n\n".join(lines)

func _item_spent(id: String) -> bool:
	match id:
		"relic.lone_glove": return bool(state.get("turn_flags", {}).get("attack_played", false))
		"relic.birthday_candle": return int(state.get("battle_flags", {}).get("cards_played", 0)) > 0
		"keepsake.letter": return int(state.get("turn_flags", {}).get("special_played", 0)) > 0
		"keepsake.mianmian": return int(state.get("turn_flags", {}).get("first_attacker", -1)) >= 0
	return false

func _build_card(index: int) -> void:
	var instance: Dictionary = state["hand"][index]
	var card: Dictionary = ContentCatalog.entry(str(instance["id"]))
	var count: int = state.get("hand", []).size()
	var spacing: float = 58.0 if count == 8 else 60.0
	var home: Vector2 = Vector2((640 - 56 - (count - 1) * spacing) / 2 + index * spacing, 282)
	_hand_homes.append(home)
	var button: Button = UI.button(self, "", Rect2(home, Vector2(56, 76)), _card_clicked.bind(index), "Hand%d" % index)
	# Selection already begins on press. A later left release after right-cancel
	# must not emit another Button.pressed and resurrect the canceled preview.
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.gui_input.connect(_card_input.bind(index))
	button.mouse_entered.connect(_card_hover.bind(index))
	button.mouse_exited.connect(_card_unhover.bind(index))
	var frame_id: String = Art.card_frame(card)
	for style_name: String in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(style_name, SimpleUI.style(frame_id) if not frame_id.is_empty() else StyleBoxEmpty.new())
	UI.label(button, str(rules.card_cost(state, card)), Rect2(5, 5, 18, 16), UI.INK)
	var art_id: String = Art.card_art(card)
	if AssetCatalog.has_asset(art_id): UI.texture(button, AssetCatalog, art_id, Rect2(8, 16, 40, 28))
	var name_label: Label = UI.label(button, str(card.get("name", "")), Rect2(4, 44, 48, 16), UI.INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var summary: Dictionary = Art.effect(card, int(state.get("player", {}).get("guard", 0)))
	var effect_icon: TextureRect = UI.texture(button, AssetCatalog, str(summary["icon"]), Rect2(9, 58, 12, 12))
	effect_icon.size = Vector2(12, 12)
	UI.label(button, str(summary["text"]), Rect2(24, 58, 28, 16), UI.INK)
	button.tooltip_text = str(card.get("text", ""))
	var playable: bool = false
	for action: Dictionary in _legal:
		if action.get("type") == "play_card" and int(action.get("hand_index", -1)) == index: playable = true
	button.modulate = Color.WHITE if playable else Color("8d8b93")
	_hand_buttons.append(button)

func _card_color(card: Dictionary) -> Color:
	return UI.RED if card.get("type") == "attack" else (UI.BLUE if card.get("type") == "guard" else UI.WARM)

func _card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pressed_card = index if not _matching_actions(index).is_empty() else -1
		_drag_origin = _hand_buttons[index].position + event.position
		_dragging = false
		select_card(index)

func _card_clicked(index: int) -> void:
	# Press already selected it. A double click is the non-target-card shortcut.
	if _dragging:
		return
	select_card(index)

func select_card(index: int) -> void:
	if index < 0 or index >= state.get("hand", []).size() or _chooser != null:
		return
	selected = index
	if target < 0 or target >= state.get("enemies", []).size() or int(state["enemies"][target].get("hp", 0)) <= 0:
		target = _first_target()
	_cue("sfx.card_pick")
	_update_preview()

func _card_hover(index: int) -> void:
	hover_card = index
	_update_preview()

func _card_unhover(index: int) -> void:
	if is_queued_for_deletion() or not is_inside_tree(): return
	if hover_card == index:
		hover_card = -1
	_update_preview()

func _target_hover(index: int) -> void:
	if int(state["enemies"][index].get("hp", 0)) > 0:
		target = index
		_update_preview()

func _enemy_clicked(index: int) -> void:
	target = index
	if selected >= 0:
		confirm_selection()

func _first_target() -> int:
	for index: int in range(state.get("enemies", []).size()):
		if int(state["enemies"][index].get("hp", 0)) > 0:
			return index
	return -1

func _intent_for(index: int) -> Dictionary:
	for intent: Dictionary in _forecast.get("intents", []):
		if int(intent.get("enemy", -1)) == index:
			return intent
	return {}

func _intent_text(intent: Dictionary) -> String:
	var type: String = str(intent.get("type", "idle"))
	if type not in ["attack", "guard", "summon", "special", "idle", "buff"]:
		type = "special"
	var result: String = t("intent_" + type)
	if intent.has("amount"):
		result += " " + str(int(intent["amount"]))
	if int(intent.get("times", 1)) > 1:
		result += "×" + str(int(intent["times"]))
	return result

func _enemy_stat(enemy: Dictionary) -> String:
	return t("hp", {"hp": enemy.get("hp", 0), "max": enemy.get("max_hp", 0)}) + "\n" + t("guard", {"guard": enemy.get("guard", 0)})

func _matching_actions(index: int, selected_target: int = -999) -> Array:
	var matches: Array = []
	for action: Dictionary in _legal:
		if action.get("type") != "play_card" or int(action.get("hand_index", -1)) != index:
			continue
		if selected_target != -999 and int(action.get("target_index", -1)) not in [-1, selected_target]:
			continue
		matches.append(action)
	return matches

func _update_preview() -> void:
	if _damage == null:
		return
	for index: int in range(_enemy_values.size()):
		_enemy_values[index].text = _enemy_stat(state["enemies"][index])
		_enemy_buttons[index].modulate = UI.WARM if index == target and selected >= 0 else Color.WHITE
	for index: int in range(_hand_buttons.size()):
		_hand_buttons[index].position.y = _hand_homes[index].y - (12 if index == selected or index == hover_card else 0)
	_hero_health.update_values(state.get("player", {}), _health_forecast(_forecast), true, true)
	for enemy_index: int in range(_enemy_health.size()):
		_enemy_health[enemy_index].update_values(state["enemies"][enemy_index], {}, true, true)
	_damage.text = t("blocked") if int(_forecast.get("damage", 0)) == 0 else t("damage", {"damage": _forecast.get("damage", 0)})
	_damage.add_theme_color_override("font_color", UI.BLUE if int(_forecast.get("damage", 0)) == 0 else UI.RED)
	if _large != null:
		_large.queue_free()
		_large = null
	var index: int = hover_card if hover_card >= 0 else selected
	_update_rope()
	if index < 0:
		return
	var card: Dictionary = ContentCatalog.entry(str(state["hand"][index]["id"]))
	_large = UI.frame(self, "CardPreview", Rect2(190, 88, 112, 152))
	_large.mouse_filter = Control.MOUSE_FILTER_STOP
	_large.z_index = 3
	var frame_id: String = Art.card_frame(card)
	_large.add_theme_stylebox_override("panel", SimpleUI.style(frame_id) if not frame_id.is_empty() else StyleBoxEmpty.new())
	UI.label(_large, str(rules.card_cost(state, card)), Rect2(10, 10, 20, 16), UI.INK)
	var description: String = str(card.get("text", ""))
	var long_description: bool = description.length() > 18
	var art: String = Art.card_art(card)
	var illustration: Rect2 = Rect2(36, 20, 40, 28) if long_description else Rect2(16, 18, 80, 56)
	if AssetCatalog.has_asset(art):
		var image: TextureRect = UI.texture(_large, AssetCatalog, art, illustration)
		image.size = illustration.size
	var name_label: Label = UI.label(_large, str(card.get("name", "")), Rect2(10, 49 if long_description else 77, 92, 16), UI.INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var effect: Label = UI.paragraph(_large, description, Rect2(10, 67 if long_description else 96, 92, 76 if long_description else 34), UI.INK)
	effect.add_theme_constant_override("line_spacing", -1 if long_description else 0)
	if not long_description:
		var summary: Dictionary = Art.effect(card, int(state.get("player", {}).get("guard", 0)))
		var effect_icon: TextureRect = UI.texture(_large, AssetCatalog, str(summary["icon"]), Rect2(34, 128, 12, 12))
		effect_icon.size = Vector2(12, 12)
		UI.label(_large, str(summary["text"]), Rect2(50, 126, 44, 16), UI.INK)

	var actions: Array = _matching_actions(index, target if target >= 0 else _first_target())
	# Ambiguous effect selections are not silently guessed for a preview.
	if actions.size() == 1:
		var action: Dictionary = actions[0]
		var preview: Dictionary = rules.preview(state, index, int(action.get("target_index", -1)), action.get("choices", {}))
		if bool(preview.get("valid", false)):
			_show_projected_health(preview)

func _show_projected_health(preview: Dictionary) -> void:
	# Both direct-card and explicit-picker hover project the same actual result.
	# This never submits a command or alters the original rules/RNG state.
	var after: Dictionary = preview.get("forecast_after", {})
	_damage.text = t("damage_change", {"before": _forecast.get("damage", 0), "after": after.get("damage", 0)})
	var projected: Dictionary = preview.get("state", {})
	_hero_health.update_values(state.get("player", {}), _health_forecast(after, projected.get("player", {})), true, true)
	for enemy_index: int in range(mini(_enemy_values.size(), projected.get("enemies", []).size())):
		var before: Dictionary = state["enemies"][enemy_index]
		var next: Dictionary = projected["enemies"][enemy_index]
		_enemy_health[enemy_index].update_values(before, {"preview_hp": next.get("hp", 0), "preview_guard": next.get("guard", 0)}, true, true)
		if before.get("hp") != next.get("hp") or before.get("guard") != next.get("guard"):
			_enemy_values[enemy_index].text = t("enemy_change", {"before_hp": before.get("hp", 0), "after_hp": next.get("hp", 0), "before_guard": before.get("guard", 0), "after_guard": next.get("guard", 0)})

func confirm_selection() -> void:
	if selected < 0:
		return
	var actions: Array = _matching_actions(selected, target)
	if actions.is_empty():
		_invalid()
	elif actions.size() == 1:
		_commit(actions[0])
	else:
		show_action_picker(actions, t("pick_discard") if actions[0].get("choices", {}).has("discard_uid") else t("pick_free"))

func request_end_turn() -> void:
	var actions: Array = []
	for action: Dictionary in _legal:
		if action.get("type") == "end_turn":
			actions.append(action)
	if actions.size() == 1:
		_commit(actions[0])
	elif actions.size() > 1:
		show_action_picker(actions, t("pick_keep"))

func show_action_picker(actions: Array, heading: String) -> void:
	_picker_actions = actions
	_picker_page = 0
	_render_picker(heading)

func _render_picker(heading: String) -> void:
	if _chooser != null:
		_chooser.queue_free()
	_chooser = UI.frame(self, "ActionPicker", Rect2(60, 40, 520, 272))
	_chooser.z_index = 4
	UI.label(_chooser, heading, Rect2(26, 22, 468, 22), UI.INK)
	var offset: int = _picker_page * 6
	for local_index: int in range(mini(6, _picker_actions.size() - offset)):
		var action: Dictionary = _picker_actions[offset + local_index]
		var choice_button: Button = UI.button(_chooser, _action_text(action), Rect2(26, 48 + local_index * 28, 468, 26), _commit.bind(action))
		choice_button.tooltip_text = _action_text(action)
		choice_button.mouse_entered.connect(_preview_picker_action.bind(action))
	UI.button(_chooser, t("cancel"), Rect2(26, 222, 120, 28), cancel_selection)
	if _picker_actions.size() > 6:
		UI.button(_chooser, t("next"), Rect2(350, 222, 144, 28), func() -> void:
			_picker_page = (_picker_page + 1) % int(ceil(float(_picker_actions.size()) / 6.0))
			_render_picker(heading))

func _action_text(action: Dictionary) -> String:
	if action.get("type") == "end_turn":
		var keep: int = int(action.get("keep_index", -1))
		return t("keep_none") if keep < 0 else str(ContentCatalog.entry(str(state["hand"][keep]["id"])).get("name", ""))
	var choices: Dictionary = action.get("choices", {})
	if choices.has("discard_uid"):
		return _uid_name(str(choices["discard_uid"]), state.get("discard", []))
	if choices.has("other_uid"):
		var card_name: String = _uid_name(str(choices["other_uid"]), state.get("hand", []))
		var other_target: int = int(choices.get("other_target_index", -1))
		var target_name: String = t("no_target") if other_target < 0 else str(ContentCatalog.entry(str(state["enemies"][other_target]["id"])).get("name", ""))
		var result: String = t("choice_target", {"card": card_name, "target": target_name})
		var nested: Dictionary = choices.get("other_choices", {})
		if nested.has("discard_uid"):
			result += " · " + _uid_name(str(nested["discard_uid"]), state.get("discard", []))
		return result
	return t("confirm")

func _uid_name(uid: String, pile: Array) -> String:
	for instance: Dictionary in pile:
		if str(instance.get("uid", "")) == uid:
			return str(ContentCatalog.entry(str(instance["id"])).get("name", ""))
	return ""

func cancel_selection() -> void:
	if selected >= 0 or _chooser != null: _cue("sfx.ui_cancel")
	if _chooser != null:
		_chooser.queue_free()
		_chooser = null
	selected = -1
	hover_card = -1
	_pressed_card = -1
	_dragging = false
	_update_preview()

func _commit(action: Dictionary) -> void:
	if Engine.get_process_frames() < _input_ready_frame:
		return
	# Only commands supplied by legal_actions may leave this view.
	if not _legal.has(action):
		_invalid()
		return
	_input_ready_frame = Engine.get_process_frames() + 2
	on_command.call(action.duplicate(true))

func _invalid() -> void:
	_last_invalid.text = t("invalid")
	_cue("sfx.ui_deny")

func _show_rules(body: String) -> void:
	if _chooser != null:
		_chooser.queue_free()
	_chooser = UI.frame(self, "RuleDetails", Rect2(96, 62, 448, 236))
	_chooser.z_index = 4
	UI.label(_chooser, t("rules"), Rect2(26, 22, 396, 22), UI.INK)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(26, 48)
	scroll.size = Vector2(396, 122)
	_chooser.add_child(scroll)
	var text: Label = Label.new()
	text.text = body
	text.custom_minimum_size = Vector2(376, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_constant_override("line_spacing", 4)
	scroll.add_child(text)
	UI.button(_chooser, t("close"), Rect2(278, 184, 144, 30), cancel_selection)

func handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo or Engine.get_process_frames() < _input_ready_frame:
		return
	if event.keycode == KEY_ESCAPE:
		if selected >= 0 or _chooser != null:
			cancel_selection()
		else:
			on_pause.call()
		return
	if _chooser != null:
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_8:
		select_card(int(event.keycode - KEY_1))
	elif event.keycode in [KEY_LEFT, KEY_RIGHT]:
		var alive: Array[int] = []
		for index: int in range(state.get("enemies", []).size()):
			if int(state["enemies"][index].get("hp", 0)) > 0:
				alive.append(index)
		if not alive.is_empty():
			target = alive[posmod(alive.find(target) + (1 if event.keycode == KEY_RIGHT else -1), alive.size())]
			_update_preview()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		confirm_selection()
	elif event.keycode == KEY_E:
		request_end_turn()
	elif event.keycode == KEY_D:
		on_pile.call("draw_pile")
	elif event.keycode == KEY_F:
		on_pile.call("discard")

func _input(event: InputEvent) -> void:
	if not visible or _chooser != null:
		return
	if event is InputEventMouseMotion and _pressed_card >= 0:
		var pointer: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		_dragging = pointer.distance_to(_drag_origin) > 5
		_update_rope(pointer)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_selection()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click and selected >= 0:
			confirm_selection()
		elif not event.pressed and _pressed_card >= 0:
			if _dragging:
				var mouse: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
				if mouse.y >= 258:
					cancel_selection()
				else:
					var card: Dictionary = ContentCatalog.entry(str(state["hand"][selected]["id"]))
					if str(card.get("target", "none")) == "enemy":
						var hit: bool = false
						for index: int in range(_enemy_buttons.size()):
							if _enemy_buttons[index].get_rect().has_point(mouse):
								target = index
								hit = true
						if hit:
							confirm_selection()
						else:
							cancel_selection()
					else:
						confirm_selection()
			_pressed_card = -1
			_dragging = false

func _preview_picker_action(action: Dictionary) -> void:
	if action.get("type") != "play_card":
		return
	var preview: Dictionary = rules.preview(state, int(action["hand_index"]), int(action.get("target_index", -1)), action.get("choices", {}))
	if preview.get("valid", false):
		_show_projected_health(preview)

func present_events(events: Array) -> void:
	_event_queue.clear()
	_event_clock = 0.0
	var visible_events: Array = []
	for event: Dictionary in events:
		if event.get("type", "") in ["card_played", "enemy_action", "damage", "guard", "heal", "relic_proc", "keepsake_proc", "enemy_defeated", "draw", "shuffle", "turn_end", "victory", "defeat", "boss_warning", "spare_rope"]:
			visible_events.append(event.duplicate(true))
	var interval: float = minf(0.12, 1.1 / maxf(1.0, float(visible_events.size() - 1)))
	presentation_duration = 0.0 if visible_events.is_empty() else interval * float(visible_events.size() - 1) + 0.35
	for index: int in range(visible_events.size()):
		if index == 0 or instant_presentation:
			_present_event(visible_events[index])
		else:
			_event_queue.append({"at": interval * index, "event": visible_events[index]})

func _present_event(event: Dictionary) -> void:
	var kind: String = str(event.get("type", ""))
	_event_audio(event)
	if kind == "card_played" and _asui != null:
		_asui.pose("attack" if ContentCatalog.entry(str(event.get("id", ""))).get("type") == "attack" else "cast", 0.35)
	if kind == "enemy_action":
		var slot: int = int(event.get("enemy", -1))
		if _actors.has(slot):
			_actors[slot].pose("attack" if event.get("intent", {}).get("type") == "attack" else "cast", 0.25)
			_enemy_buttons[slot].modulate = UI.WARM
			_highlights.append({"node": _enemy_buttons[slot], "time": 0.0})
	if kind in ["relic_proc", "keepsake_proc"] and _item_icons.has(str(event.get("id", ""))):
		var icon: TextureRect = _item_icons[str(event["id"])]
		_proc_icons.append({"node": icon, "at": icon.position, "time": 0.0})
	if kind == "enemy_defeated" and _actors.has(int(event.get("enemy", -1))):
		_actors[int(event["enemy"])].pose("defeat")
	if kind not in ["damage", "guard", "heal"]: return
	var target_value: Variant = event.get("target", "player")
	var at: Vector2 = Vector2(108, 176)
	if target_value is int or target_value is float:
		var slot: int = int(target_value)
		if slot >= 0 and slot < _enemy_buttons.size():
			at = _enemy_buttons[slot].position + Vector2(32, 80)
			if kind == "damage" and _actors.has(slot): _actors[slot].pose("hit", 0.28)
	elif kind == "damage" and _asui != null:
		_asui.pose("hit", 0.28)
	at.y -= (_popups.size() % 2) * 18
	var text: String = ("−" if kind == "damage" else "+") + str(int(event.get("amount", 0)))
	var popup: Label = UI.label(self, text, Rect2(at, Vector2(80, 32)), UI.RED if kind == "damage" else (UI.HEAL if kind == "heal" else UI.BLUE), 24)
	_popups.append({"node": popup, "at": at, "time": 0.0})

func _event_audio(event: Dictionary) -> void:
	var kind: String = str(event.get("type", ""))
	var cue: String = {"draw": "sfx.draw", "shuffle": "sfx.shuffle", "guard": "sfx.guard_gain", "heal": "sfx.heal", "enemy_defeated": "sfx.enemy_poof", "turn_end": "sfx.end_turn", "relic_proc": "sfx.relic_proc", "keepsake_proc": "sfx.relic_proc", "boss_warning": "sting.boss_warn", "victory": "sting.victory", "defeat": "sting.defeat", "spare_rope": "sfx.rope_pull", "enemy_action": "sfx.intent_reveal"}.get(kind, "")
	if kind == "damage": cue = "sfx.hit_big" if int(event.get("amount", 0)) >= 12 else "sfx.hit_small"
	if kind == "card_played": cue = "sfx.card_play_" + str(ContentCatalog.entry(str(event.get("id", ""))).get("type", "special"))
	if not cue.is_empty(): _cue(cue)

func _process(delta: float) -> void:
	_event_clock += delta
	while not _event_queue.is_empty() and float(_event_queue[0]["at"]) <= _event_clock:
		_present_event(_event_queue.pop_front()["event"])
	for index: int in range(_highlights.size() - 1, -1, -1):
		var item: Dictionary = _highlights[index]
		item["time"] += delta
		if float(item["time"]) >= 0.22:
			item["node"].modulate = Color.WHITE
			_highlights.remove_at(index)
	for index: int in range(_popups.size() - 1, -1, -1):
		var item: Dictionary = _popups[index]
		item["time"] += delta
		item["node"].position = item["at"] - Vector2(0, floor(float(item["time"]) * 28.0))
		if float(item["time"]) >= 0.55:
			item["node"].queue_free()
			_popups.remove_at(index)
	for index: int in range(_proc_icons.size() - 1, -1, -1):
		var item: Dictionary = _proc_icons[index]
		item["time"] += delta
		item["node"].position = item["at"] - Vector2(0, 2 if int(float(item["time"]) * 12) % 2 == 0 else 0)
		if float(item["time"]) >= 0.5:
			item["node"].position = item["at"]
			_proc_icons.remove_at(index)

func _cue(id: String) -> void:
	if AudioService.has_cue(id): AudioService.play(id)

func _build_decorations() -> void:
	var boss: bool = str(state.get("encounter", {}).get("id", "")).contains("boss")
	for enemy: Dictionary in state.get("enemies", []):
		if str(enemy.get("id", "")).begins_with("boss."): boss = true
	var prefix: String = "table.snake_nest." if boss else "table.sock_marsh."
	var index: int = 0
	for definition: Dictionary in ContentCatalog.table("ui"):
		if not str(definition.get("id", "")).begins_with(prefix): continue
		var art: String = str(definition.get("art", "")) + ".small"
		# The new scene is the visible art. Keep the original easter-egg commands
		# on its scenery, rather than repainting the old procedural mini-icons.
		var hotspots: Dictionary = {
			"decor.clothesline.small": Rect2(536, 75, 64, 38),
			"decor.frog.small": Rect2(54, 215, 42, 21),
			"decor.bubbles.small": Rect2(255, 236, 40, 20),
			"decor.reeds.small": Rect2(0, 166, 48, 70),
			"decor.socks.small": Rect2(0, 150, 60, 50),
			"decor.yarn.small": Rect2(200, 220, 44, 26)
		}
		var rectangle: Rect2 = hotspots.get(art, Rect2(16 + index * 32, 210, 24, 16))
		var button: Button = UI.button(self, "", rectangle, _click_decoration.bind(definition, art, index))
		for style_name: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
		button.tooltip_text = str(definition.get("text", ""))
		button.name = "Decoration%d" % index
		index += 1

func _click_decoration(definition: Dictionary, _art: String, index: int) -> void:
	var id: String = str(definition["id"])
	decoration_counts[id] = int(decoration_counts.get(id, 0)) + 1
	var secret: bool = int(decoration_counts[id]) >= int(definition.get("click_threshold", 999)) and not bool(decoration_saved.get(id, false))
	if secret:
		decoration_counts[id] = 0
		if definition.get("once_per_save", false): decoration_saved[id] = true
	# Existing count, once-per-save, cue, dialogue and callback are unchanged.
	# Generated scenery already supplies the visible object; no old art is drawn.
	_cue(str(definition.get("sound", "")))
	_last_invalid.text = str(definition.get("secret_text" if secret else "normal_text", ""))
	if on_decoration.is_valid(): on_decoration.call(id, secret)

func _update_rope(mouse: Vector2 = Vector2(-1, -1)) -> void:
	if _rope_layer == null:
		_rope_layer = Control.new()
		_rope_layer.name = "TargetRope"
		_rope_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rope_layer.z_index = 2
		add_child(_rope_layer)
	for tile: TextureRect in _rope_tiles:
		tile.hide()
	if selected < 0 or selected >= _hand_buttons.size() or not AssetCatalog.has_asset("fx.r2_rope_strip"):
		return
	var card: Dictionary = ContentCatalog.entry(str(state["hand"][selected]["id"]))
	if str(card.get("target", "none")) != "enemy" and not _dragging:
		return
	var destination: Vector2 = mouse if _dragging and mouse.x >= 0 else Vector2(-1, -1)
	if destination.x < 0 and target >= 0 and target < _enemy_buttons.size():
		destination = _enemy_buttons[target].position + Vector2(_enemy_buttons[target].size.x / 2, 110)
	if destination.x < 0:
		return
	var origin: Vector2 = _hand_buttons[selected].position + Vector2(28, 6)
	var count: int = maxi(1, int(origin.distance_to(destination) / 6))
	for index: int in range(count + 1):
		if index >= _rope_tiles.size():
			var tile: TextureRect = UI.texture(_rope_layer, AssetCatalog, "fx.r2_rope_strip", Rect2(0, 0, 6, 4))
			# Imported strip width must not survive as the minimum control size.
			tile.size = Vector2(6, 4)
			_rope_tiles.append(tile)
		var position: Vector2 = origin.lerp(destination, float(index) / float(count))
		_rope_tiles[index].position = Vector2(Vector2i(position)) - Vector2(2, 2)
		_rope_tiles[index].show()
