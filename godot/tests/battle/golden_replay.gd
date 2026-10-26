extends RefCounted
## Fixed canonical JSON/SHA-256 regression, captured after individually verified mechanics.
## Do not regenerate automatically. Review a changed result against design rules.
const CASE: Dictionary = {
	"commands": [
		{
			"choices": {},
			"hand_index": 0,
			"target_index": 0,
			"type": "play_card"
		},
		{
			"choices": {},
			"hand_index": 0,
			"target_index": -1,
			"type": "play_card"
		},
		{
			"choices": {},
			"hand_index": 0,
			"target_index": -1,
			"type": "play_card"
		},
		{
			"keep_index": -1,
			"type": "end_turn"
		},
		{
			"choices": {},
			"hand_index": 0,
			"target_index": -1,
			"type": "play_card"
		},
		{
			"choices": {},
			"hand_index": 0,
			"target_index": 0,
			"type": "play_card"
		},
		{
			"choices": {},
			"hand_index": 0,
			"target_index": -1,
			"type": "play_card"
		},
		{
			"keep_index": -1,
			"type": "end_turn"
		},
		{
			"choices": {},
			"hand_index": 0,
			"target_index": -1,
			"type": "play_card"
		},
		{
			"choices": {},
			"hand_index": 0,
			"target_index": 1,
			"type": "play_card"
		}
	],
	"encounter": {
		"enemies": [
			"enemy.lonely_sock",
			"enemy.lint_bug"
		],
		"id": "enc.replay"
	},
	"expected_events_sha256": "5f1d671ead5355e54ec067adfb720f7aeadf226c229c85cfd51cd318643e10b1",
	"expected_hp": 38,
	"expected_state_sha256": "69d6a80d8debf4f59fa93776cd4972f60a32d9c60c770fc6a15d223b2d3e041e",
	"expected_status": "victory",
	"expected_turn": 3,
	"run": {
		"deck": [
			"card.knock",
			"card.knock",
			"card.knock",
			"card.knock",
			"card.brace",
			"card.brace",
			"card.brace",
			"card.brace",
			"card.rope_lasso",
			"card.tug"
		],
		"hp": 40,
		"keepsakes": [
			"keepsake.ring"
		],
		"max_hp": 40,
		"next_battle": {},
		"relics": [
			"relic.lone_glove",
			"relic.lost_kite"
		],
		"spare_rope_available": false,
		"spare_rope_used": false
	},
	"seed": 92814
}
