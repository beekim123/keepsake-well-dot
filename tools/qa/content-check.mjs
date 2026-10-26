import { ROOT, assert, isMain, readJson, validateId, unique } from '../lib/paths.mjs';
import { loadAssetManifest, loadRegistry } from '../lib/manifests.mjs';

const TABLES = ['cards', 'relics', 'keepsakes', 'enemies', 'encounters', 'events', 'path', 'meta', 'balance', 'pages', 'banter', 'ui'];
const CARD_TYPES = ['attack', 'guard', 'special'];
const TRIGGERS = ['battle_start', 'turn_start', 'card_played', 'turn_end', 'guard_broken', 'enemy_defeated', 'battle_won', 'incoming_attack'];
const BANTER_EVENTS = ['battle_start', 'turn_start', 'card_played', 'big_hit', 'perfect_block', 'player_low_hp', 'enemy_defeated', 'enemy_low_hp', 'boss_phase', 'boss_summon', 'relic_trigger', 'relic_proc', 'keepsake_proc', 'keepsake_get', 'wish_done', 'idle', 'victory', 'defeat', 'retry', 'path_pick', 'hub_enter', 'tutorial_end_turn', 'reward_open', 'path_open', 'return_complete', 'knot_hover', 'enemy_intent', 'spare_rope', 'table_secret'];
const HOOKS = {
  lone_glove: { repeats: 'integer' }, spyglass: { lookahead: 'integer' }, empty_frame: { copies: 'integer' },
  leaky_balloon: { retention: 'fraction' }, crooked_compass: { draw: 'integer' }, bookmark: { keep: 'integer' },
  shedding_brush: { damage: 'integer' }, birthday_candle: { multiplier: 'integer' },
  mianmian: { reduction: 'integer' }, letter: { free_special_cards: 'integer' },
};
const BATTLE_OPS = ['damage', 'damage_all', 'damage_random', 'damage_equal_guard', 'gain_guard', 'heal', 'draw', 'gain_energy', 'next_turn_energy', 'weaken_next_attack', 'set_intent_idle', 'return_from_discard', 'double_guard_this_turn', 'free_play_other', 'retaliate'];
const NODE_OPS = ['heal', 'lose_hp', 'max_hp', 'gain_relic', 'gain_card', 'next_battle', 'complete_wish', 'story'];
const AMOUNT_OPS = new Set(['damage', 'damage_all', 'damage_random', 'gain_guard', 'heal', 'draw', 'gain_energy', 'next_turn_energy', 'weaken_next_attack', 'return_from_discard', 'retaliate', 'lose_hp', 'max_hp', 'gain_relic', 'gain_card']);
const OP_FIELDS = {
  damage: ['amount', 'times', 'target'], damage_all: ['amount', 'times'], damage_random: ['amount', 'times'], damage_equal_guard: [],
  gain_guard: ['amount', 'multiplier'], heal: ['amount'], draw: ['amount'], gain_energy: ['amount'], next_turn_energy: ['amount'],
  weaken_next_attack: ['amount'], set_intent_idle: [], return_from_discard: ['amount'], double_guard_this_turn: [], free_play_other: [], retaliate: ['amount'],
  lose_hp: ['amount'], max_hp: ['amount'], gain_relic: ['amount', 'random', 'relic_id'], gain_card: ['amount', 'random', 'card_id', 'card_type'],
  next_battle: ['enemy_id', 'bonus_relics', 'guard', 'first_attack_immune'], complete_wish: ['keepsake_id'], story: ['story_id'],
};
const SIMPLE_TEXT = {
  damage: n => `造成${n}点伤害`, damage_all: n => `对所有敌人造成${n}点伤害`, damage_random: n => `对随机一个敌人造成${n}点伤害`,
  gain_guard: n => `获得${n}点守护`, draw: n => `抽${n}张牌`, heal: n => `回复${n}点生命`, gain_energy: n => `获得${n}点能量`,
  next_turn_energy: n => `下回合多${n}点能量`, weaken_next_attack: n => `下一次攻击-${n}`, return_from_discard: n => `从弃牌堆选${n}张牌放回手里`,
  retaliate: n => `反击${n}点伤害`, lose_hp: n => `失去${n}点生命`, max_hp: n => `最大生命+${n}`, gain_relic: n => `获得${n}件奇物`,
};
function integer(value, min, max, label) { assert(Number.isInteger(value) && value >= min && value <= max, `${label}: expected integer ${min}..${max}`); }
function number(value, min, max, label) { assert(typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max, `${label}: expected number ${min}..${max}`); }
function text(value, label) { assert(typeof value === 'string' && value.trim().length > 0, `${label}: expected nonempty text`); }
function bool(value, label) { assert(typeof value === 'boolean', `${label}: expected boolean`); }
function object(value, label) { assert(value && typeof value === 'object' && !Array.isArray(value), `${label}: expected object`); }
function array(value, label, min = 0) { assert(Array.isArray(value) && value.length >= min, `${label}: expected array with at least ${min} entries`); }
function oneOf(value, choices, label) { assert(choices.includes(value), `${label}: unknown value ${value}`); }
function fields(value, allowed, label) { for (const key of Object.keys(value)) assert(allowed.includes(key), `${label}: unknown field ${key}`); }
function prefix(id, prefixes, label) { assert(prefixes.some(p => id.startsWith(`${p}.`)), `${label}: invalid id namespace ${id}`); }
function includesText(value, expected, label) { assert(value.replace(/\s/g, '').includes(expected), `${label}: text/ops mismatch; expected ${expected}`); }
function noDuplicates(values, label) { const seen = new Set(); for (const value of values) unique(value, seen, label); }

function conditions(value, label) {
  object(value, label);
  const refs = ['card_id', 'enemy_id', 'relic_id', 'keepsake_id', 'encounter_id', 'event_id', 'wish', 'decoration_id'];
  const strings = ['last_end', 'intent_name'];
  const integers = ['turn', 'card_number', 'minions_at_least'];
  const booleans = ['intro_seen', 'all_keepsakes_returned', 'boss_defeated', 'first_visit'];
  fields(value, [...refs, ...strings, ...integers, ...booleans, 'card_type'], label);
  for (const [key, item] of Object.entries(value)) {
    if (refs.includes(key)) validateId(item, `${label}.${key}`);
    else if (integers.includes(key)) integer(item, 0, 999, `${label}.${key}`);
    else if (booleans.includes(key)) bool(item, `${label}.${key}`);
    else if (key === 'card_type') oneOf(item, CARD_TYPES, `${label}.${key}`);
    else text(item, `${label}.${key}`);
  }
}

// Check every stated fixed quantity, not merely one matching substring. Dynamic
// guard/free-play/choice effects are deliberately not assigned invented numbers.
function checkVisibleAmounts(owner, ops) {
  const value = owner.text.replace(/\s/g, '');
  const patterns = [
    [/造成(\d+)点伤害/g, ['damage', 'damage_all', 'damage_random'], 'damage'],
    [/获得(\d+)点守护/g, ['gain_guard'], 'guard'], [/回复(\d+)点生命/g, ['heal'], 'heal'],
    [/抽(\d+)张牌/g, ['draw'], 'draw'], [/获得(\d+)点能量/g, ['gain_energy'], 'energy'],
    [/下回合多(\d+)点能量/g, ['next_turn_energy'], 'next_energy'],
    [/下一次攻击-(\d+)/g, ['weaken_next_attack'], 'weaken'],
    [/反击(\d+)点伤害/g, ['retaliate'], 'retaliate'], [/失去(\d+)点生命/g, ['lose_hp'], 'lose_hp'],
    [/最大生命\+(\d+)/g, ['max_hp'], 'max_hp'], [/获得(\d+)件奇物/g, ['gain_relic'], 'relic'],
    [/获得(\d+)张(?:随机)?(?:攻击|守护|特殊)?牌/g, ['gain_card'], 'card'],
    [/从弃牌堆选(\d+)张牌/g, ['return_from_discard'], 'discard'],
  ];
  for (const [regex, names, kind] of patterns) {
    const allowed = ops.filter(op => names.includes(op.op)).map(op => op.amount);
    if (kind === 'guard') allowed.push(...ops.filter(op => op.op === 'next_battle' && op.guard !== undefined).map(op => op.guard));
    if (kind === 'relic') allowed.push(...ops.filter(op => op.op === 'next_battle' && op.bonus_relics !== undefined).map(op => op.bonus_relics));
    if (owner.hook === 'shedding_brush' && kind === 'damage') allowed.push(owner.params.damage);
    if (owner.hook === 'crooked_compass' && kind === 'draw') allowed.push(owner.params.draw);
    for (const match of value.matchAll(regex)) assert(allowed.includes(Number(match[1])), `${owner.id}: text/ops mismatch; unrepresented ${kind} quantity ${match[1]}`);
  }
}

function checkOps(ops, owner, { node = false, empty = false, card = false } = {}) {
  array(ops, `${owner.id}.ops`, empty ? 0 : 1);
  for (const effect of ops) {
    object(effect, `${owner.id}.op`);
    assert((node ? NODE_OPS : BATTLE_OPS).includes(effect.op), `${owner.id}: unknown op ${effect.op}`);
    fields(effect, ['op', ...OP_FIELDS[effect.op]], `${owner.id}.${effect.op}`);
    if (AMOUNT_OPS.has(effect.op)) integer(effect.amount, ['gain_card', 'gain_relic', 'return_from_discard'].includes(effect.op) ? 1 : 0, 999, `${owner.id}.${effect.op}.amount`);
    if (effect.times !== undefined) integer(effect.times, 1, 99, `${owner.id}.${effect.op}.times`);
    if (effect.multiplier !== undefined) oneOf(effect.multiplier, ['remaining_energy'], `${owner.id}.multiplier`);
    if (effect.target !== undefined) oneOf(effect.target, ['attacker'], `${owner.id}.target`);
    if (effect.random !== undefined) bool(effect.random, `${owner.id}.random`);
    if (effect.card_type !== undefined) oneOf(effect.card_type, CARD_TYPES, `${owner.id}.card_type`);
    for (const key of ['card_id', 'relic_id', 'enemy_id', 'keepsake_id', 'story_id']) if (effect[key] !== undefined) validateId(effect[key], `${owner.id}.${key}`);
    if (SIMPLE_TEXT[effect.op]) includesText(owner.text, SIMPLE_TEXT[effect.op](effect.amount), owner.id);
    if (effect.times > 1) assert(owner.text.replace(/\s/g, '').includes(`${effect.times}次`), `${owner.id}: text/ops repeat mismatch`);
    if (card && ['damage', 'damage_equal_guard', 'weaken_next_attack', 'set_intent_idle'].includes(effect.op)) assert(owner.target === 'enemy', `${owner.id}: ${effect.op} requires enemy target`);
    if (card && effect.op === 'damage_all') assert(owner.target === 'all_enemies', `${owner.id}: damage_all requires all_enemies target`);
    if (effect.multiplier === 'remaining_energy') includesText(owner.text, '每剩1点能量', owner.id);
    if (effect.op === 'damage_equal_guard') includesText(owner.text, '等于你当前守护的伤害', owner.id);
    if (effect.op === 'double_guard_this_turn') includesText(owner.text, '本回合之后你获得的守护翻倍', owner.id);
    if (effect.op === 'free_play_other') includesText(owner.text, '免费打出你手里的另一张牌', owner.id);
    if (effect.op === 'set_intent_idle') includesText(owner.text, '发呆', owner.id);
    if (effect.op === 'gain_card') {
      assert(effect.random === true || typeof effect.card_id === 'string', `${owner.id}: gain_card requires random or card_id`);
      const type = { attack: '攻击', guard: '守护', special: '特殊' }[effect.card_type] ?? '';
      includesText(owner.text, `获得${effect.amount}张${effect.random ? '随机' : ''}${type}牌`, owner.id);
    }
    if (effect.op === 'gain_relic') assert(effect.random === true || typeof effect.relic_id === 'string', `${owner.id}: gain_relic requires random or relic_id`);
    if (effect.op === 'complete_wish') { validateId(effect.keepsake_id, `${owner.id}.keepsake_id`); includesText(owner.text, '心愿完成', owner.id); }
    if (effect.op === 'story') validateId(effect.story_id, `${owner.id}.story_id`);
    if (effect.op === 'next_battle') {
      assert(Object.keys(effect).length > 1, `${owner.id}: empty next_battle effect`);
      includesText(owner.text, '下一场战斗', owner.id);
      if (effect.guard !== undefined) { integer(effect.guard, 1, 999, `${owner.id}.guard`); includesText(owner.text, `获得${effect.guard}点守护`, owner.id); }
      if (effect.bonus_relics !== undefined) { integer(effect.bonus_relics, 1, 99, `${owner.id}.bonus_relics`); includesText(owner.text, `胜利后额外获得${effect.bonus_relics}件奇物`, owner.id); }
      if (effect.first_attack_immune !== undefined) { assert(effect.first_attack_immune === true, `${owner.id}: first_attack_immune must be true`); includesText(owner.text, '每个敌人的第一次攻击无效', owner.id); }
      if (effect.enemy_id !== undefined) includesText(owner.text, '多1只', owner.id);
    }
  }
  checkVisibleAmounts(owner, ops);
}

function checkCard(card, d1) {
  prefix(card.id, ['card'], card.id); text(card.name, `${card.id}.name`); text(card.text, `${card.id}.text`); text(card.art, `${card.id}.art`);
  oneOf(card.type, CARD_TYPES, `${card.id}.type`); integer(card.cost, 0, 9, `${card.id}.cost`);
  if (card.starterCount !== undefined) integer(card.starterCount, 0, 10, `${card.id}.starterCount`);
  oneOf(card.target, ['enemy', 'all_enemies', 'self', 'none'], `${card.id}.target`);
  if (d1) oneOf(card.pool, ['starter', 'reward', 'replica', 'replica_plus'], `${card.id}.pool`);
  if (card.tendency !== undefined) oneOf(card.tendency, ['attack', 'guard', 'draw', 'general'], `${card.id}.tendency`);
  if (card.uses_per_battle !== undefined) { integer(card.uses_per_battle, 1, 99, `${card.id}.uses_per_battle`); includesText(card.text, `每场战斗限${card.uses_per_battle}次`, card.id); }
  if (d1 && card.pool === 'starter') integer(card.starterCount, 1, 10, `${card.id}.starterCount`);
  if (d1 && card.pool !== 'starter') assert(!card.starterCount, `${card.id}: only starter pool may have starterCount`);
  checkOps(card.ops, card, { card: true });
}
function checkHook(item) {
  text(item.name, `${item.id}.name`); text(item.text, `${item.id}.text`); text(item.art, `${item.id}.art`);
  oneOf(item.trigger, TRIGGERS, `${item.id}.trigger`);
  if (item.when !== undefined) conditions(item.when, `${item.id}.when`);
  if (item.hook !== undefined) {
    assert(HOOKS[item.hook], `${item.id}: unknown hook ${item.hook}`); object(item.params, `${item.id}.params`);
    fields(item.params, Object.keys(HOOKS[item.hook]), `${item.id}.params`);
    for (const [key, type] of Object.entries(HOOKS[item.hook])) {
      if (type === 'fraction') number(item.params[key], 0, 1, `${item.id}.params.${key}`);
      else integer(item.params[key], 1, 999, `${item.id}.params.${key}`);
    }
    assert(item.id.endsWith(`.${item.hook}`), `${item.id}: hook must match stable item id`);
    const p = item.params;
    const hookText = {
      lone_glove: `打${p.repeats}次`, spyglass: `多显示${p.lookahead}回合`, empty_frame: `最高的${p.copies}张牌`,
      leaky_balloon: '改为减半', crooked_compass: `多抽${p.draw}张牌`, bookmark: `留下${p.keep}张手牌`,
      shedding_brush: `额外造成${p.damage}点伤害`, birthday_candle: '效果翻倍', mianmian: `伤害-${p.reduction}`, letter: '第一张特殊牌不花能量',
    };
    includesText(item.text, hookText[item.hook], item.id);
    if (item.hook === 'leaky_balloon') assert(p.retention === 0.5, `${item.id}: text/ops mismatch; 减半 requires retention 0.5`);
    if (item.hook === 'birthday_candle') assert(p.multiplier === 2, `${item.id}: text/ops mismatch; 翻倍 requires multiplier 2`);
    if (item.hook === 'letter') assert(p.free_special_cards === 1, `${item.id}: text/ops mismatch; 第一张 requires 1`);
  }
  checkOps(item.ops, item, { empty: item.hook !== undefined });
}
function checkEnemy(enemy) {
  prefix(enemy.id, ['enemy', 'elite', 'boss'], enemy.id); text(enemy.name, `${enemy.id}.name`); text(enemy.art, `${enemy.id}.art`); integer(enemy.hp, 1, 999, `${enemy.id}.hp`);
  oneOf(enemy.kind, ['normal', 'minion', 'elite', 'boss'], `${enemy.id}.kind`); array(enemy.intents, `${enemy.id}.intents`, 1);
  for (const intent of enemy.intents) {
    object(intent, `${enemy.id}.intent`); oneOf(intent.type, ['attack', 'guard', 'guard_all', 'consume_minion', 'idle'], `${enemy.id}.intent.type`);
    fields(intent, ['type', 'name', 'amount', 'times', 'draw_penalty', 'guard', 'growth', 'heal', 'fallback_damage', 'enemy_id'], `${enemy.id}.intent`);
    text(intent.name, `${enemy.id}.intent.name`);
    if (['attack', 'guard', 'guard_all'].includes(intent.type)) integer(intent.amount, 0, 999, `${enemy.id}.intent.amount`);
    if (intent.times !== undefined) { assert(intent.type === 'attack', `${enemy.id}: only attack has times`); integer(intent.times, 1, 99, `${enemy.id}.intent.times`); }
    for (const key of ['draw_penalty', 'guard', 'growth', 'heal', 'fallback_damage']) if (intent[key] !== undefined) integer(intent[key], 0, 999, `${enemy.id}.intent.${key}`);
    if (intent.growth !== undefined) assert(intent.type === 'guard', `${enemy.id}: growth requires guard intent`);
    if (intent.draw_penalty !== undefined || intent.guard !== undefined) assert(intent.type === 'attack', `${enemy.id}: attack rider requires attack intent`);
    if (intent.type === 'consume_minion') { validateId(intent.enemy_id, `${enemy.id}.intent.enemy_id`); integer(intent.heal, 1, 999, `${enemy.id}.intent.heal`); integer(intent.fallback_damage, 1, 999, `${enemy.id}.intent.fallback_damage`); }
    else assert(intent.heal === undefined && intent.fallback_damage === undefined && intent.enemy_id === undefined, `${enemy.id}: consume fields require consume_minion`);
  }
  if (enemy.kind === 'boss') {
    object(enemy.mechanics, `${enemy.id}.mechanics`);
    fields(enemy.mechanics, ['summon_enemy_id', 'summon_per_turn', 'max_minions', 'guard_per_minion', 'full_board_guard', 'phase_hp_below', 'phase_damage', 'phase_warning_turns'], `${enemy.id}.mechanics`);
    for (const [key, value] of Object.entries(enemy.mechanics)) if (key !== 'summon_enemy_id') integer(value, 1, 999, `${enemy.id}.${key}`);
    validateId(enemy.mechanics.summon_enemy_id, `${enemy.id}.summon_enemy_id`);
    assert(enemy.mechanics.phase_hp_below < enemy.hp, `${enemy.id}: phase threshold must be below starting hp`);
    assert(enemy.mechanics.phase_warning_turns === 2, `${enemy.id}: boss requires two warning turns`);
  }
}

const ART_KEYS = new Set(['art', 'portrait', 'background']);
const AUDIO_KEYS = new Set(['audio', 'sound', 'music', 'sfx']);
const REF_TABLE = {
  card_id: 'cards', plus_card_id: 'cards', replica_of: 'cards', replica_card_id: 'cards', replica_plus_card_id: 'cards', stamp: 'cards', stamp_plus: 'cards',
  enemy_id: 'enemies', summon_enemy_id: 'enemies', relic_id: 'relics', first_reward_relic_id: 'relics', keepsake_id: 'keepsakes', wish: 'keepsakes', first_commission_id: 'keepsakes', first_run_keepsake_id: 'keepsakes',
  encounter_id: 'encounters', tutorial_encounter_id: 'encounters', event_id: 'events', story_id: 'pages', return_story_id: 'pages', first_victory_story_id: 'pages', first_return_story_id: 'pages', ending_story_id: 'pages', intro_story_id: 'pages', boss_knot_story_id: 'pages', back_up_story_id: 'pages', pulled_home_story_id: 'pages', decoration_id: 'ui',
};
function checkReferences(value, ctx, context) {
  if (Array.isArray(value)) { value.forEach(item => checkReferences(item, ctx, context)); return; }
  if (!value || typeof value !== 'object') return;
  for (const [key, item] of Object.entries(value)) {
    if (ART_KEYS.has(key) || AUDIO_KEYS.has(key)) {
      validateId(item, `${context}.${key}`); const kind = ART_KEYS.has(key) ? 'art' : 'audio';
      if (ctx.manifests[kind]) assert(ctx.manifests[kind].has(item), `${context}: unknown ${kind} reference ${item}`);
    }
    if (REF_TABLE[key] && !(key === 'wish' && item && typeof item === 'object' && !Array.isArray(item))) {
      assert(typeof item === 'string' && ctx.ids.has(item), `${context}: unknown content reference ${item}`);
      if (ctx.d1) assert(ctx.tables[REF_TABLE[key]].some(record => record.id === item), `${context}: wrong reference type for ${key}: ${item}`);
    }
    if (['elite_encounter_id', 'boss_encounter_id'].includes(key)) assert(ctx.tables.enemies?.some(record => record.id === item && record.kind === key.split('_')[0]), `${context}: unknown ${key} ${item}`);
    if (['speaker', 'owner'].includes(key)) assert(ctx.speakers.has(item), `${context}: unknown speaker ${item}`);
    checkReferences(item, ctx, context);
  }
}
function idsIn(values, table, label, duplicates = false) {
  array(values, label); if (!duplicates) noDuplicates(values, label);
  for (const id of values) { validateId(id, label); assert(table.some(item => item.id === id), `${label}: unknown content reference ${id}`); }
}

function checkD1(tables) {
  for (const name of TABLES) assert(Array.isArray(tables[name]), `D1 requires table ${name}`);
  const counts = { starter: 4, reward: 14, replica: 3, replica_plus: 3 };
  for (const [pool, count] of Object.entries(counts)) assert(tables.cards.filter(c => c.pool === pool).length === count, `Card pool ${pool} must contain ${count} definitions`);
  for (const [name, count] of Object.entries({ relics: 15, keepsakes: 3, enemies: 9, encounters: 10, events: 6, path: 1, meta: 1, balance: 1 })) assert(tables[name].length === count, `${name} must contain ${count} records`);
  for (const c of tables.cards) {
    if (c.pool === 'replica') {
      const plus = tables.cards.find(x => x.id === c.plus_card_id);
      assert(plus?.pool === 'replica_plus' && plus.replica_of === c.id && plus.keepsake_id === c.keepsake_id, `${c.id}: invalid reciprocal plus variant`);
    }
    if (c.pool === 'replica_plus') assert(tables.cards.some(base => base.pool === 'replica' && base.id === c.replica_of && base.plus_card_id === c.id), `${c.id}: orphan plus variant`);
  }
  for (const relic of tables.relics) { prefix(relic.id, ['relic'], relic.id); text(relic.flavor, `${relic.id}.flavor`); oneOf(relic.tendency, ['attack', 'guard', 'draw', 'general'], `${relic.id}.tendency`); checkHook(relic); }
  for (const k of tables.keepsakes) {
    prefix(k.id, ['keepsake'], k.id); checkHook(k); text(k.owner_name, `${k.id}.owner_name`); text(k.commission_text, `${k.id}.commission_text`); object(k.wish, `${k.id}.wish`);
    text(k.wish.name, `${k.id}.wish.name`); text(k.wish.text, `${k.id}.wish.text`); oneOf(k.wish.type, ['campfire_rest', 'event_choice'], `${k.id}.wish.type`);
    const base = tables.cards.find(c => c.id === k.replica_card_id), plus = tables.cards.find(c => c.id === k.replica_plus_card_id);
    assert(base?.keepsake_id === k.id && plus?.replica_of === base.id, `${k.id}: replica links do not match keepsake`);
    if (k.wish.type === 'event_choice') {
      const event = tables.events.find(e => e.id === k.wish.event_id), choice = event?.choices.find(c => c.id === k.wish.choice_id);
      assert(choice?.when?.keepsake_id === k.id && choice.ops.some(op => op.op === 'complete_wish' && op.keepsake_id === k.id), `${k.id}: wish choice missing or does not complete matching wish`);
    } else assert(k.wish.event_id === undefined && k.wish.choice_id === undefined, `${k.id}: campfire wish cannot reference event choice`);
  }
  for (const enemy of tables.enemies) checkEnemy(enemy);
  for (const e of tables.encounters) { prefix(e.id, ['enc'], e.id); integer(e.tier, 1, 3, `${e.id}.tier`); idsIn(e.enemies, tables.enemies, `${e.id}.enemies`, true); assert(e.enemies.length > 0 && e.enemies.length <= tables.balance[0].enemy_limit, `${e.id}: enemy count outside limit`); bool(e.tutorial, `${e.id}.tutorial`); }
  for (const event of tables.events) {
    prefix(event.id, ['event'], event.id); text(event.name, `${event.id}.name`); text(event.description, `${event.id}.description`); text(event.art, `${event.id}.art`); array(event.choices, `${event.id}.choices`, 2); assert(event.choices.length <= 4, `${event.id}: too many choices`);
    const choices = new Set();
    for (const choice of event.choices) {
      object(choice, `${event.id}.choice`); fields(choice, ['id', 'text', 'when', 'ops'], `${event.id}.choice`); validateId(choice.id, event.id); unique(choice.id, choices, `${event.id} choice id`); text(choice.text, `${event.id}.${choice.id}.text`);
      if (choice.when) { conditions(choice.when, `${event.id}.${choice.id}.when`); fields(choice.when, ['keepsake_id'], `${event.id}.${choice.id}.when`); }
      checkOps(choice.ops, { ...choice, id: `${event.id}.${choice.id}` }, { node: true, empty: true });
      if (!choice.ops.length) includesText(choice.text, '不发生变化', `${event.id}.${choice.id}`);
      for (const op of choice.ops) if (op.op === 'complete_wish') assert(choice.when?.keepsake_id === op.keepsake_id, `${event.id}.${choice.id}: wish choice must require its keepsake`);
    }
    if (event.once !== undefined) oneOf(event.once, ['save'], `${event.id}.once`);
    if (event.once_per_save !== undefined) bool(event.once_per_save, `${event.id}.once_per_save`);
    if (event.run_numbers !== undefined) { array(event.run_numbers, `${event.id}.run_numbers`, 1); noDuplicates(event.run_numbers, `${event.id}.run_numbers`); event.run_numbers.forEach(n => integer(n, 1, 999, `${event.id}.run_numbers`)); }
  }
  checkWorld(tables);
}

function checkWorld(t) {
  const b = t.balance[0], p = t.path[0], m = t.meta[0];
  assert(b.id === 'balance.default' && p.id === 'path.sock_marsh' && m.id === 'meta.default', 'Expected stable default balance/path/meta ids');
  const fractionKeys = ['retry_hp_fraction', 'retry_enemy_hp_step', 'retry_enemy_hp_cap', 'low_hp_fraction'];
  const timeKeys = ['banter_base_seconds', 'banter_seconds_per_character', 'banter_cooldown_seconds', 'banter_priority_lock_seconds'];
  const intKeys = ['max_hp', 'energy_per_turn', 'draw_per_turn', 'hand_limit', 'starter_deck_size', 'deck_limit', 'enemy_limit', 'spare_rope_hp', 'spare_rope_guard', 'campfire_heal', 'campfire_max_hp', 'max_commissions', 'reward_normal_relics', 'reward_normal_cards', 'reward_elite_relics', 'trade_offer_count', 'departure_offer_count', 'big_hit_threshold', 'idle_seconds', 'simulation_turn_seconds', 'simulation_node_seconds'];
  fields(b, ['id', ...fractionKeys, ...timeKeys, ...intKeys], b.id);
  intKeys.forEach(k => integer(b[k], 1, 999, `${b.id}.${k}`)); fractionKeys.forEach(k => number(b[k], 0, 1, `${b.id}.${k}`)); timeKeys.forEach(k => number(b[k], 0, 99, `${b.id}.${k}`));
  assert(b.deck_limit >= b.starter_deck_size && b.hand_limit <= b.deck_limit, `${b.id}: invalid deck/hand limits`);
  assert(b.retry_enemy_hp_step <= b.retry_enemy_hp_cap, `${b.id}: retry step exceeds cap`);
  assert(b.max_commissions === 2 && b.enemy_limit === 4, `${b.id}: commission/enemy limits conflict with fixed demo scope`);
  assert(t.enemies.find(e => e.kind === 'boss').mechanics.max_minions < b.enemy_limit, 'Boss minions must leave space for boss');
  integer(p.segment_count, 7, 7, `${p.id}.segment_count`); array(p.segments, `${p.id}.segments`, 7); assert(p.segments.length === p.segment_count, `${p.id}: segment count mismatch`);
  const types = ['battle', 'elite', 'event', 'campfire', 'trade', 'boss'];
  p.segments.forEach((s, i) => { object(s, `${p.id}.segment`); integer(s.segment, i + 1, i + 1, `${p.id}.segment`); array(s.types, `${p.id}.types`, 1); noDuplicates(s.types, `${p.id}.types`); s.types.forEach(type => oneOf(type, types, `${p.id}.type`)); integer(s.choices, 1, 2, `${p.id}.choices`); if (s.tier !== undefined) integer(s.tier, 1, 3, `${p.id}.tier`); for (const k of ['at_least_event', 'distinct_types']) if (s[k] !== undefined) bool(s[k], `${p.id}.${k}`); });
  const expectedTypes = [['battle'], ['battle', 'event'], ['event', 'trade', 'battle'], ['elite', 'campfire'], ['battle', 'event'], ['campfire'], ['boss']];
  p.segments.forEach((s, i) => { assert(JSON.stringify(s.types) === JSON.stringify(expectedTypes[i]), `${p.id}: segment ${i + 1} type pool differs from required topology`); assert(s.choices === ([0, 5, 6].includes(i) ? 1 : 2), `${p.id}: segment ${i + 1} choice count mismatch`); });
  assert(p.segments[1].at_least_event === true && p.segments[2].distinct_types === true, `${p.id}: event/distinct guarantees missing`);
  assert(JSON.stringify(p.segments[3].types) === '["elite","campfire"]' && p.segments[5].types[0] === 'campfire' && p.segments[6].types[0] === 'boss', `${p.id}: required elite/campfire/boss topology missing`);
  object(p.hints, `${p.id}.hints`); for (const type of types) { array(p.hints[type], `${p.id}.hints.${type}`, 1); p.hints[type].forEach(h => text(h, `${p.id}.hint`)); }
  object(p.tiers, `${p.id}.tiers`); for (const tier of ['1', '2', '3']) { idsIn(p.tiers[tier], t.encounters, `${p.id}.tiers.${tier}`); assert(p.tiers[tier].every(id => t.encounters.find(e => e.id === id).tier === Number(tier)), `${p.id}: encounter tier mismatch`); }
  assert(p.no_repeat_events === true, `${p.id}: events must not repeat`);
  object(p.placement, `${p.id}.placement`); const placement = p.placement;
  for (const key of ['first_run_segment', 'last_drift_segment', 'fallback_segment']) integer(placement[key], 1, p.segment_count, `${p.id}.${key}`);
  for (const key of ['event_keepsake_segments', 'event_wish_segments', 'campfire_keepsake_segments']) { array(placement[key], `${p.id}.${key}`, 1); placement[key].forEach(n => integer(n, 1, p.segment_count, `${p.id}.${key}`)); noDuplicates(placement[key], `${p.id}.${key}`); }
  array(placement.dual_event_routes, `${p.id}.dual_event_routes`, 2); assert(placement.dual_event_routes.length === 2, `${p.id}: requires two separate event wish routes`);
  for (const route of placement.dual_event_routes) { integer(route.get_segment, 1, 7, `${p.id}.get_segment`); integer(route.wish_segment, 1, 7, `${p.id}.wish_segment`); assert(route.get_segment < route.wish_segment, `${p.id}: wish must follow keepsake`); assert(placement.event_wish_segments.includes(route.wish_segment), `${p.id}: route wish not in allowed segments`); }
  noDuplicates(placement.dual_event_routes.map(r => r.get_segment), `${p.id} keepsake segment`); noDuplicates(placement.dual_event_routes.map(r => r.wish_segment), `${p.id} wish segment`);
  assert(placement.first_run_segment === 4 && placement.first_run_type === 'elite' && placement.fallback_segment === 7 && placement.last_drift_segment === 5, `${p.id}: fixed first-run/drift rules mismatch`);
  idsIn(m.commission_ids, t.keepsakes, `${m.id}.commission_ids`); assert(m.commission_ids.length === t.keepsakes.length, `${m.id}: commissions incomplete`);
  idsIn(m.starter_deck, t.cards, `${m.id}.starter_deck`, true); assert(m.starter_deck.length === b.starter_deck_size, `${m.id}: starter deck count mismatch`);
  for (const card of t.cards) assert(m.starter_deck.filter(id => id === card.id).length === (card.starterCount ?? 0), `${m.id}: starter quantities mismatch for ${card.id}`);
  array(m.services, `${m.id}.services`, 3); noDuplicates(m.services.map(s => s.id), `${m.id} service`);
  for (const s of m.services) { oneOf(s.id, ['departure_choice', 'double_commission', 'spare_rope'], `${m.id}.service.id`); integer(s.returned, 1, t.keepsakes.length, `${m.id}.returned`); }
  assert(m.ending_return_count === t.keepsakes.length && m.ending_requires_boss_victory === true, `${m.id}: ending requires every keepsake and boss victory`);
  assert(m.forced_return === true && m.allow_uncommissioned_boss_retry === true, `${m.id}: forced return or no-commission boss retry missing`);
  const aunt = t.events.find(e => e.id === 'event.aunt_mark'); assert(aunt?.once_per_save === true && aunt.once === 'save' && JSON.stringify(aunt.run_numbers) === '[2,3]', 'Aunt mark must be once per save, only runs 2/3');
  const intro = t.pages.find(s => s.id === m.intro_story_id), ending = t.pages.find(s => s.id === m.ending_story_id);
  assert(intro?.when?.intro_seen === false && intro.pages.length === 4, 'Intro must have four pages and unseen condition');
  assert(ending?.when?.all_keepsakes_returned === true && ending.when.boss_defeated === true && ending.end?.demo_complete === true && ending.pages.length === 4, 'Ending requires returned keepsakes and defeated boss, then demo_complete');
  for (const k of t.keepsakes) {
    const story = t.pages.find(s => s.id === k.return_story_id); assert(story?.pages.length === 4, `${k.id}: return story needs three regular pages and one wish page`);
    assert(story.pages.filter(pg => pg.when?.wish === k.id).length === 1 && story.pages.filter(pg => pg.when === undefined).length === 3, `${k.id}: invalid conditional return pages`);
    assert(story.end?.stamp === k.replica_card_id && story.end.stamp_plus === k.replica_plus_card_id && story.end.keepsake_id === k.id, `${k.id}: story stamp mismatch`);
  }
}

function checkStory(t) {
  for (const sequence of t.pages ?? []) {
    prefix(sequence.id, ['story'], sequence.id); array(sequence.pages, `${sequence.id}.pages`, 1);
    if (sequence.when !== undefined) conditions(sequence.when, `${sequence.id}.when`);
    if (sequence.once !== undefined) oneOf(sequence.once, ['save', 'run'], `${sequence.id}.once`);
    if (sequence.end !== undefined) { object(sequence.end, `${sequence.id}.end`); fields(sequence.end, ['stamp', 'stamp_plus', 'keepsake_id', 'demo_complete'], `${sequence.id}.end`); if (sequence.end.demo_complete !== undefined) bool(sequence.end.demo_complete, `${sequence.id}.end.demo_complete`); }
    for (const [index, pg] of sequence.pages.entries()) {
      object(pg, `${sequence.id}.page`); text(pg.text, `${sequence.id}.${index}.text`); assert([...(pg.text + (pg.caption ?? ''))].length <= 50, `${sequence.id}.${index}: story text exceeds 50 characters`); text(pg.speaker, `${sequence.id}.speaker`); array(pg.layers, `${sequence.id}.layers`);
      if (pg.caption !== undefined) text(pg.caption, `${sequence.id}.caption`);
      if (pg.when !== undefined) conditions(pg.when, `${sequence.id}.page.when`);
      if (pg.tone !== undefined) oneOf(pg.tone, ['memory', 'normal'], `${sequence.id}.tone`);
      for (const layer of pg.layers) { object(layer, `${sequence.id}.layer`); text(layer.art, `${sequence.id}.layer.art`); integer(layer.x, -640, 640, `${sequence.id}.layer.x`); integer(layer.y, -360, 360, `${sequence.id}.layer.y`); if (layer.anim !== undefined) text(layer.anim, `${sequence.id}.layer.anim`); }
    }
  }
  for (const line of t.banter ?? []) {
    prefix(line.id, ['banter'], line.id); oneOf(line.event, BANTER_EVENTS, `${line.id}.event`); text(line.speaker, `${line.id}.speaker`); array(line.lines, `${line.id}.lines`, 1);
    line.lines.forEach(value => { text(value, `${line.id}.line`); assert([...value].length <= 18, `${line.id}: banter exceeds 18 characters`); });
    oneOf(line.once, ['none', 'battle', 'run', 'save'], `${line.id}.once`); number(line.chance, 0, 1, `${line.id}.chance`); bool(line.priority, `${line.id}.priority`); if (line.when !== undefined) conditions(line.when, `${line.id}.when`);
  }
  for (const item of t.ui ?? []) {
    prefix(item.id, ['ui', 'speaker', 'table'], item.id); text(item.text, `${item.id}.text`);
    if (item.kind === 'speaker') { prefix(item.id, ['speaker'], item.id); text(item.speaker, `${item.id}.speaker`); }
    else if (item.kind === 'decoration') { prefix(item.id, ['table'], item.id); text(item.normal_text, `${item.id}.normal_text`); text(item.secret_text, `${item.id}.secret_text`); integer(item.click_threshold, 1, 99, `${item.id}.click_threshold`); bool(item.once_per_save, `${item.id}.once_per_save`); assert(item.affects_rules === false, `${item.id}: decorations must not alter rules`); }
    else assert(item.kind === undefined && item.id.startsWith('ui.'), `${item.id}: unknown UI record kind`);
    for (const match of item.text.matchAll(/\{([^}]*)\}/g)) assert(/^[a-z][a-z0-9_]*$/.test(match[1]), `${item.id}: malformed template token`);
    assert((item.text.match(/\{/g) ?? []).length === (item.text.match(/\}/g) ?? []).length, `${item.id}: unbalanced template token`);
  }
}

export function checkContent(root = ROOT) {
  const registry = loadRegistry(root), d1 = registry.stage === 'D1';
  assert(registry.stage === undefined || d1, `Unknown content stage ${registry.stage}`);
  const warnings = [], manifests = {}, ids = new Set(), tables = {}, items = [];
  for (const kind of ['art', 'audio']) {
    const manifest = loadAssetManifest(root, kind, { optional: true }); manifests[kind] = manifest ? new Set(manifest.assets.map(asset => asset.id)) : null;
    if (!manifest) warnings.push(`${kind} manifest absent: resource references not checked; build resources before full check.`);
  }
  for (const entry of registry.files) {
    if (d1) oneOf(entry.id, TABLES, 'registry table');
    const data = readJson(root, `content/${entry.file}`); array(data, `${entry.file}: expected a top-level array`); tables[entry.id] = data;
    for (const item of data) { object(item, entry.file); validateId(item.id, entry.file); unique(item.id, ids, 'content id'); items.push(item); }
  }
  const cards = tables.cards ?? items.filter(i => i.id.startsWith('card.'));
  cards.forEach(c => checkCard(c, d1));
  const starterCount = cards.reduce((n, c) => n + (c.starterCount ?? 0), 0);
  assert(cards.length > 0, 'No card definitions registered'); assert(starterCount === 10, `Starter deck must total 10 cards, got ${starterCount}`);
  checkStory(tables);
  if (d1) checkD1(tables);
  const speakers = new Set((tables.ui ?? []).filter(i => i.kind === 'speaker').map(i => i.speaker));
  noDuplicates((tables.ui ?? []).filter(i => i.kind === 'speaker').map(i => i.speaker), 'speaker identity');
  for (const item of [...(tables.enemies ?? []), ...(tables.keepsakes ?? [])]) speakers.add(item.id);
  for (const item of items) checkReferences(item, { ids, tables, manifests, speakers, d1 }, item.id);
  return { scope: d1 ? 'D1 complete source data and references; graybox assets, not full-game implementation acceptance' : 'D0 content foundation, not full D1 content validation', files: registry.files.length, records: items.length, cards: cards.length, starterCount, storyPages: (tables.pages ?? []).reduce((n, s) => n + s.pages.length, 0), warnings };
}

if (isMain(import.meta.url)) {
  try {
    assert(process.argv.length === 2, 'Usage: node tools/qa/content-check.mjs'); const result = checkContent();
    for (const warning of result.warnings) console.warn(`WARNING: ${warning}`);
    console.log(`content:check PASS — ${result.cards} card definitions / ${result.starterCount} starting cards, ${result.records} records, ${result.storyPages} story pages; ${result.scope}`);
  } catch (error) { console.error(`content:check FAIL — ${error.message}`); process.exitCode = 1; }
}
