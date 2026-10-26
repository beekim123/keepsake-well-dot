extends Control
## A projection of BattleRules. All legal commands, HP, intents and predictions
## come from the rules object; this script never resolves combat.
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
	UI.label(self, t("turn", {"turn": state.get("turn", 1)}), Rect2(16, 12, 130, 18), UI.WARM)
	var tutorial: bool = str(state.get("encounter", {}).get("id", "")) == "enc.tutorial"
	if tutorial:
		var hint: Panel = UI.frame(self, "TutorialStrip", Rect2(148, 7, 396, 26))
		UI.label(hint, t("tutorial"), Rect2(6, 5, 384, 18), UI.WARM)
	elif _forecast.get("warnings", []).is_empty():
		UI.label(self, t("graybox"), Rect2(152, 12, 390, 18), UI.MUTED)
	UI.button(self, t("pause"), Rect2(548, 8, 78, 28), on_pause)
	if AssetCatalog.has_asset("char.ma_ye"):
		var ma: AnimatedSprite2D = AnimatedSprite2D.new()
		ma.sprite_frames = AssetCatalog.frames("char.ma_ye", "idle")
		ma.position = Vector2(28, 78)
		add_child(ma)
		ma.play("idle")
	UI.paragraph(self, t("return_hint"), Rect2(56, 44, 88, 64), UI.MUTED)
	var enemies: Array = state.get("enemies", [])
	var boss_layout: bool = false
	for enemy: Dictionary in enemies:
		if str(enemy.get("id", "")).begins_with("boss."):
			boss_layout = true
	for index: int in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		var width: int = 168 if boss_layout and index == 0 else (98 if boss_layout else 112)
		var x: int = 152 + index * 118 if not boss_layout else (152 if index == 0 else 326 + (index - 1) * 100)
		var rect: Rect2 = Rect2(x, 32, width, 186)
		var button: Button = UI.button(self, "", rect, _enemy_clicked.bind(index), "Enemy%d" % index)
		button.disabled = int(enemy.get("hp", 0)) <= 0
		for style_name: String in ["normal", "disabled"]:
			button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
		button.mouse_entered.connect(_target_hover.bind(index))
		var definition: Dictionary = ContentCatalog.entry(str(enemy.get("id", "")))
		button.tooltip_text = str(definition.get("rule_text", definition.get("text", definition.get("mechanic_text", ""))))
		_enemy_buttons.append(button)
		var intent: Dictionary = _intent_for(index)
		button.tooltip_text = _intent_text(intent) + " · " + str(intent.get("name", "")) + "\n" + button.tooltip_text
		var intent_id: String = "intent." + str(intent.get("type", "special"))
		if AssetCatalog.has_asset(intent_id):
			UI.texture(button, AssetCatalog, intent_id, Rect2(4, 3, 16, 16))
		UI.label(button, _intent_text(intent), Rect2(22, 3, width - 24, 18), UI.RED)
		UI.label(button, str(definition.get("name", enemy.get("name", ""))), Rect2(8, 26, width - 16, 18), UI.WARM)
		var art_id: String = str(definition.get("art", enemy.get("id", "")))
		if art_id == "ui.panel.default" and AssetCatalog.has_asset(str(enemy.get("id", ""))):
			art_id = str(enemy["id"])
		if AssetCatalog.has_asset(art_id) and not AssetCatalog.metadata(art_id).get("animations", {}).is_empty():
			var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
			sprite.sprite_frames = AssetCatalog.frames(art_id, "idle")
			var dimensions: Vector2i = AssetCatalog.frame_size(art_id)
			sprite.position = Vector2(int(width / 2), 92 if dimensions.y == 120 else (104 if dimensions.y == 96 else 116))
			sprite.modulate.a = 0.35 if button.disabled else 1.0
			button.add_child(sprite)
			sprite.play("idle")
		var stats: Label = UI.paragraph(button, _enemy_stat(enemy), Rect2(8, 154, width - 16, 34), UI.BLUE)
		stats.add_theme_constant_override("line_spacing", 0)
		_enemy_values.append(stats)
		if _forecast.get("next_intents", []).size() > index:
			button.tooltip_text += "\n" + t("next_intent", {"text": _intent_text(_forecast["next_intents"][index])})
	var rule_texts: Array[String] = []
	for enemy: Dictionary in enemies:
		var definition: Dictionary = ContentCatalog.entry(str(enemy.get("id", "")))
		var rule_text: String = str(definition.get("rule_text", definition.get("mechanic_text", definition.get("mechanic", ""))))
		if not rule_text.is_empty():
			rule_texts.append(rule_text)
	var rule_button: Button = UI.button(self, t("rules"), Rect2(16, 118, 122, 30), _show_rules.bind("\n".join(rule_texts)))
	rule_button.tooltip_text = "\n".join(rule_texts)
	var warnings: Array = _forecast.get("warnings", [])
	if not warnings.is_empty():
		var warning: Dictionary = warnings[0]
		UI.label(self, t("warning", {"turns": warning.get("turns", 2), "amount": warning.get("amount", 16)}), Rect2(152, 10, 390, 20), UI.RED)
	_inventory()
	_damage = UI.label(self, "", Rect2(16, 232, 252, 20), UI.RED)
	var player: Dictionary = state.get("player", {})
	var portrait: Panel = UI.frame(self, "AsuiStats", Rect2(12, 264, 108, 76))
	var asui: AnimatedSprite2D = AnimatedSprite2D.new()
	asui.sprite_frames = AssetCatalog.frames("char.asui", "idle")
	asui.position = Vector2(28, 38)
	portrait.add_child(asui)
	asui.play("idle")
	UI.label(portrait, t("player_name"), Rect2(56, 7, 48, 16), UI.WARM)
	var hp_text: Label = UI.paragraph(portrait, t("hp", {"hp": player.get("hp", 0), "max": player.get("max_hp", 40)}), Rect2(56, 25, 48, 32))
	hp_text.add_theme_constant_override("line_spacing", 0)
	UI.label(portrait, t("guard", {"guard": player.get("guard", 0)}), Rect2(56, 56, 48, 16), UI.BLUE)
	UI.label(self, t("energy", {"energy": state.get("energy", 0)}), Rect2(270, 237, 82, 18), UI.WARM)
	UI.button(self, t("draw_pile", {"count": state.get("draw_pile", []).size()}), Rect2(354, 226, 78, 30), on_pile.bind("draw_pile"))
	UI.button(self, t("discard_pile", {"count": state.get("discard", []).size()}), Rect2(436, 226, 78, 30), on_pile.bind("discard"))
	var end: Button = UI.button(self, t("end_turn"), Rect2(518, 226, 110, 30), request_end_turn, "EndTurn")
	var can_play: bool = false
	for action: Dictionary in _legal:
		if action.get("type") == "play_card":
			can_play = true
	end.modulate = UI.WARM if not can_play else Color.WHITE
	for index: int in range(state.get("hand", []).size()):
		_build_card(index)
	UI.label(self, t("help"), Rect2(16, 344, 610, 14), UI.MUTED)
	_last_invalid = UI.label(self, "", Rect2(16, 211, 490, 18), UI.RED)
	_update_preview()

func _inventory() -> void:
	for index: int in range(2):
		var kind: String = ["relics", "keepsakes"][index]
		var ids: Array = state.get(kind, [])
		var lines: Array[String] = []
		for item: Variant in ids:
			var id: String = str(item.get("id", "")) if item is Dictionary else str(item)
			var definition: Dictionary = ContentCatalog.entry(id)
			lines.append(str(definition.get("name", "")) + " · " + str(definition.get("text", "")) + "\n" + str(definition.get("flavor", "")))
		var button: Button = UI.button(self, t(kind) + " " + str(ids.size()), Rect2(16, 158 + index * 32, 122, 28), _show_rules.bind("\n\n".join(lines)))
		button.tooltip_text = "\n\n".join(lines)

func _build_card(index: int) -> void:
	var instance: Dictionary = state["hand"][index]
	var card: Dictionary = ContentCatalog.entry(str(instance["id"]))
	var button: Button = UI.button(self, "", Rect2(132 + index * 60, 264, 56, 76), _card_clicked.bind(index), "Hand%d" % index)
	button.gui_input.connect(_card_input.bind(index))
	button.mouse_entered.connect(_card_hover.bind(index))
	button.mouse_exited.connect(_card_unhover.bind(index))
	var frame_id: String = "card.frame_s." + str(card.get("type", "special"))
	if AssetCatalog.has_asset(frame_id):
		for style_name: String in ["normal", "hover", "pressed"]:
			var style: StyleBoxTexture = StyleBoxTexture.new()
			style.texture = AssetCatalog.texture(frame_id)
			style.modulate_color = UI.WARM if style_name == "hover" else Color.WHITE
			button.add_theme_stylebox_override(style_name, style)
	UI.label(button, str(index + 1) + " · " + str(rules.card_cost(state, card)), Rect2(6, 4, 44, 16), UI.WARM)
	var art_id: String = "cardart." + str(card.get("type", "special")) + "_stub"
	if AssetCatalog.has_asset(art_id):
		UI.texture(button, AssetCatalog, art_id, Rect2(8, 23, 40, 28))
	UI.label(button, str(card.get("name", "")), Rect2(4, 54, 48, 18))
	var playable: bool = false
	for action: Dictionary in _legal:
		if action.get("type") == "play_card" and int(action.get("hand_index", -1)) == index:
			playable = true
	# Keep non-playable cards inspectable, but never create a command for them.
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
	AudioService.play("sfx.ui_click")
	_update_preview()

func _card_hover(index: int) -> void:
	hover_card = index
	_update_preview()

func _card_unhover(index: int) -> void:
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
		_hand_buttons[index].position.y = 260 if index == selected else 264
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
	_large = UI.frame(self, "CardPreview", Rect2(16, 72, 112, 152))
	_large.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_large.z_index = 3
	var frame_id: String = "card.frame_l." + str(card.get("type", "special"))
	if AssetCatalog.has_asset(frame_id):
		var frame_style: StyleBoxTexture = StyleBoxTexture.new()
		frame_style.texture = AssetCatalog.texture(frame_id)
		_large.add_theme_stylebox_override("panel", frame_style)
	UI.label(_large, str(card.get("name", "")), Rect2(8, 7, 96, 20), UI.WARM)
	UI.label(_large, t("view_card", {"cost": rules.card_cost(state, card), "type": t("type_" + str(card.get("type", "special")))}), Rect2(8, 30, 96, 20), _card_color(card))
	UI.paragraph(_large, str(card.get("text", "")), Rect2(8, 58, 96, 86))
	var actions: Array = _matching_actions(index, target if target >= 0 else _first_target())
	# Ambiguous effect selections are not silently guessed for a preview.
	if actions.size() == 1:
		var action: Dictionary = actions[0]
		var preview: Dictionary = rules.preview(state, index, int(action.get("target_index", -1)), action.get("choices", {}))
		if bool(preview.get("valid", false)):
			var after: Dictionary = preview.get("forecast_after", {})
			_damage.text = t("damage_change", {"before": _forecast.get("damage", 0), "after": after.get("damage", 0)})
			var projected: Dictionary = preview.get("state", {})
			for enemy_index: int in range(mini(_enemy_values.size(), projected.get("enemies", []).size())):
				var before: Dictionary = state["enemies"][enemy_index]
				var next: Dictionary = projected["enemies"][enemy_index]
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
	UI.label(_chooser, heading, Rect2(16, 14, 488, 22), UI.WARM)
	var offset: int = _picker_page * 6
	for local_index: int in range(mini(6, _picker_actions.size() - offset)):
		var action: Dictionary = _picker_actions[offset + local_index]
		var choice_button: Button = UI.button(_chooser, _action_text(action), Rect2(16, 44 + local_index * 30, 488, 28), _commit.bind(action))
		choice_button.tooltip_text = _action_text(action)
		choice_button.mouse_entered.connect(_preview_picker_action.bind(action))
	UI.button(_chooser, t("cancel"), Rect2(16, 232, 120, 28), cancel_selection)
	if _picker_actions.size() > 6:
		UI.button(_chooser, t("next"), Rect2(360, 232, 144, 28), func() -> void:
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
	AudioService.play("sfx.ui_click")

func _show_rules(body: String) -> void:
	if _chooser != null:
		_chooser.queue_free()
	_chooser = UI.frame(self, "RuleDetails", Rect2(96, 62, 448, 236))
	_chooser.z_index = 4
	UI.label(_chooser, t("rules"), Rect2(16, 14, 416, 22), UI.WARM)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.position = Vector2(16, 46)
	scroll.size = Vector2(416, 128)
	_chooser.add_child(scroll)
	var text: Label = Label.new()
	text.text = body
	text.custom_minimum_size = Vector2(396, 0)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_constant_override("line_spacing", 4)
	scroll.add_child(text)
	UI.button(_chooser, t("close"), Rect2(288, 190, 144, 30), cancel_selection)

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
		_damage.text = t("damage_change", {"before": _forecast.get("damage", 0), "after": preview.get("forecast_after", {}).get("damage", 0)})

func present_events(events: Array) -> void:
	var count: int = 0
	for event: Dictionary in events:
		var kind: String = str(event.get("type", ""))
		if kind not in ["damage", "guard", "heal"] or count >= 4:
			continue
		var target_value: Variant = event.get("target", "player")
		var at: Vector2 = Vector2(26, 236)
		if target_value is int or target_value is float:
			var slot: int = int(target_value)
			if slot >= 0 and slot < _enemy_buttons.size():
				at = _enemy_buttons[slot].position + Vector2(32, 80)
		at.y -= (count % 2) * 18
		var text: String = ("−" if kind == "damage" else "+") + str(int(event.get("amount", 0)))
		var popup: Label = UI.label(self, text, Rect2(at, Vector2(80, 26)), UI.RED if kind == "damage" else UI.BLUE, 24)
		var tween: Tween = create_tween().set_parallel(true)
		tween.tween_property(popup, "position:y", at.y - 16, 0.55)
		tween.tween_property(popup, "modulate:a", 0.0, 0.55)
		tween.chain().tween_callback(popup.queue_free)
		count += 1

func _update_rope(mouse: Vector2 = Vector2(-1, -1)) -> void:
	if _rope_layer == null:
		_rope_layer = Control.new()
		_rope_layer.name = "TargetRope"
		_rope_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rope_layer.z_index = 2
		add_child(_rope_layer)
	for tile: TextureRect in _rope_tiles:
		tile.hide()
	if selected < 0 or selected >= _hand_buttons.size() or not AssetCatalog.has_asset("ui.target_rope"):
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
			var tile: TextureRect = UI.texture(_rope_layer, AssetCatalog, "ui.target_rope", Rect2(0, 0, 4, 4))
			_rope_tiles.append(tile)
		var position: Vector2 = origin.lerp(destination, float(index) / float(count))
		_rope_tiles[index].position = Vector2(Vector2i(position)) - Vector2(2, 2)
		_rope_tiles[index].show()
