import test from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { ROOT, jsonBytes } from '../tools/lib/paths.mjs';
import { checkContent } from '../tools/qa/content-check.mjs';

function fixture(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'keepsake-content-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  cpSync(path.join(ROOT, 'content'), path.join(root, 'content'), { recursive: true });
  for (const kind of ['art', 'audio']) {
    const target = path.join(root, 'resources', kind, 'export'); mkdirSync(path.dirname(target), { recursive: true });
    cpSync(path.join(ROOT, 'resources', kind, 'export'), target, { recursive: true });
  }
  const read = name => JSON.parse(readFileSync(path.join(root, 'content', name), 'utf8'));
  const write = (name, value) => writeFileSync(path.join(root, 'content', name), jsonBytes(value));
  const change = (name, fn) => { const data = read(name); fn(data); write(name, data); };
  return { root, read, write, change };
}
function definitions() {
  return Object.fromEntries(JSON.parse(readFileSync(path.join(ROOT, 'content/registry.json'), 'utf8')).files.map(entry => [entry.id, JSON.parse(readFileSync(path.join(ROOT, 'content', entry.file), 'utf8'))]));
}

test('D1 source catalog has full documented pools, real asset references and honest graybox scope', () => {
  const result = checkContent();
  assert.equal(result.cards, 24); assert.equal(result.starterCount, 10); assert.equal(result.files, 12); assert.equal(result.storyPages, 25);
  assert.deepEqual(result.warnings, []); assert.match(result.scope, /D1 complete source data/); assert.match(result.scope, /not full-game implementation acceptance/);
  const t = definitions();
  for (const [key, count] of Object.entries({ cards: 24, relics: 15, keepsakes: 3, enemies: 9, encounters: 10, events: 6 })) assert.equal(t[key].length, count, key);
  assert.deepEqual(Object.fromEntries(['starter', 'reward', 'replica', 'replica_plus'].map(pool => [pool, t.cards.filter(c => c.pool === pool).length])), { starter: 4, reward: 14, replica: 3, replica_plus: 3 });
});

test('documented stable card, keepsake, enemy and event IDs are preserved', () => {
  const t = definitions();
  const ids = (table, values) => assert.deepEqual(t[table].map(x => x.id).sort(), values.split(' ').sort());
  ids('cards', 'card.knock card.brace card.rope_lasso card.tug card.double_tap card.big_hammer card.dust_off card.wring card.yank card.curl_up card.clothesline card.push_back card.blanket card.pocket card.deep_breath card.knot card.shake_rope card.pick_up card.vow card.whisper card.deliver card.vow_plus card.whisper_plus card.deliver_plus');
  ids('keepsakes', 'keepsake.ring keepsake.mianmian keepsake.letter');
  ids('enemies', 'enemy.wet_sock enemy.lonely_sock enemy.lint_bug enemy.stinky_insole enemy.clothespin enemy.soap_bubble enemy.sock_kid elite.hungry_drawer boss.sock_snake');
  ids('events', 'event.lonely_bench event.echo_mailbox event.mud_glint event.laundry_granny event.soap_tub event.aunt_mark');
  ids('relics', 'relic.lone_glove relic.spyglass relic.lost_kite relic.open_ink relic.half_biscuit relic.offkey_harmonica relic.empty_frame relic.leaky_balloon relic.crooked_compass relic.bookmark relic.shedding_brush relic.tangled_earbuds relic.flat_ball relic.birthday_candle relic.odd_button');
});

test('all replica plus links and optional wish pages match forced return rewards', () => {
  const t = definitions();
  for (const k of t.keepsakes) {
    const base = t.cards.find(c => c.id === k.replica_card_id), plus = t.cards.find(c => c.id === k.replica_plus_card_id), story = t.pages.find(s => s.id === k.return_story_id);
    assert.equal(base.plus_card_id, plus.id); assert.equal(plus.replica_of, base.id);
    assert.equal(story.pages.filter(pg => pg.when?.wish === k.id).length, 1);
    assert.deepEqual(story.end, { stamp: base.id, stamp_plus: plus.id, keepsake_id: k.id });
  }
  assert.equal(t.cards.find(c => c.id === 'card.vow_plus').cost, 0);
  assert.equal(t.cards.find(c => c.id === 'card.deliver_plus').cost, 0);
  assert.deepEqual(t.cards.find(c => c.id === 'card.whisper_plus').ops, [{ op: 'weaken_next_attack', amount: 4 }, { op: 'gain_guard', amount: 4 }]);
  assert.equal(t.meta[0].forced_return, true); assert.equal(t.meta[0].allow_uncommissioned_boss_retry, true);
});

test('first-run tutorial, glove, ring elite placement, later wish routes and ending conditions are explicit data', () => {
  const t = definitions(), p = t.path[0], m = t.meta[0];
  assert.equal(p.tutorial_encounter_id, 'enc.tutorial'); assert.equal(m.first_commission_id, 'keepsake.ring'); assert.equal(m.first_reward_relic_id, 'relic.lone_glove');
  assert.equal(p.placement.first_run_segment, 4); assert.equal(p.placement.first_run_type, 'elite');
  assert.deepEqual(p.placement.dual_event_routes.map(r => [r.get_segment, r.wish_segment]), [[2, 3], [4, 5]]);
  assert.equal(p.placement.last_drift_segment, 5); assert.equal(p.placement.fallback_segment, 7);
  assert.deepEqual(t.events.find(e => e.id === 'event.aunt_mark').run_numbers, [2, 3]);
  assert.equal(m.ending_return_count, 3); assert.equal(m.ending_requires_boss_victory, true);
  assert.deepEqual(t.pages.find(s => s.id === 'story.ending').when, { all_keepsakes_returned: true, boss_defeated: true });
});

test('numeric battle rules, enemy intent riders, boss forecast and reward counts are data, not UI formulas', () => {
  const t = definitions(), b = t.balance[0];
  for (const [key, expected] of Object.entries({ max_hp: 40, energy_per_turn: 3, draw_per_turn: 4, hand_limit: 8, starter_deck_size: 10, deck_limit: 12, enemy_limit: 4, campfire_heal: 12, campfire_max_hp: 4, retry_hp_fraction: 0.5, retry_enemy_hp_step: 0.2, retry_enemy_hp_cap: 0.4, spare_rope_hp: 1, spare_rope_guard: 10 })) assert.equal(b[key], expected, key);
  assert.deepEqual(t.enemies.find(e => e.id === 'elite.hungry_drawer').intents.map(i => [i.type, i.amount, i.growth ?? 0, i.times ?? 1]), [['guard', 6, 2, 1], ['attack', 9, 0, 1], ['attack', 4, 0, 2]]);
  const boss = t.enemies.find(e => e.id === 'boss.sock_snake');
  assert.deepEqual(boss.mechanics, { summon_enemy_id: 'enemy.sock_kid', summon_per_turn: 1, max_minions: 3, guard_per_minion: 3, full_board_guard: 3, phase_hp_below: 35, phase_damage: 16, phase_warning_turns: 2 });
  assert.equal(boss.intents[2].heal, 6); assert.equal(boss.intents[2].fallback_damage, 10);
});

const mutations = [
  ['malformed top-level table', 'data/enemies.json', (_, f) => f.write('data/enemies.json', {}), /expected.*array/],
  ['missing table file', 'registry.json', (d, f) => rmSync(path.join(f.root, 'content/data/events.json')), /Missing file/],
  ['missing required table', 'registry.json', d => { d.files = d.files.filter(x => x.id !== 'banter'); }, /requires table banter/],
  ['unknown registry table', 'registry.json', d => { d.files[0].id = 'invented'; }, /registry table/],
  ['bad record ID', 'data/relics.json', d => { d[0].id = 'Relic.Bad'; }, /invalid id/],
  ['duplicate global ID', 'data/cards.json', d => { d[1].id = d[0].id; }, /Duplicate content id/],
  ['wrong namespace', 'data/enemies.json', d => { d[0].id = 'card.fake'; }, /namespace/],
  ['unknown op', 'data/cards.json', d => { d[0].ops[0].op = 'hidden_roll'; }, /unknown op/],
  ['unknown op field', 'data/cards.json', d => { d[0].ops[0].ammount = 6; }, /unknown field ammount/],
  ['fractional amount', 'data/cards.json', d => { d[0].ops[0].amount = 1.5; }, /amount/],
  ['string cost', 'data/cards.json', d => { d[0].cost = '1'; }, /cost/],
  ['wrong damage number', 'data/cards.json', d => { d[0].text = '造成 60 点伤害'; }, /text\/ops mismatch/],
  ['appended contradictory effect quantity', 'data/cards.json', d => { d[0].text += '，造成 99 点伤害'; }, /text\/ops mismatch/],
  ['effect stated without operation', 'data/events.json', d => { d[2].choices[1].text += '，获得 1 件奇物'; }, /text\/ops mismatch/],
  ['missing repeat text', 'data/cards.json', d => { d.find(c => c.id === 'card.double_tap').text = '造成 3 点伤害'; }, /repeat mismatch/],
  ['missing discard choice number', 'data/cards.json', d => { d.find(c => c.id === 'card.pick_up').text = '从弃牌堆选 2 张牌放回手里'; }, /text\/ops mismatch/],
  ['invented free-play amount', 'data/cards.json', d => { d.find(c => c.id === 'card.deliver').ops[0].amount = 2; }, /unknown field amount/],
  ['dynamic damage must not have fake constant', 'data/cards.json', d => { d.find(c => c.id === 'card.wring').ops[0].amount = 5; }, /unknown field amount/],
  ['wrong all-enemies target', 'data/cards.json', d => { d[2].target = 'enemy'; }, /damage_all/],
  ['wrong card pool count', 'data/cards.json', d => { d.find(c => c.id === 'card.big_hammer').pool = 'replica'; }, /Card pool/],
  ['wrong starter count', 'data/cards.json', d => { d[0].starterCount = 3; }, /total 10/],
  ['orphan plus variant', 'data/cards.json', d => { d.find(c => c.id === 'card.vow_plus').replica_of = 'card.deliver'; }, /plus variant/],
  ['missing art ref', 'data/enemies.json', d => { d[0].art = 'enemyart.not_ready'; }, /unknown art reference/],
  ['missing audio ref', 'data/cards.json', d => { d[0].audio = 'sfx.not_ready'; }, /unknown audio reference/],
  ['unknown hook', 'data/relics.json', d => { d[0].hook = 'invented'; }, /unknown hook/],
  ['bad hook amount type', 'data/relics.json', d => { d[0].params.repeats = '2'; }, /params.repeats/],
  ['hook text mismatches amount', 'data/relics.json', d => { d[0].params.repeats = 3; }, /text\/ops mismatch/],
  ['unsupported hook parameter', 'data/relics.json', d => { d[0].params.copies = 4; }, /unknown field copies/],
  ['unknown trigger', 'data/relics.json', d => { d[2].trigger = 'roll_dice'; }, /trigger/],
  ['missing enemy reference', 'data/encounters.json', d => { d[0].enemies = ['enemy.absent']; }, /unknown content reference/],
  ['empty encounter', 'data/encounters.json', d => { d[0].enemies = []; }, /enemy count/],
  ['too many enemies', 'data/encounters.json', d => { d[0].enemies = Array(5).fill('enemy.wet_sock'); }, /enemy count/],
  ['unknown enemy intent', 'data/enemies.json', d => { d[0].intents[0].type = 'surprise'; }, /intent.type/],
  ['attack-only rider on guard', 'data/enemies.json', d => { d[0].intents[2].draw_penalty = 1; }, /attack rider/],
  ['boss warning shorter than two windows', 'data/enemies.json', d => { d.at(-1).mechanics.phase_warning_turns = 1; }, /two warning turns/],
  ['duplicate event choices', 'data/events.json', d => { d[2].choices[1].id = d[2].choices[0].id; }, /Duplicate.*choice id/],
  ['node choice contains battle-only op', 'data/events.json', d => { d[0].choices[0].ops = [{ op: 'damage', amount: 8 }]; }, /unknown op/],
  ['event healing text wrong', 'data/events.json', d => { d[0].choices[0].ops[0].amount = 6; }, /text\/ops mismatch/],
  ['unannounced choice effect', 'data/events.json', d => { d[2].choices[1].ops = [{ op: 'lose_hp', amount: 5 }]; }, /text\/ops mismatch/],
  ['empty effect masquerades as reward', 'data/events.json', d => { d[2].choices[0].ops = []; }, /text\/ops mismatch/],
  ['wish condition missing', 'data/events.json', d => { delete d[0].choices[1].when; }, /wish choice/],
  ['wish points to wrong choice', 'data/keepsakes.json', d => { d[1].wish.choice_id = 'sit'; }, /wish choice/],
  ['next battle modifier string not boolean', 'data/events.json', d => { d[4].choices[1].ops[0].first_attack_immune = 'true'; }, /must be true/],
  ['hidden reward quantity mismatch', 'data/events.json', d => { d[0].choices[2].ops[0].bonus_relics = 2; }, /text\/ops mismatch/],
  ['story op points nowhere', 'data/events.json', d => { d[3].choices[1].ops[0].story_id = 'story.missing'; }, /unknown content reference/],
  ['aunt event repeats per save', 'data/events.json', d => { d.at(-1).once_per_save = false; }, /Aunt mark/],
  ['aunt event appears first run', 'data/events.json', d => { d.at(-1).run_numbers = [1, 2]; }, /Aunt mark/],
  ['intro replay condition missing', 'story/pages.json', d => { delete d[0].when; }, /Intro/],
  ['ending misses boss requirement', 'story/pages.json', d => { delete d.find(s => s.id === 'story.ending').when.boss_defeated; }, /Ending/],
  ['meta ending too early', 'data/meta.json', d => { d[0].ending_return_count = 2; }, /ending requires/],
  ['forced return disabled', 'data/meta.json', d => { d[0].forced_return = false; }, /forced return/],
  ['wish bonus page unconditional', 'story/pages.json', d => { delete d.find(s => s.id === 'story.return.ring').pages[2].when; }, /conditional return pages/],
  ['return stamp wrong', 'story/pages.json', d => { d.find(s => s.id === 'story.return.ring').end.stamp = 'card.deliver'; }, /stamp mismatch/],
  ['unknown speaker', 'story/pages.json', d => { d[0].pages[0].speaker = 'npc.absent'; }, /unknown speaker/],
  ['duplicate speaker identity', 'data/ui.json', d => { const rows = d.filter(x => x.kind === 'speaker'); rows[1].speaker = rows[0].speaker; }, /Duplicate speaker identity/],
  ['too long story', 'story/pages.json', d => { d[0].pages[0].text = '啊'.repeat(51); }, /50 characters/],
  ['invalid condition property', 'story/banter.json', d => { d[0].when.chance = true; }, /unknown field chance/],
  ['invalid probability', 'story/banter.json', d => { d[0].chance = 1.1; }, /chance/],
  ['malformed template', 'data/ui.json', d => { d[0].text = '{bad token}'; }, /template token/],
  ['decoration changes battle rules', 'data/ui.json', d => { d.find(x => x.kind === 'decoration').affects_rules = true; }, /must not alter rules/],
  ['route wish before item', 'data/path.json', d => { d[0].placement.dual_event_routes[0].wish_segment = 1; }, /wish must follow/],
  ['route missing event guarantee', 'data/path.json', d => { d[0].segments[1].at_least_event = false; }, /guarantees/],
  ['route wrong fixed campfire', 'data/path.json', d => { d[0].segments[5].types = ['battle']; }, /topology/],
  ['route tier reference wrong', 'data/path.json', d => { d[0].tiers['1'] = ['enc.t3_a']; }, /tier mismatch/],
  ['meta starter deck differs from quantities', 'data/meta.json', d => { d[0].starter_deck[0] = 'card.brace'; }, /starter quantities/],
  ['unknown balance parameter', 'data/balance.json', d => { d[0].max_hpp = 40; }, /unknown field max_hpp/],
  ['invalid retry assistance', 'data/balance.json', d => { d[0].retry_enemy_hp_cap = 1.4; }, /retry_enemy_hp_cap/],
];
for (const [name, file, mutate, pattern] of mutations) test(`strict content rejects ${name}`, t => {
  const f = fixture(t), data = f.read(file);
  mutate(data, f);
  if (!['malformed top-level table', 'missing table file'].includes(name)) f.write(file, data);
  assert.throws(() => checkContent(f.root), pattern);
});

test('dynamic guard, discard choice and free-play texts validate without invented literal amounts', () => {
  const t = definitions();
  for (const id of ['card.wring', 'card.deliver', 'card.deliver_plus', 'card.vow', 'card.vow_plus']) assert.equal(t.cards.find(c => c.id === id).ops[0].amount, undefined);
  assert.equal(t.cards.find(c => c.id === 'card.pick_up').ops[0].amount, 1);
  assert.doesNotThrow(() => checkContent());
});
