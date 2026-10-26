extends RefCounted
## Pure battle contracts: data is injected, no files, scenes, nodes or resources.
## Controlled dictionaries are fixtures, not bypasses used by gameplay or bots.
const Rules = preload("res://scripts/core/battle_rules.gd")
const Rng = preload("res://scripts/core/rng.gd")
const Bot = preload("res://scripts/core/policy_bot.gd")
const GoldenReplay = preload("res://tests/battle/golden_replay.gd")
var _defs: Dictionary = {}
var _rules: RefCounted
var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _uid: int = 10000
var _stress: Dictionary = {}

func run(definitions: Dictionary) -> Dictionary:
	_passed = 0
	_failed = 0
	_failures.clear()
	_uid = 10000
	_stress = {}
	var source_before: String = JSON.stringify(definitions)
	_defs = definitions.duplicate(true)
	_rules = Rules.new(_defs)
	_test_start_and_validation()
	_test_cards()
	_test_relics()
	_test_keepsakes()
	_test_enemies()
	_test_edges_and_forecasts()
	_test_replay_and_randomness()
	_test_coupled_boundaries()
	_test_activation_order_and_policy()
	_test_golden_replay()
	_test_bot_stress()
	_test_retry_and_phase_cancellations()
	_test_adversarial_parity()
	_test_lethal_forecast_semantics()
	_equal(JSON.stringify(_defs), source_before, "entire suite preserves every injected definition")
	_equal(JSON.stringify(definitions), source_before, "entire suite leaves caller-owned definitions unchanged")
	return {"passed": _passed, "failed": _failed, "failures": _failures, "scope": "pure D1 battle rules; not a human-fun or full-expedition claim", "combat_stress": _stress}

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS battle: " + label)
	else:
		_failed += 1
		_failures.append(label)
		printerr("FAIL battle: " + label)

func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label + (" [actual=" + str(actual) + ", expected=" + str(expected) + "]" if actual != expected else ""))

func _run_fixture(relics: Array = [], keepsakes: Array = [], extra: Dictionary = {}) -> Dictionary:
	var run_state: Dictionary = {"hp": 40, "max_hp": 40, "deck": ["card.knock", "card.knock", "card.knock", "card.knock", "card.brace", "card.brace", "card.brace", "card.brace", "card.rope_lasso", "card.tug"], "relics": relics.duplicate(), "keepsakes": keepsakes.duplicate(), "next_battle": {}, "spare_rope_available": false, "spare_rope_used": false}
	run_state.merge(extra, true)
	return run_state

func _state(enemy_ids: Array = ["enemy.wet_sock"], relics: Array = [], keepsakes: Array = [], extra: Dictionary = {}) -> Dictionary:
	return _rules.start({"id": "enc.test", "enemies": enemy_ids}, _run_fixture(relics, keepsakes, extra), 73191).state

func _card(id: String) -> Dictionary:
	_uid += 1
	return {"id": id, "uid": "test.card." + str(_uid)}

func _cards(ids: Array) -> Array:
	var result: Array = []
	for id: String in ids:
		result.append(_card(id))
	return result

func _hand(state: Dictionary, ids: Array, draw_ids: Array = ["card.brace", "card.knock", "card.brace", "card.knock", "card.brace", "card.knock"]) -> void:
	state.hand = _cards(ids)
	state.draw_pile = _cards(draw_ids)
	state.discard = []

func _durable(state: Dictionary, hp: int = 1000) -> void:
	for enemy: Dictionary in state.enemies:
		enemy.hp = hp
		enemy.max_hp = hp
		enemy.guard = 0

func _count_events(events: Array, type: String) -> int:
	var result: int = 0
	for event: Dictionary in events:
		if event.get("type", "") == type:
			result += 1
	return result

func _event_index(events: Array, type: String) -> int:
	for index: int in range(events.size()):
		if events[index].get("type", "") == type:
			return index
	return -1

func _living(state: Dictionary) -> int:
	var result: int = 0
	for enemy: Dictionary in state.enemies:
		if int(enemy.hp) > 0:
			result += 1
	return result

func _contains_uid(cards: Array, uid: Variant) -> bool:
	for card: Dictionary in cards:
		if card.uid == uid:
			return true
	return false

func _execute(state: Dictionary, action: Dictionary) -> Array:
	if action.type == "end_turn":
		return _rules.end_turn(state, int(action.get("keep_index", -1)))
	return _rules.play_card(state, int(action.hand_index), int(action.get("target_index", -1)), action.get("choices", {}))

func _test_start_and_validation() -> void:
	var original: Dictionary = _run_fixture([], [], {"hp": 23})
	var before: Dictionary = original.duplicate(true)
	var encounter: Dictionary = {"id": "enc.test", "enemies": ["enemy.wet_sock"]}
	var result: Dictionary = _rules.start(encounter, original, 431)
	var state: Dictionary = result.state
	_equal(original, before, "start does not mutate expedition snapshot")
	_equal(encounter, {"id": "enc.test", "enemies": ["enemy.wet_sock"]}, "start does not mutate encounter definition")
	_equal(state.status, "player", "battle starts in player phase")
	_equal(state.turn, 1, "first turn is numbered one")
	_equal(state.energy, 3, "first turn refills three energy")
	_equal(state.hand.size(), 4, "first turn draws four cards")
	_equal(state.draw_pile.size(), 6, "ten-card starter leaves six in draw pile")
	_equal(state.player.hp, 23, "battle start preserves expedition HP")
	_equal(state.enemies[0].hp, 12, "wet sock starts with authored HP")
	_check(state.enemies[0].has("intent"), "first enemy intent is public immediately")
	var uids: Array = []
	for card: Dictionary in state.hand + state.draw_pile:
		uids.append(card.uid)
	var unique: Dictionary = {}
	for uid: Variant in uids:
		unique[uid] = true
	_equal(unique.size(), 10, "duplicate card definitions have unique instance IDs")
	for invalid: Dictionary in [{"hand_index": -1, "target_index": 0}, {"hand_index": 999, "target_index": 0}]:
		before = state.duplicate(true)
		_rules.play_card(state, invalid.hand_index, invalid.target_index)
		_equal(state, before, "invalid hand index cannot mutate state or RNG " + str(invalid.hand_index))
	_hand(state, ["card.knock"])
	for invalid_target: int in [-1, 1, 999]:
		before = state.duplicate(true)
		_rules.play_card(state, 0, invalid_target)
		_equal(state, before, "invalid enemy target cannot mutate state " + str(invalid_target))
	state.energy = 0
	before = state.duplicate(true)
	_rules.play_card(state, 0, 0)
	_equal(state, before, "unaffordable card is rejected transactionally")
	_hand(state, ["card.dust_off"])
	_rules.play_card(state, 0, 0)
	_equal(state.enemies[0].hp, 9, "zero-cost card remains playable at zero energy")
	before = state.duplicate(true)
	_rules.end_turn(state, 999)
	_equal(state, before, "invalid bookmark index does not advance enemy turn")
	_check(not _rules.legal_actions(state).is_empty(), "nonterminal state always exposes legal end turn")

func _test_cards() -> void:
	for item: Array in [["card.knock", 6, 1], ["card.double_tap", 6, 1], ["card.big_hammer", 14, 2], ["card.dust_off", 3, 0]]:
		var state: Dictionary = _state()
		_durable(state)
		_hand(state, [item[0]])
		var events: Array = _rules.play_card(state, 0, 0)
		_equal(state.enemies[0].hp, 1000 - int(item[1]), str(item[0]) + " deals authored damage")
		_equal(state.energy, 3 - int(item[2]), str(item[0]) + " pays authored cost once")
		if item[0] == "card.double_tap":
			_equal(_count_events(events, "damage"), 2, "double tap resolves two separate damage hits")
	for item: Array in [["card.brace", 5, 1], ["card.curl_up", 7, 1], ["card.clothesline", 12, 2], ["card.blanket", 3, 0]]:
		var state: Dictionary = _state()
		_hand(state, [item[0]])
		_rules.play_card(state, 0)
		_equal(state.player.guard, item[1], str(item[0]) + " gains authored guard")
		_equal(state.energy, 3 - int(item[2]), str(item[0]) + " pays authored cost")
	var state: Dictionary = _state(["enemy.wet_sock", "enemy.lonely_sock", "enemy.clothespin"])
	_hand(state, ["card.rope_lasso"])
	_rules.play_card(state, 0)
	_equal([state.enemies[0].hp, state.enemies[1].hp, state.enemies[2].hp], [8, 14, 6], "rope lasso damages every living enemy")
	for item: Array in [["card.tug", 2], ["card.pocket", 1]]:
		state = _state()
		_hand(state, [item[0]])
		_rules.play_card(state, 0)
		_equal(state.hand.size(), item[1], str(item[0]) + " draws authored number")
	state = _state()
	_hand(state, ["card.yank"])
	_rules.play_card(state, 0, 0)
	_equal([state.enemies[0].hp, state.hand.size()], [7, 1], "yank damages then draws")
	state = _state()
	_hand(state, ["card.wring"])
	state.player.guard = 9
	_rules.play_card(state, 0, 0)
	_equal([state.enemies[0].hp, state.player.guard], [3, 9], "wring deals current guard without spending it")
	state = _state()
	_hand(state, ["card.push_back"])
	_rules.play_card(state, 0)
	_equal(state.player.guard, 4, "push back grants four guard")
	_rules.end_turn(state)
	_equal([state.player.hp, state.enemies[0].hp], [39, 9], "push back retaliates after an enemy attack")
	_rules.end_turn(state)
	_equal(state.enemies[0].hp, 9, "push back expires at next player turn start")
	state = _state()
	_hand(state, ["card.deep_breath"])
	_rules.play_card(state, 0)
	_equal(state.energy, 2, "deep breath spends energy now")
	_rules.end_turn(state)
	_equal(state.energy, 5, "deep breath adds energy next turn")
	_rules.end_turn(state)
	_equal(state.energy, 3, "deep breath bonus does not leak into later turns")
	for item: Array in [["card.knot", 5, 0], ["card.whisper", 4, 0], ["card.whisper_plus", 4, 4]]:
		state = _state()
		_hand(state, [item[0]])
		_rules.play_card(state, 0, 0)
		_equal(state.enemies[0].weaken, item[1], str(item[0]) + " weakens next attack")
		_equal(state.player.guard, item[2], str(item[0]) + " grants correct extra guard")
		_rules.end_turn(state)
		_equal(state.enemies[0].weaken, 0, str(item[0]) + " is consumed by attack intent")
	state = _state()
	_hand(state, ["card.shake_rope", "card.shake_rope"])
	_rules.play_card(state, 0, 0)
	var before: Dictionary = state.duplicate(true)
	_rules.play_card(state, 0, 0)
	_equal(state, before, "shake rope second copy cannot bypass once-per-battle limit")
	_rules.end_turn(state)
	_equal(state.player.hp, 40, "shake rope replaces next enemy action with idle")
	_rules.end_turn(state)
	_equal(state.player.hp, 35, "shake rope skips one action not the entire enemy cycle")
	state = _state()
	_hand(state, ["card.pick_up"])
	var recovered: Dictionary = _card("card.big_hammer")
	state.discard = [recovered]
	_rules.play_card(state, 0, -1, {"discard_uid": recovered.uid})
	_check(_contains_uid(state.hand, recovered.uid), "pick up returns specifically selected discard instance")
	for card_id: String in ["card.vow", "card.vow_plus"]:
		state = _state()
		_hand(state, [card_id, "card.brace"])
		state.player.guard = 2
		_rules.play_card(state, 0)
		_equal(state.player.guard, 2, card_id + " does not multiply existing guard")
		_rules.play_card(state, 0)
		_equal(state.player.guard, 12, card_id + " doubles guard gained afterward")
		_equal(state.energy, 1 if card_id == "card.vow" else 2, card_id + " has correct base/plus cost")
		_rules.end_turn(state)
		_hand(state, ["card.brace"])
		_rules.play_card(state, 0)
		_equal(state.player.guard, 5, card_id + " guard multiplier expires next player turn")
	for card_id: String in ["card.deliver", "card.deliver_plus"]:
		state = _state()
		_durable(state)
		_hand(state, [card_id, "card.big_hammer"])
		var selected: Variant = state.hand[1].uid
		_rules.play_card(state, 0, -1, {"other_uid": selected, "other_target_index": 0})
		_equal(state.enemies[0].hp, 986, card_id + " executes selected card for free")
		_equal(state.energy, 2 if card_id == "card.deliver" else 3, card_id + " only pays delivery cost")
		_equal(state.hand.size(), 0, card_id + " consumes both physical hand cards")

func _test_relics() -> void:
	var state: Dictionary = _state(["enemy.wet_sock", "enemy.lonely_sock"], ["relic.lone_glove"])
	_durable(state)
	_hand(state, ["card.knock", "card.knock"])
	var events: Array = _rules.play_card(state, 0, 0)
	_equal(state.enemies[0].hp, 988, "lone glove repeats first attack card effects")
	_equal(state.energy, 2, "lone glove pays only one card cost")
	_equal(_count_events(events, "card_played"), 1, "lone glove does not recurse card-play hooks")
	_rules.play_card(state, 0, 0)
	_equal(state.enemies[0].hp, 982, "lone glove does not repeat second attack that turn")
	_rules.end_turn(state)
	_hand(state, ["card.knock"])
	_rules.play_card(state, 0, 0)
	_equal(state.enemies[0].hp, 970, "lone glove refreshes next turn")
	state = _state(["enemy.wet_sock", "enemy.lonely_sock"], ["relic.lone_glove"])
	state.enemies[0].hp = 4
	_hand(state, ["card.knock"])
	_rules.play_card(state, 0, 0)
	_equal([state.enemies[0].hp, state.enemies[1].hp], [0, 18], "lone glove does not silently retarget after first strike defeats target")
	state = _state(["enemy.wet_sock"], ["relic.spyglass"])
	_check(not _rules.forecast(state).get("next_intents", []).is_empty(), "spyglass exposes an additional enemy intent")
	state = _state()
	_check(_rules.forecast(state).get("next_intents", []).is_empty(), "extra intent is not shown without spyglass")
	state = _state(["enemy.wet_sock", "enemy.lonely_sock"], ["relic.lost_kite"])
	_hand(state, ["card.brace"])
	_rules.play_card(state, 0)
	_equal(int(state.enemies[0].hp) + int(state.enemies[1].hp), 28, "lost kite damages exactly one random enemy for two")
	_equal(state.player.guard, 5, "lost kite keeps the guard card's primary effect")
	state = _state(["enemy.wet_sock"], ["relic.open_ink"])
	_equal(state.hand.size(), 5, "open ink adds one opening draw")
	_rules.end_turn(state)
	_equal(state.hand.size(), 5, "open ink adds one draw every turn")
	state = _state(["enemy.wet_sock"], ["relic.half_biscuit"], [], {"hp": 32})
	state.enemies[0].hp = 1
	_hand(state, ["card.knock"])
	_rules.play_card(state, 0, 0)
	_equal([state.status, state.player.hp], ["victory", 36], "half biscuit heals four on victory")
	state = _state(["enemy.wet_sock"], ["relic.half_biscuit"], [], {"hp": 39})
	state.enemies[0].hp = 1
	_hand(state, ["card.knock"])
	_rules.play_card(state, 0, 0)
	_equal(state.player.hp, 40, "half biscuit healing cannot exceed max HP")
	state = _state(["enemy.wet_sock"], ["relic.offkey_harmonica"])
	_rules.end_turn(state)
	_equal(state.player.hp, 40, "harmonica converts all three leftover energy before incoming attack")
	state = _state(["enemy.wet_sock"], ["relic.offkey_harmonica"])
	state.energy = 1
	_rules.end_turn(state)
	_equal(state.player.hp, 38, "harmonica grants exactly three guard per leftover energy")
	state = _state(["enemy.wet_sock"], ["relic.empty_frame"], [], {"deck": ["card.knock", "card.brace", "card.big_hammer", "card.clothesline"]})
	_equal(state.hand.size(), 5, "empty frame adds one temporary copy after first draw")
	var original_highest: Dictionary = {}
	var highest_cost: int = -1
	for index: int in range(4):
		var instance: Dictionary = state.hand[index]
		var cost: int = _card_cost(instance.id)
		if cost > highest_cost:
			highest_cost = cost
			original_highest = instance
	_equal(state.hand[4].id, original_highest.id, "empty frame chooses leftmost maximum-cost card on a tie")
	_check(state.hand[4].uid != original_highest.uid, "empty frame copy gets a distinct instance ID")
	state = _state(["enemy.wet_sock"], ["relic.leaky_balloon"])
	state.player.guard = 10
	_rules.end_turn(state)
	_equal(state.player.guard, 2, "leaky balloon halves remaining guard with integer floor")
	state = _state(["enemy.wet_sock"], ["relic.crooked_compass"])
	_equal(state.hand.size(), 7, "crooked compass adds three first-turn cards")
	_rules.end_turn(state)
	_equal(state.hand.size(), 4, "crooked compass does not add cards on later turns")
	state = _state(["enemy.wet_sock"], ["relic.bookmark"])
	var kept_uid: Variant = state.hand[2].uid
	_rules.end_turn(state, 2)
	_equal(state.hand.size(), 5, "bookmark keeps one card plus four new draws")
	_check(_contains_uid(state.hand, kept_uid), "bookmark keeps the exact chosen instance")
	state = _state(["enemy.wet_sock"], ["relic.shedding_brush"])
	state.enemies[0].guard = 2
	_hand(state, ["card.knock"])
	_rules.play_card(state, 0, 0)
	_equal([state.enemies[0].guard, state.enemies[0].hp], [0, 5], "shedding brush adds three damage against a guarded enemy")
	state = _state(["enemy.wet_sock"], ["relic.shedding_brush"])
	_hand(state, ["card.knock"])
	_rules.play_card(state, 0, 0)
	_equal(state.enemies[0].hp, 6, "shedding brush does not boost attacks on unguarded enemies")
	state = _state(["enemy.wet_sock"], ["relic.tangled_earbuds"])
	_hand(state, ["card.blanket", "card.blanket", "card.blanket", "card.blanket"])
	_rules.play_card(state, 0)
	_rules.play_card(state, 0)
	_equal(state.hand.size(), 2, "earbuds does not trigger before third card")
	_rules.play_card(state, 0)
	_equal(state.hand.size(), 2, "earbuds draws exactly one on third card")
	_rules.play_card(state, 0)
	_equal(state.hand.size(), 1, "earbuds does not trigger again on fourth card")
	state = _state(["enemy.wet_sock"], ["relic.flat_ball"])
	state.player.guard = 5
	_rules.end_turn(state)
	_equal(state.enemies[0].hp, 7, "flat ball retaliates when an attack exactly breaks positive guard")
	state = _state(["enemy.wet_sock"], ["relic.flat_ball"])
	_rules.end_turn(state)
	_equal(state.enemies[0].hp, 12, "flat ball does not proc when player had no guard")
	state = _state(["enemy.wet_sock"], ["relic.birthday_candle"])
	_durable(state)
	_hand(state, ["card.knock", "card.knock"])
	_rules.play_card(state, 0, 0)
	_equal(state.enemies[0].hp, 988, "birthday candle doubles first card numeric effects")
	_rules.play_card(state, 0, 0)
	_equal(state.enemies[0].hp, 982, "birthday candle does not double subsequent card")
	state = _state(["enemy.wet_sock", "enemy.lonely_sock"], ["relic.odd_button"])
	state.enemies[0].hp = 1
	_hand(state, ["card.knock"])
	_rules.play_card(state, 0, 0)
	_equal(state.energy, 3, "odd button refunds one energy for each enemy defeated")
	# Coupled regression: brush applies to each current shield state, not a stale
	# snapshot; candle scales card damage, glove repeats, neither repeats hooks.
	state = _state(["enemy.wet_sock"], ["relic.lone_glove", "relic.birthday_candle", "relic.shedding_brush"])
	_durable(state)
	state.enemies[0].guard = 5
	_hand(state, ["card.double_tap"])
	var preview: Dictionary = _rules.preview(state, 0, 0)
	events = _rules.play_card(state, 0, 0)
	_equal(state.enemies[0].hp, 978, "glove+candle+brush reevaluates guard after each of four hits")
	_equal(_count_events(events, "damage"), 4, "glove+candle double tap produces four nonrecursive hits")
	_equal(_count_events(events, "card_played"), 1, "combined glove/candle emit one card-play event")
	_equal(preview.state, state, "combined glove+candle+brush preview matches actual full state")

func _card_cost(id: String) -> int:
	for definition: Dictionary in _defs.cards:
		if definition.id == id:
			return int(definition.cost)
	return -1

func _test_keepsakes() -> void:
	var state: Dictionary = _state(["enemy.wet_sock"], [], ["keepsake.ring"])
	_equal(state.player.guard, 3, "ring grants guard on first player turn")
	_rules.end_turn(state)
	_equal([state.player.hp, state.player.guard], [38, 3], "ring applies after old guard clears every turn")
	state = _state(["enemy.wet_sock"], ["relic.leaky_balloon"], ["keepsake.ring"])
	state.player.guard = 10
	_rules.end_turn(state)
	_equal(state.player.guard, 5, "balloon halves remaining guard before ring grants new guard")
	state = _state(["enemy.wet_sock", "enemy.wet_sock"], [], ["keepsake.mianmian"])
	_equal(_rules.forecast(state).damage, 7, "mianmian reduces only first attacking enemy in forecast")
	_rules.end_turn(state)
	_equal(state.player.hp, 33, "mianmian reduces first attacker by three, not both enemies")
	state = _state(["enemy.wet_sock"], [], ["keepsake.letter"])
	_hand(state, ["card.tug", "card.deep_breath"])
	_rules.play_card(state, 0)
	_equal(state.energy, 3, "letter makes first special card free")
	_rules.play_card(state, 0)
	_equal(state.energy, 2, "letter does not discount second special card")
	_rules.end_turn(state)
	_hand(state, ["card.tug"])
	var energy_before: int = state.energy
	_rules.play_card(state, 0)
	_equal(state.energy, energy_before, "letter refreshes its free special on next turn")
	state = _state(["enemy.wet_sock"], [], ["keepsake.letter"])
	_hand(state, ["card.pocket", "card.deep_breath"])
	_rules.play_card(state, 0)
	_rules.play_card(state, 0)
	_equal(state.energy, 2, "zero-cost special still consumes letter's first-special trigger")

func _test_enemies() -> void:
	var cases: Array = [
		["enemy.wet_sock", [5, 5, 0, 5], [0, 0, 4, 0]],
		["enemy.lonely_sock", [7, 0, 7], [0, 6, 0]],
		["enemy.lint_bug", [3, 3, 0, 3], [0, 0, 4, 0]],
		["enemy.stinky_insole", [4, 8, 4], [0, 0, 0]],
		["enemy.clothespin", [4, 4, 8, 4], [0, 0, 0, 0]],
		["enemy.soap_bubble", [0, 2, 0], [3, 0, 3]],
		["enemy.sock_kid", [3, 3], [0, 0]],
		["elite.hungry_drawer", [0, 9, 8, 0, 9, 8, 0], [6, 0, 0, 8, 0, 0, 10]]
	]
	for item: Array in cases:
		var state: Dictionary = _state([item[0]], [], [], {"hp": 1000, "max_hp": 1000})
		for cycle_step: int in range(item[1].size()):
			var hp_before: int = state.player.hp
			var expected: int = item[1][cycle_step]
			_equal(_rules.forecast(state).damage, expected, str(item[0]) + " forecast cycle step " + str(cycle_step))
			_rules.end_turn(state)
			_equal(hp_before - int(state.player.hp), expected, str(item[0]) + " executes damage cycle step " + str(cycle_step))
			_equal(state.enemies[0].guard, item[2][cycle_step], str(item[0]) + " guard cycle step " + str(cycle_step))
			if item[0] == "enemy.stinky_insole":
				_equal(state.hand.size(), 3 if cycle_step % 2 == 0 else 4, "stinky insole draw penalty applies once at next draw")
	var state: Dictionary = _state(["enemy.soap_bubble", "enemy.wet_sock"])
	_rules.end_turn(state)
	_equal([state.enemies[0].guard, state.enemies[1].guard], [3, 3], "soap bubble guard intent protects all living enemies")
	state = _state(["elite.hungry_drawer"], [], ["keepsake.mianmian"], {"hp": 1000, "max_hp": 1000})
	_rules.end_turn(state)
	_rules.end_turn(state)
	_equal(_rules.forecast(state).damage, 2, "mianmian reduction applies separately to both hits of first attacking enemy")
	var hp_before: int = state.player.hp
	_rules.end_turn(state)
	_equal(hp_before - int(state.player.hp), 2, "mianmian multiattack forecast matches two reduced actual hits")
	state = _state(["elite.hungry_drawer"])
	_hand(state, ["card.knot"])
	_rules.play_card(state, 0, 0)
	_rules.end_turn(state)
	_equal(state.enemies[0].weaken, 5, "weaken survives enemy nonattack guard intention")
	_equal(_rules.forecast(state).damage, 4, "stored weaken modifies next attack intent immediately")
	_rules.end_turn(state)
	_equal(state.enemies[0].weaken, 0, "stored weaken is consumed only by an actual attack intention")
	state = _state(["boss.sock_snake"], [], [], {"hp": 1000, "max_hp": 1000})
	_equal(_rules.forecast(state).damage, 8, "sock snake first intent is tail eight")
	_rules.end_turn(state)
	_equal(_living(state), 2, "sock snake spawns one minion at enemy turn end")
	_equal(state.enemies[1].id, "enemy.sock_kid", "boss summon uses authored sock-kid definition")
	_equal(state.enemies[1].hp, 4, "summoned sock kid has four HP")
	_equal(state.player.hp, 992, "new minion does not attack on its spawn turn")
	_rules.end_turn(state)
	_equal([state.enemies[0].guard, _living(state)], [8, 3], "boss gains three guard per preexisting minion then five from coil")
	state.enemies[0].hp = 50
	_rules.end_turn(state)
	_equal(state.enemies[0].hp, 56, "swallow consumes a sock and heals six")
	_equal(_living(state), 3, "swallow removes one minion before end-turn replacement summon")
	state = _state(["boss.sock_snake"], [], [], {"hp": 1000, "max_hp": 1000})
	_rules.end_turn(state)
	_rules.end_turn(state)
	_hand(state, ["card.rope_lasso"])
	_rules.play_card(state, 0)
	_equal(_living(state), 1, "rope lasso clears all four-HP sock minions")
	_equal(_rules.forecast(state).damage, 10, "swallow forecast changes live to attack ten after final minion dies")
	hp_before = state.player.hp
	_rules.end_turn(state)
	_equal(hp_before - int(state.player.hp), 10, "empty-board swallow actually uses the live ten-damage fallback")
	state = _state(["boss.sock_snake", "enemy.sock_kid", "enemy.sock_kid", "enemy.sock_kid"], [], [], {"hp": 1000, "max_hp": 1000})
	_rules.end_turn(state)
	_equal(_living(state), 4, "boss cannot exceed four simultaneously living enemies")
	_equal(state.enemies[0].guard, 12, "full-board summon becomes three guard after minion guard bonus")
	state = _state(["boss.sock_snake"], [], [], {"hp": 1000, "max_hp": 1000})
	state.enemies[0].hp = 36
	_hand(state, ["card.dust_off"])
	var events: Array = _rules.play_card(state, 0, 0)
	_check(not _rules.forecast(state).get("warnings", []).is_empty(), "boss crossing below 35 immediately exposes two-window warning")
	hp_before = state.player.hp
	_rules.end_turn(state)
	_equal(hp_before - int(state.player.hp), 8, "boss warning gives first response window before normal tail")
	_check(not _rules.forecast(state).get("warnings", []).is_empty(), "boss warning remains visible for second player response window")
	hp_before = state.player.hp
	events = _rules.end_turn(state)
	_check(hp_before - int(state.player.hp) >= 16, "boss big coil executes only after second response window")
	var warnings_after: Array = _rules.forecast(state).get("warnings", [])
	_check(warnings_after.is_empty(), "boss phase warning does not restart repeatedly below threshold")

func _test_edges_and_forecasts() -> void:
	var state: Dictionary = _state()
	_hand(state, ["card.tug", "card.brace", "card.brace", "card.brace", "card.brace", "card.brace", "card.brace", "card.brace"])
	var draw_before: int = state.draw_pile.size()
	_rules.play_card(state, 0)
	_equal(state.hand.size(), 8, "draw stops at eight-card hand cap")
	_equal(state.draw_pile.size(), draw_before - 1, "overflow draw is canceled with remaining card left in deck")
	state = _state()
	_hand(state, ["card.tug"], [])
	_rules.play_card(state, 0)
	_equal(state.hand.size(), 0, "draw with both piles empty is a safe no-op")
	state = _state()
	_hand(state, ["card.tug"], [])
	var recycled: Dictionary = _card("card.big_hammer")
	state.discard = [recycled, _card("card.brace")]
	_rules.play_card(state, 0)
	_equal(state.hand.size(), 2, "empty draw pile recycles discard and continues drawing")
	_check(_contains_uid(state.hand, recycled.uid), "discard recycle preserves card instance identities")
	state = _state()
	_hand(state, ["card.knock"])
	state.enemies[0].guard = 4
	_rules.play_card(state, 0, 0)
	_equal([state.enemies[0].guard, state.enemies[0].hp], [0, 10], "damage exhausts enemy guard before touching HP")
	state = _state()
	_hand(state, ["card.knot", "card.knot"])
	_rules.play_card(state, 0, 0)
	_rules.play_card(state, 0, 0)
	_equal(state.enemies[0].weaken, 10, "multiple weaken cards stack")
	_equal(_rules.forecast(state).damage, 0, "stacked weaken floors attack damage at zero")
	state = _state()
	_hand(state, ["card.pick_up"])
	for choices: Dictionary in [{}, {"discard_uid": "nonexistent"}, {"discard_index": 999}]:
		var before: Dictionary = state.duplicate(true)
		_rules.play_card(state, 0, -1, choices)
		_equal(state, before, "invalid discard selection is atomic " + str(choices))
	state = _state()
	_hand(state, ["card.deliver", "card.knock"])
	for choices: Dictionary in [{}, {"other_uid": "nonexistent", "other_target_index": 0}, {"other_uid": state.hand[0].uid, "other_target_index": 0}, {"other_uid": state.hand[1].uid, "other_target_index": 999}, {"other_hand_index": 999}]:
		var before: Dictionary = state.duplicate(true)
		_rules.play_card(state, 0, -1, choices)
		_equal(state, before, "invalid nested free-play selection is atomic " + str(choices))
	state = _state(["enemy.wet_sock"], ["relic.bookmark"])
	var before: Dictionary = state.duplicate(true)
	_rules.end_turn(state, state.hand.size())
	_equal(state, before, "out-of-range retained-hand choice is atomic")
	state = _state(["enemy.wet_sock", "enemy.wet_sock"])
	state.player.guard = 7
	_equal(_rules.forecast(state).damage, 3, "forecast applies one shared player guard across left-to-right enemy attacks")
	var forecast: Dictionary = _rules.forecast(state)
	_rules.end_turn(state)
	_equal(state.player.hp, forecast.hp_after, "ordinary combined enemy forecast matches actual HP")
	state = _state(["enemy.wet_sock", "enemy.wet_sock"], ["relic.flat_ball"])
	state.enemies[0].hp = 5
	state.player.guard = 5
	forecast = _rules.forecast(state)
	_equal(forecast.damage, 5, "forecast includes guard-break retaliation without ignoring later attacker")
	_rules.end_turn(state)
	_equal(state.player.hp, forecast.hp_after, "guard-break retaliation forecast equals actual HP")
	state = _state(["elite.hungry_drawer"], [], [], {"hp": 1000, "max_hp": 1000})
	_rules.end_turn(state)
	_rules.end_turn(state)
	state.enemies[0].hp = 3
	_hand(state, ["card.push_back"])
	_rules.play_card(state, 0)
	forecast = _rules.forecast(state)
	_equal(forecast.damage, 0, "forecast stops a multiattack when first-hit retaliation defeats attacker")
	_rules.end_turn(state)
	_equal(state.status, "victory", "retaliation victory interrupts remaining enemy hits")
	_equal(state.player.hp, forecast.hp_after, "retaliation interruption forecast equals actual HP")
	state = _state(["enemy.wet_sock", "enemy.wet_sock"], [], [], {"next_battle": {"first_attack_immune": true}})
	_equal(_rules.forecast(state).damage, 0, "soap modifier forecasts each enemy's first attack as harmless")
	_rules.end_turn(state)
	_equal(state.player.hp, 40, "soap modifier cancels each enemy's first attack")
	_equal(_rules.forecast(state).damage, 10, "soap protection is exhausted separately for every enemy")
	state = _state(["enemy.wet_sock"], [], [], {"hp": 1, "spare_rope_available": true})
	_rules.end_turn(state)
	_equal(state.status, "player", "spare rope resolves before defeat")
	_equal(state.player.hp, 1, "spare rope preserves one HP")
	_check(state.spare_rope_used, "spare rope records once-per-run consumption")
	state.player.guard = 0
	_rules.end_turn(state)
	_equal(state.status, "defeat", "spare rope cannot rescue player a second time")
	before = state.duplicate(true)
	_rules.end_turn(state)
	_rules.play_card(state, 0, 0)
	_equal(state, before, "terminal defeat rejects later commands without mutation")
	var retry_one: Dictionary = _rules.retry(state, 1).state
	_equal(retry_one.player.hp, 20, "retry restores at least half maximum HP")
	_equal(retry_one.enemies[0].max_hp, 10, "first retry reduces enemy max HP by 20 percent with ceil rounding")
	_check(retry_one.spare_rope_used, "retry cannot restore spent once-per-run spare rope")
	_check(retry_one.rng.shuffle.seed != state.rng.shuffle.seed, "retry derives a fresh shuffle seed")
	var retry_two: Dictionary = _rules.retry(state, 2).state
	_equal(retry_two.enemies[0].max_hp, 8, "second retry reduces enemy max HP by 40 percent with ceil rounding")
	_equal(_rules.retry(state, 99).state.enemies[0].max_hp, 8, "retry help is capped at 40 percent")
	state = _state(["enemy.wet_sock"], [], ["keepsake.ring"], {"hp": 31})
	state.status = "defeat"
	state.player.hp = 0
	retry_one = _rules.retry(state, 1).state
	_equal(retry_one.player.hp, 31, "retry preserves higher original battle-start HP")
	_equal(retry_one.keepsakes, ["keepsake.ring"], "retry preserves borrowed keepsakes")
	_test_card_completion_order()

func _test_card_completion_order() -> void:
	var fixture_defs: Dictionary = _defs.duplicate(true)
	fixture_defs.cards.append({"id": "card.test_finish", "type": "attack", "cost": 0, "target": "all_enemies", "ops": [{"op": "damage_all", "amount": 50}, {"op": "heal", "amount": 5}, {"op": "draw", "amount": 1}]})
	var engine: RefCounted = Rules.new(fixture_defs)
	var state: Dictionary = engine.start({"id": "enc.test", "enemies": ["enemy.wet_sock", "enemy.lint_bug"]}, _run_fixture(["relic.odd_button"], [], {"hp": 20}), 2).state
	_hand(state, ["card.test_finish"])
	var events: Array = engine.play_card(state, 0)
	_equal(state.status, "victory", "all-enemy lethal card produces victory")
	_equal(state.player.hp, 25, "lethal all-enemy card finishes its subsequent heal")
	_equal(state.hand.size(), 1, "lethal all-enemy card finishes its subsequent draw")
	_equal(state.energy, 5, "each defeated enemy fires odd-button hook exactly once")
	_equal(_count_events(events, "victory"), 1, "victory emits exactly once even with multiple simultaneous deaths")
	_check(_event_index(events, "enemy_defeated") >= 0, "enemy defeat event is emitted during lethal card resolution")

func _test_replay_and_randomness() -> void:
	var rng: RefCounted = Rng.new(1)
	var actual: Array = []
	for ignored: int in range(5):
		actual.append(rng.next_u32())
	_equal(actual, [270369, 67634689, 2647435461, 307599695, 2398689233], "xorshift32 has a fixed portable reference sequence")
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(rng.snapshot()))
	var resumed: RefCounted = Rng.new(serialized)
	for index: int in range(20):
		_equal(resumed.next_u32(), rng.next_u32(), "RNG JSON snapshot resumes exact next value " + str(index))
	var zero_seed: RefCounted = Rng.new(0)
	_check(zero_seed.next_u32() != 0, "zero seed is safely remapped away from xorshift's stuck state")
	var range_rng: RefCounted = Rng.new(441)
	var minimum_seen: int = 99
	var maximum_seen: int = -99
	var in_bounds: bool = true
	for ignored: int in range(200):
		var value: int = range_rng.range_int(-2, 2)
		minimum_seen = mini(minimum_seen, value)
		maximum_seen = maxi(maximum_seen, value)
		in_bounds = in_bounds and value >= -2 and value <= 2
	_check(in_bounds and minimum_seen == -2 and maximum_seen == 2, "range_int is inclusive and stays within signed bounds")
	_equal(range_rng.range_int(3, 3), 3, "degenerate range returns only possible value")
	var shuffle_a: RefCounted = Rng.new(Rng.derive(911, "shuffle"))
	var shuffle_b: RefCounted = Rng.new(Rng.derive(911, "shuffle"))
	var battle_rng: RefCounted = Rng.new(Rng.derive(911, "battle"))
	for ignored: int in range(53):
		battle_rng.next_u32()
	_equal(shuffle_a.shuffle([0, 1, 2, 3, 4, 5]), shuffle_b.shuffle([0, 1, 2, 3, 4, 5]), "battle-random draws cannot perturb shuffle stream")
	_check(Rng.derive(911, "path") != Rng.derive(911, "rewards") and Rng.derive(911, "shuffle") != Rng.derive(911, "battle"), "named path/reward/shuffle/battle seeds are distinct")
	var state: Dictionary = _state(["enemy.wet_sock", "enemy.lonely_sock"], ["relic.lost_kite"])
	_durable(state)
	_hand(state, ["card.brace"])
	var before: Dictionary = state.duplicate(true)
	var preview_a: Dictionary = _rules.preview(state, 0)
	var preview_b: Dictionary = _rules.preview(state, 0)
	_equal(state, before, "preview leaves input and every RNG stream untouched")
	_equal(preview_a, preview_b, "random-target preview is repeatable")
	_rules.play_card(state, 0)
	_equal(state, preview_a.state, "random-target preview executes the same engine as real play")
	_equal(state.rng.shuffle, before.rng.shuffle, "random relic proc does not consume shuffle RNG")
	_check(state.rng.battle != before.rng.battle, "random relic proc advances only battle RNG")
	state = _state()
	_hand(state, ["card.tug"], [])
	state.discard = _cards(["card.knock", "card.brace", "card.big_hammer"])
	before = state.duplicate(true)
	_rules.play_card(state, 0)
	_equal(state.rng.battle, before.rng.battle, "discard shuffle does not consume battle-random stream")
	_check(state.rng.shuffle != before.rng.shuffle, "discard shuffle advances shuffle stream")
	state = _state()
	_hand(state, ["card.knock"])
	before = state.duplicate(true)
	var invalid_preview: Dictionary = _rules.preview(state, 99, 99)
	_check(not invalid_preview.get("valid", true), "invalid preview is explicitly marked invalid")
	_equal(state, before, "invalid preview leaves input unchanged")
	var fixture_run: Dictionary = _run_fixture(["relic.lone_glove", "relic.lost_kite"], ["keepsake.ring"])
	var encounter: Dictionary = {"id": "enc.replay", "enemies": ["enemy.lonely_sock", "enemy.lint_bug"]}
	var first: Dictionary = _rules.start(encounter, fixture_run, 92814).state
	var second: Dictionary = _rules.start(encounter, fixture_run, 92814).state
	var replay_events_equal: bool = true
	var commands: int = 0
	while first.status == "player" and commands < 100:
		var actions: Array = _rules.legal_actions(first)
		var action: Dictionary = actions[0]
		# Prefer card play over ending; action enumeration is engine-authoritative.
		for candidate: Dictionary in actions:
			if candidate.type == "play_card":
				action = candidate
				break
		var left_events: Array = _execute(first, action)
		var right_events: Array = _execute(second, action)
		replay_events_equal = replay_events_equal and left_events == right_events
		commands += 1
	_equal(first, second, "fixed seed and command stream replay identical complete state")
	_check(replay_events_equal, "fixed seed replay produces identical ordered event stream")
	_check(first.status != "player" and commands > 0, "replay reaches a real terminal outcome through legal actions")
	_check(_is_json(first), "battle snapshots contain JSON-only values")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(first))
	_equal(JSON.parse_string(JSON.stringify(restored)), JSON.parse_string(JSON.stringify(first)), "full battle snapshot round-trips through JSON")
	var defs_before: Dictionary = _defs.duplicate(true)
	state = _state()
	_rules.forecast(state)
	_rules.legal_actions(state)
	_equal(_defs, defs_before, "read-only definitions stay unchanged by battle/query calls")

func _is_json(value: Variant) -> bool:
	if value == null or value is String or value is bool or value is int or value is float:
		return true
	if value is Array:
		for child: Variant in value:
			if not _is_json(child):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _is_json(value[key]):
				return false
		return true
	return false

func _test_coupled_boundaries() -> void:
	_equal(_defs.cards.size(), 24, "all twenty-one base cards plus three wish variants are loaded")
	_equal(_defs.relics.size(), 15, "all fifteen relic definitions are loaded")
	_equal(_defs.keepsakes.size(), 3, "all three keepsakes are loaded")
	_equal(_defs.enemies.size(), 9, "all nine enemy definitions are loaded")
	var too_large: Array = []
	for ignored: int in range(13):
		too_large.append("card.knock")
	var result: Dictionary = _rules.start({"id": "enc.test", "enemies": ["enemy.wet_sock"]}, _run_fixture([], [], {"deck": too_large}), 42)
	_check(result.state.is_empty() and result.has("error"), "battle start rejects a deck larger than twelve")
	result = _rules.start({"id": "enc.test", "enemies": ["enemy.wet_sock", "enemy.wet_sock", "enemy.wet_sock", "enemy.wet_sock", "enemy.wet_sock"]}, _run_fixture(), 42)
	_check(result.state.is_empty() and result.has("error"), "battle start rejects more than four simultaneous enemies")
	var state: Dictionary = _state(["enemy.wet_sock"], ["relic.tangled_earbuds"])
	_durable(state)
	_hand(state, ["card.blanket", "card.deliver", "card.knock"])
	_rules.play_card(state, 0)
	var selected: Variant = state.hand[1].uid
	var events: Array = _rules.play_card(state, 0, -1, {"other_uid": selected, "other_target_index": 0})
	_equal(state.hand.size(), 1, "deliver as second card and its third-card child trigger earbuds exactly once")
	_equal(_count_events(events, "card_played"), 2, "deliver and selected physical card each count as one played card")
	state = _state(["enemy.wet_sock"], ["relic.birthday_candle"])
	_hand(state, ["card.tug"])
	_rules.play_card(state, 0)
	_equal(state.hand.size(), 4, "birthday candle doubles draw counts")
	state = _state(["enemy.wet_sock"], ["relic.birthday_candle"])
	_hand(state, ["card.brace"])
	_rules.play_card(state, 0)
	_equal(state.player.guard, 10, "birthday candle doubles numeric guard")
	state = _state(["enemy.wet_sock"], ["relic.birthday_candle"])
	_hand(state, ["card.deep_breath"])
	_rules.play_card(state, 0)
	_rules.end_turn(state)
	_equal(state.energy, 7, "birthday candle doubles delayed energy count")
	state = _state(["enemy.wet_sock"], ["relic.birthday_candle"])
	_hand(state, ["card.vow", "card.brace"])
	_rules.play_card(state, 0)
	_rules.play_card(state, 0)
	_equal(state.player.guard, 10, "birthday candle does not recursively double vow's boolean guard rule")
	state = _state(["enemy.wet_sock"], ["relic.birthday_candle"])
	_durable(state)
	_hand(state, ["card.deliver", "card.big_hammer"])
	selected = state.hand[1].uid
	events = _rules.play_card(state, 0, -1, {"other_uid": selected, "other_target_index": 0})
	_equal(state.enemies[0].hp, 986, "candle on deliver does not replay choice or leak onto nested card")
	_equal(_count_events(events, "card_played"), 2, "candle delivery resolves exactly two physical card plays")
	state = _state(["enemy.wet_sock"], ["relic.lone_glove"])
	_durable(state)
	_hand(state, ["card.yank"])
	_rules.play_card(state, 0, 0)
	_equal(state.hand.size(), 2, "lone glove repeats the entire attack card including draw")
	state = _state(["enemy.wet_sock"], ["relic.crooked_compass", "relic.open_ink", "relic.empty_frame"])
	_equal(state.hand.size(), 8, "combined opening draw/copy hooks never exceed hand cap")
	_equal(state.draw_pile.size(), 2, "opening overflow does not consume unseen deck cards")
	state = _state()
	_hand(state, ["card.deliver_plus", "card.big_hammer"])
	state.energy = 0
	selected = state.hand[1].uid
	var free_action_found: bool = false
	for action: Dictionary in _rules.legal_actions(state):
		if action.type == "play_card" and action.hand_index == 0 and action.get("choices", {}).get("other_uid", "") == selected:
			free_action_found = true
	_check(free_action_found, "legal actions includes free delivery of unaffordable card at zero energy")
	_rules.play_card(state, 0, -1, {"other_uid": selected, "other_target_index": 0})
	_equal(state.status, "victory", "zero-energy free delivery performs actual lethal expensive card")
	state = _state(["enemy.wet_sock"], [], [], {"next_battle": {"first_attack_immune": true}})
	_hand(state, ["card.push_back"])
	_rules.play_card(state, 0)
	var forecast: Dictionary = _rules.forecast(state)
	_rules.end_turn(state)
	_equal(state.player.hp, forecast.hp_after, "soap plus retaliation remains forecast-exact")
	state = _state(["enemy.wet_sock"], ["relic.half_biscuit", "relic.flat_ball"], [], {"hp": 20})
	state.player.guard = 5
	state.enemies[0].hp = 5
	forecast = _rules.forecast(state)
	_rules.end_turn(state)
	_equal(state.player.hp, 24, "victory biscuit resolves after lethal guard-break retaliation")
	_equal(state.player.hp, forecast.hp_after, "forecast includes victory healing after retaliation")
	state = _state(["enemy.wet_sock", "enemy.lonely_sock"], ["relic.lost_kite"])
	_hand(state, ["card.brace", "card.knock"])
	var restored: Dictionary = JSON.parse_string(JSON.stringify(state))
	var actual_events: Array = _rules.play_card(state, 0)
	var restored_events: Array = _rules.play_card(restored, 0)
	_equal(JSON.parse_string(JSON.stringify(restored)), JSON.parse_string(JSON.stringify(state)), "JSON-restored active battle continues to identical state")
	_equal(JSON.parse_string(JSON.stringify(restored_events)), JSON.parse_string(JSON.stringify(actual_events)), "JSON-restored active battle emits identical random-target events")

func _test_activation_order_and_policy() -> void:
	var state: Dictionary = _state()
	state.keepsakes.append("keepsake.letter")
	_hand(state, ["card.tug"])
	_rules.play_card(state, 0)
	_equal(state.energy, 3, "newly acquired letter applies immediately during an existing battle")
	state = _state()
	state.keepsakes.append("keepsake.mianmian")
	_equal(_rules.forecast(state).damage, 2, "newly acquired mianmian immediately modifies live intent forecast")
	_rules.end_turn(state)
	_equal(state.player.hp, 38, "newly acquired mianmian protects the next incoming attack")
	state = _state()
	state.keepsakes.append("keepsake.ring")
	_equal(state.player.guard, 0, "newly acquired ring does not retroactively trigger current turn start")
	_rules.end_turn(state)
	_equal(state.player.guard, 3, "newly acquired ring starts at next player turn start")
	state = _state(["enemy.wet_sock"], ["relic.flat_ball"], [], {"hp": 1, "spare_rope_available": true})
	state.player.guard = 1
	var forecast: Dictionary = _rules.forecast(state)
	_rules.end_turn(state)
	_equal(state.enemies[0].hp, 7, "spare-rope replacement guard does not suppress the original flat-ball guard-break trigger")
	_equal(state.player.hp, 1, "flat ball and spare rope resolve without a false defeat")
	_equal(state.player.hp, forecast.hp_after, "spare-rope plus flat-ball forecast matches actual rescued HP")
	state = _state(["boss.sock_snake"], ["relic.flat_ball"], [], {"hp": 1000, "max_hp": 1000})
	state.enemies[0].hp = 36
	state.player.guard = 5
	_rules.end_turn(state)
	_equal(_rules.forecast(state).warnings[0].turns, 2, "phase crossed during enemy retaliation grants two full future player response windows")
	var events: Array = _rules.end_turn(state)
	_check(not _contains_phase_attack(events), "retaliation-triggered boss phase does not strike after only one player window")
	events = _rules.end_turn(state)
	_check(_contains_phase_attack(events), "retaliation-triggered phase strikes after the second full player window")
	var fixture_defs: Dictionary = _defs.duplicate(true)
	fixture_defs.keepsakes.append({"id": "keepsake.test_order", "trigger": "turn_start", "ops": [{"op": "gain_guard", "amount": 1}]})
	fixture_defs.relics.append({"id": "relic.test_order_a", "trigger": "turn_start", "ops": [{"op": "gain_guard", "amount": 2}]})
	fixture_defs.relics.append({"id": "relic.test_order_b", "trigger": "turn_start", "ops": [{"op": "gain_guard", "amount": 3}]})
	var engine: RefCounted = Rules.new(fixture_defs)
	var start_result: Dictionary = engine.start({"id": "enc.test", "enemies": ["enemy.wet_sock"]}, _run_fixture(["relic.test_order_b", "relic.test_order_a"], ["keepsake.test_order"]), 29)
	var sources: Array = []
	for event: Dictionary in start_result.events:
		if event.type == "guard" and event.get("target", "") == "player":
			sources.append(event.source)
	_equal(sources, ["keepsake.test_order", "relic.test_order_b", "relic.test_order_a"], "simultaneous hooks resolve keepsakes first then relic acquisition order")
	_equal(start_result.state.player.guard, 6, "all simultaneous hook effects resolve once")
	var bot: RefCounted = Bot.new(_defs)
	for strategy: String in ["simple", "defensive"]:
		for seed_value: int in [1, 29, 441, 92814, 99171]:
			state = _rules.start({"id": "enc.tutorial", "enemies": ["enemy.wet_sock"]}, _run_fixture(), seed_value).state
			var choices_legal: bool = true
			var policy_pure: bool = true
			var count: int = 0
			while state.status == "player" and count < 80:
				var before: Dictionary = state.duplicate(true)
				var action: Dictionary = bot.choose_action(state, _rules, strategy)
				policy_pure = policy_pure and state == before
				choices_legal = choices_legal and _rules.legal_actions(state).has(action)
				_execute(state, action)
				count += 1
			_check(choices_legal and policy_pure, strategy + " bot selects only legal actions without mutating preview state seed " + str(seed_value))
			_equal(state.status, "victory", strategy + " bot wins tutorial through real rule execution seed " + str(seed_value))
			_check(int(state.enemies[0].hp) == 0 and count > 0, strategy + " bot cannot fabricate tutorial victory seed " + str(seed_value))
			_equal(bot.choose_action(state, _rules, strategy), {}, "terminal battle offers no policy action")
	_equal(bot.choose_reward([], {}, "simple"), -1, "reward policy handles no offers")
	_equal(bot.choose_reward([{"id": "relic.open_ink"}, {"id": "relic.lone_glove"}], {}, "simple"), 1, "attack reward policy recognizes glove synergy")

func _contains_phase_attack(events: Array) -> bool:
	for event: Dictionary in events:
		if event.get("type", "") == "enemy_action" and event.get("intent", {}).get("phase_attack", false) and event.get("intent", {}).get("type", "") == "attack":
			return true
	return false

func _test_golden_replay() -> void:
	var fixture: Dictionary = GoldenReplay.CASE.duplicate(true)
	var state: Dictionary = _rules.start(fixture.encounter, fixture.run, fixture.seed).state
	var all_events: Array = []
	for action: Dictionary in fixture.commands:
		_check(_rules.legal_actions(state).has(action), "fixed golden command is legal at recorded safe state")
		all_events.append_array(_execute(state, action))
	_equal(state.status, fixture.expected_status, "fixed golden replay reaches recorded real victory")
	_equal(state.turn, fixture.expected_turn, "fixed golden replay has expected turn count")
	_equal(state.player.hp, fixture.expected_hp, "fixed golden replay has expected surviving HP")
	_equal(JSON.stringify(state).sha256_text(), fixture.expected_state_sha256, "fixed golden replay matches canonical full-state SHA-256")
	_equal(JSON.stringify(all_events).sha256_text(), fixture.expected_events_sha256, "fixed golden replay matches ordered-events SHA-256")
	state = _state(["enemy.stinky_insole", "enemy.stinky_insole", "enemy.stinky_insole", "enemy.stinky_insole"], [], [], {"hp": 1000, "max_hp": 1000})
	var draw_before: int = state.draw_pile.size()
	_rules.end_turn(state)
	_equal(state.hand.size(), 0, "stacked draw penalty clamps at zero rather than drawing a negative amount")
	_equal(state.draw_pile.size(), draw_before, "canceled draw leaves deck untouched")
	_rules.end_turn(state)
	_equal(state.hand.size(), 4, "stacked draw penalties reset after one draw phase")
	state = _state(["enemy.soap_bubble", "enemy.wet_sock"])
	state.enemies[0].guard = 10
	state.enemies[1].guard = 10
	_rules.end_turn(state)
	_equal([state.enemies[0].guard, state.enemies[1].guard], [3, 3], "all enemy guard clears together before soap's all-enemy guard intent")

func _test_bot_stress() -> void:
	var bot: RefCounted = Bot.new(_defs)
	var encounters: Array = _defs.encounters.duplicate(true)
	encounters.append({"id": "elite.hungry_drawer", "enemies": ["elite.hungry_drawer"]})
	encounters.append({"id": "boss.sock_snake", "enemies": ["boss.sock_snake"]})
	var battles: int = 0
	var victories: int = 0
	var defeats: int = 0
	var illegal: int = 0
	var stalls: int = 0
	var false_outcomes: int = 0
	var maximum_turn: int = 0
	var by_encounter: Array = []
	for encounter: Dictionary in encounters:
		var local_wins: int = 0
		var local_losses: int = 0
		for seed_number: int in range(10):
			var run_state: Dictionary = _run_fixture()
			if encounter.id == "boss.sock_snake":
				run_state.relics = ["relic.lone_glove"]
				run_state.keepsakes = ["keepsake.ring"]
			var state: Dictionary = _rules.start(encounter, run_state, 12001 + seed_number * 7919).state
			var action_count: int = 0
			while state.status == "player" and int(state.turn) <= 100 and action_count < 1000:
				var action: Dictionary = bot.choose_action(state, _rules, "defensive")
				if not _rules.legal_actions(state).has(action):
					illegal += 1
					break
				var events: Array = _execute(state, action)
				if _count_events(events, "invalid_action") > 0:
					illegal += 1
					break
				action_count += 1
			battles += 1
			maximum_turn = maxi(maximum_turn, int(state.turn))
			if state.status == "victory":
				victories += 1
				local_wins += 1
				if _living(state) > 0 or int(state.player.hp) <= 0:
					false_outcomes += 1
			elif state.status == "defeat":
				defeats += 1
				local_losses += 1
				if int(state.player.hp) != 0:
					false_outcomes += 1
			else:
				stalls += 1
		by_encounter.append({"id": encounter.id, "wins": local_wins, "losses": local_losses, "seeds": 10})
	_stress = {"battles": battles, "victories": victories, "defeats": defeats, "illegal_actions": illegal, "stalls": stalls, "false_outcomes": false_outcomes, "maximum_turn": maximum_turn, "by_encounter": by_encounter, "loadout_note": "starter deck; boss additionally has lone glove and ring; isolated fights, not full-run balance"}
	_equal(battles, 120, "combat stress executes all ten authored encounters plus elite and boss across ten seeds")
	_equal(illegal, 0, "combat stress policies never select an illegal command")
	_equal(stalls, 0, "combat stress has no unresolved battle at diagnostic watchdog")
	_equal(false_outcomes, 0, "combat stress outcomes are backed by actual enemy/player HP")
	_equal(victories + defeats, battles, "combat stress reports every real victory or defeat without manufacturing wins")

func _test_retry_and_phase_cancellations() -> void:
	var encounter: Dictionary = {"id": "enc.test", "enemies": ["enemy.wet_sock"]}
	var run_state: Dictionary = _run_fixture([], [], {"hp": 1, "next_battle": {"extra_enemies": ["enemy.lonely_sock"]}})
	var state: Dictionary = _rules.start(encounter, run_state, 61).state
	_equal(state.enemies.size(), 2, "next-battle extra enemy appears exactly once")
	_equal(encounter.enemies, ["enemy.wet_sock"], "extra enemy does not mutate caller encounter")
	_equal(state.start_snapshot.encounter.enemies, ["enemy.wet_sock"], "battle checkpoint stores unmodified base encounter")
	_rules.end_turn(state)
	state = _rules.retry(state, 1).state
	_equal(state.enemies.size(), 2, "first retry does not append event extra enemy again")
	_equal(state.start_snapshot.encounter.enemies, ["enemy.wet_sock"], "first retry preserves original encounter checkpoint")
	state.player.hp = 1
	state.player.guard = 0
	_rules.end_turn(state)
	state = _rules.retry(state, 2).state
	_equal(state.enemies.size(), 2, "second retry still has exactly one event extra enemy")
	var full_encounter: Dictionary = {"id": "enc.full", "enemies": ["boss.sock_snake", "enemy.sock_kid", "enemy.sock_kid", "enemy.sock_kid"]}
	var before: Dictionary = full_encounter.duplicate(true)
	var result: Dictionary = _rules.start(full_encounter, run_state, 61)
	_check(result.state.is_empty() and result.has("error"), "extra enemy exceeding four-slot limit is rejected")
	_equal(full_encounter, before, "overflow encounter rejection does not mutate caller")
	state = _state(["boss.sock_snake"], [], [], {"hp": 1000, "max_hp": 1000})
	state.enemies[0].hp = 38
	_hand(state, ["card.dust_off", "card.dust_off"])
	_rules.play_card(state, 0, 0)
	_check(_rules.forecast(state).warnings.is_empty(), "boss at exactly 35 HP does not prematurely enter below-35 phase")
	_rules.play_card(state, 0, 0)
	_check(not _rules.forecast(state).warnings.is_empty(), "boss first drops below 35 into announced phase")
	_rules.end_turn(state)
	_hand(state, ["card.shake_rope"])
	_rules.play_card(state, 0, 0)
	var events: Array = _rules.end_turn(state)
	_check(not _contains_phase_attack(events), "shake rope cancels currently due big-coil attack")
	_check(_rules.forecast(state).warnings.is_empty(), "canceled big coil is not silently postponed behind an idle turn")
	_equal(_rules.forecast(state).intents[0].amount, 5, "after canceled phase attack boss resumes paused normal coil")
	state = _state(["boss.sock_snake"], [], [], {"hp": 1000, "max_hp": 1000})
	state.enemies[0].hp = 36
	_hand(state, ["card.dust_off", "card.shake_rope"])
	_rules.play_card(state, 0, 0)
	_rules.play_card(state, 0, 0)
	events = _rules.end_turn(state)
	_check(not _contains_phase_attack(events), "early shake cancels ordinary current intention during first warning window")
	events = _rules.end_turn(state)
	_check(_contains_phase_attack(events), "early shake does not erase a future not-yet-due big-coil intention")

func _test_adversarial_parity() -> void:
	for invalid_hp: Dictionary in [{"hp": 0}, {"hp": -1}, {"max_hp": 0, "hp": 0}, {"hp": 41, "max_hp": 40}]:
		var run_state: Dictionary = _run_fixture([], [], invalid_hp)
		var before: String = JSON.stringify(run_state)
		var result: Dictionary = _rules.start({"id": "enc.test", "enemies": ["enemy.wet_sock"]}, run_state, 89)
		_check(result.state.is_empty() and result.has("error"), "invalid initial HP is rejected instead of silently resurrected " + str(invalid_hp))
		_equal(JSON.stringify(run_state), before, "invalid HP rejection leaves input bytes unchanged")
	var catalog_cards: Array = []
	var catalog_relics: Array = []
	for definition: Dictionary in _defs.cards:
		catalog_cards.append(definition.id)
	for definition: Dictionary in _defs.relics:
		catalog_relics.append(definition.id)
	var mismatches: int = 0
	var invalid_legal: int = 0
	var preview_mutations: int = 0
	var executed: int = 0
	for case_number: int in range(32):
		var rng: RefCounted = Rng.new(4021 + case_number * 811)
		var deck: Array = []
		for ignored: int in range(12):
			deck.append(catalog_cards[rng.range_int(0, catalog_cards.size() - 1)])
		var relics: Array = []
		while relics.size() < 4:
			var relic: String = catalog_relics[rng.range_int(0, catalog_relics.size() - 1)]
			if not relics.has(relic):
				relics.append(relic)
		var keepsakes: Array = ["keepsake.ring", "keepsake.mianmian"] if case_number % 2 == 0 else ["keepsake.letter"]
		var enemy_ids: Array = ["enemy.stinky_insole", "enemy.soap_bubble"] if case_number % 3 == 0 else (["elite.hungry_drawer"] if case_number % 3 == 1 else ["boss.sock_snake"])
		var run_state: Dictionary = _run_fixture(relics, keepsakes, {"deck": deck, "spare_rope_available": true, "next_battle": {"first_attack_immune": case_number % 4 == 0}})
		var state: Dictionary = _rules.start({"id": "enc.parity", "enemies": enemy_ids}, run_state, 781 + case_number).state
		for step: int in range(18):
			if state.status != "player":
				break
			var before: String = JSON.stringify(state)
			var forecast: Dictionary = _rules.forecast(state)
			var actions: Array = _rules.legal_actions(state)
			if JSON.stringify(state) != before:
				preview_mutations += 1
			var action: Dictionary = {"type": "end_turn", "keep_index": -1}
			if rng.range_int(0, 3) != 0:
				action = actions[rng.range_int(0, actions.size() - 1)]
			var prediction: Dictionary = {}
			if action.type == "play_card":
				prediction = _rules.preview(state, action.hand_index, action.target_index, action.choices)
				if not prediction.valid or JSON.stringify(state) != before:
					preview_mutations += 1
			var events: Array = _execute(state, action)
			if _count_events(events, "invalid_action") > 0:
				invalid_legal += 1
			if action.type == "play_card":
				if state != prediction.state or events != prediction.events:
					mismatches += 1
			elif int(state.player.hp) != int(forecast.hp_after):
				mismatches += 1
			executed += 1
	_check(executed >= 100, "adversarial parity exercises at least one hundred diverse legal commands")
	_equal(invalid_legal, 0, "adversarial diverse-hand legal_actions never advertises a rejected command")
	_equal(preview_mutations, 0, "adversarial random previews and forecasts never mutate state or random streams")
	_equal(mismatches, 0, "adversarial random card previews and enemy-turn forecasts equal actual engine outcomes")

func _test_lethal_forecast_semantics() -> void:
	var state: Dictionary = _state(["enemy.stinky_insole"])
	_rules.end_turn(state)
	state.player.hp = 5
	var forecast: Dictionary = _rules.forecast(state)
	_equal(forecast.damage, 8, "lethal forecast shows full eight unblocked damage instead of truncating to five remaining HP")
	_equal(forecast.resolved_damage, 8, "resolved-damage field preserves full lethal hit pressure")
	_equal(forecast.hp_loss, 5, "lethal forecast separately reports actual capped HP loss")
	_equal(forecast.predicted_damage, 8, "raw live-intent prediction retains lethal hit size")
	_check(forecast.prediction_stops_at_defeat, "lethal forecast discloses simulation termination at defeat")
	_check(not str(forecast.prediction_basis).is_empty(), "forecast explains its damage basis")
	_rules.end_turn(state)
	_equal([state.status, state.player.hp], ["defeat", 0], "lethal forecast corresponds to real defeat and zero HP")
	state = _state(["elite.hungry_drawer"], [], [], {"hp": 1000, "max_hp": 1000})
	_rules.end_turn(state)
	_rules.end_turn(state)
	state.player.hp = 3
	forecast = _rules.forecast(state)
	_equal([forecast.damage, forecast.hp_loss, forecast.predicted_damage], [4, 3, 8], "multihit lethal forecast separates one resolved hit from two-hit published pressure")
	var events: Array = _rules.end_turn(state)
	var player_hits: int = 0
	for event: Dictionary in events:
		if event.type == "damage" and event.get("target", null) == "player":
			player_hits += 1
	_equal(player_hits, 1, "immediate player defeat prevents remaining multihit attack segments")
	state = _state(["elite.hungry_drawer"], [], [], {"hp": 1000, "max_hp": 1000})
	_rules.end_turn(state)
	_rules.end_turn(state)
	state.player.hp = 2
	state.player.guard = 5
	forecast = _rules.forecast(state)
	_equal([forecast.damage, forecast.hp_loss, forecast.predicted_damage], [3, 2, 3], "guard is deducted per hit before lethal damage and capped HP loss diverge")
	state = _state(["elite.hungry_drawer"], ["relic.flat_ball"], [], {"hp": 1000, "max_hp": 1000})
	_rules.end_turn(state)
	_rules.end_turn(state)
	state.enemies[0].hp = 5
	state.player.guard = 4
	forecast = _rules.forecast(state)
	_equal([forecast.damage, forecast.hp_loss, forecast.predicted_damage], [0, 0, 4], "guard-break kill cancels later hits while raw intent pressure remains separately visible")
	_rules.end_turn(state)
	_equal(state.status, "victory", "guard-break interruption yields real victory")
	state = _state(["enemy.wet_sock"], [], [], {"hp": 1, "spare_rope_available": true})
	forecast = _rules.forecast(state)
	_equal([forecast.damage, forecast.hp_loss, forecast.hp_after], [5, 0, 1], "spare-rope forecast reports zero HP lost when one HP is retained")
	_check(not forecast.prediction_stops_at_defeat, "spare rope prevents forecast from reporting a terminal defeat")
	_rules.end_turn(state)
	_equal([state.status, state.player.hp], ["player", forecast.hp_after], "spare-rope forecast remains actual-execution exact")
	state = _state(["enemy.stinky_insole"], [], [], {"spare_rope_available": true})
	_rules.end_turn(state)
	state.player.hp = 5
	forecast = _rules.forecast(state)
	_equal([forecast.damage, forecast.hp_loss, forecast.hp_after], [8, 4, 1], "spare rope prevents lethal damage at five HP by retaining one, not dying and healing")
	events = _rules.end_turn(state)
	var saved_hit: Dictionary = {}
	for event: Dictionary in events:
		if event.get("prevented_lethal", false):
			saved_hit = event
	_equal(saved_hit.get("hp_damage", -1), 4, "prevented-lethal event records only four HP actually lost")
	_equal(_count_events(events, "heal"), 0, "spare rope is not misrepresented as a healing event")
	_equal(_count_events(events, "defeat"), 0, "spare rope prevents defeat rather than reversing it")
	var fixture_defs: Dictionary = _defs.duplicate(true)
	fixture_defs.enemies.append({"id": "enemy.test_lethal_multi", "hp": 30, "intents": [{"type": "attack", "amount": 15, "times": 2}]})
	var engine: RefCounted = Rules.new(fixture_defs)
	state = engine.start({"id": "enc.test_lethal_multi", "enemies": ["enemy.test_lethal_multi"]}, _run_fixture([], [], {"hp": 5, "spare_rope_available": true}), 27).state
	forecast = engine.forecast(state)
	_equal([forecast.damage, forecast.hp_loss, forecast.hp_after], [20, 5, 0], "second lethal hit consumes rescue guard then defeats player without reusing spare rope")
	events = engine.end_turn(state)
	var hit_losses: Array = []
	var prevented_count: int = 0
	for event: Dictionary in events:
		if event.type == "damage" and event.get("target", null) == "player":
			hit_losses.append(event.hp_damage)
			if event.get("prevented_lethal", false):
				prevented_count += 1
	_equal(hit_losses, [4, 1], "rescued first and lethal second hits report four then one HP loss")
	_equal(prevented_count, 1, "multiattack can consume spare rope only once")
	_equal(_count_events(events, "spare_rope"), 1, "multiattack emits one spare-rope rescue event")
	_equal([state.status, state.player.hp], ["defeat", forecast.hp_after], "second-hit lethal outcome matches forecast exactly")
