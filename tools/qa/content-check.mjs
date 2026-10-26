import { ROOT, assert, isMain, readJson, validateId, unique } from '../lib/paths.mjs';
import { loadAssetManifest, loadRegistry } from '../lib/manifests.mjs';

const OPS = new Set([
  'damage', 'damage_all', 'damage_random', 'damage_equal_guard', 'gain_guard',
  'heal', 'draw', 'gain_energy', 'next_turn_energy', 'weaken_next_attack',
  'set_intent_idle', 'return_from_discard', 'double_guard_this_turn',
  'free_play_other', 'retaliate', 'lose_hp', 'max_hp', 'gain_relic', 'gain_card',
  'next_battle', 'complete_wish', 'story',
]);
const AMOUNT_OPS = new Set(['damage', 'damage_all', 'damage_random', 'gain_guard', 'heal', 'draw', 'gain_energy', 'next_turn_energy', 'weaken_next_attack', 'retaliate', 'lose_hp', 'max_hp']);
const SIMPLE_TEXT = {
  damage: n => `造成${n}点伤害`,
  damage_all: n => `对所有敌人造成${n}点伤害`,
  gain_guard: n => `获得${n}点守护`,
  draw: n => `抽${n}张牌`,
  heal: n => `回复${n}点生命`,
  gain_energy: n => `获得${n}点能量`,
  next_turn_energy: n => `下回合多${n}点能量`,
};

function integer(value, min, max, label) {
  assert(Number.isInteger(value) && value >= min && value <= max, `${label}: expected integer ${min}..${max}`);
}
function text(value, label) { assert(typeof value === 'string' && value.trim().length > 0, `${label}: expected nonempty text`); }

function checkCard(card) {
  text(card.name, `${card.id}.name`);
  text(card.text, `${card.id}.text`);
  text(card.art, `${card.id}.art`);
  assert(['attack', 'guard', 'special'].includes(card.type), `${card.id}: invalid card type`);
  integer(card.cost, 0, 9, `${card.id}.cost`);
  if (card.starterCount !== undefined) integer(card.starterCount, 0, 10, `${card.id}.starterCount`);
  assert(['enemy', 'all_enemies', 'self', 'none'].includes(card.target), `${card.id}: invalid target`);
  assert(Array.isArray(card.ops) && card.ops.length > 0, `${card.id}: requires ops`);
  const normalized = card.text.replace(/\s/g, '');
  for (const effect of card.ops) {
    assert(effect && OPS.has(effect.op), `${card.id}: unknown op ${effect?.op}`);
    if (AMOUNT_OPS.has(effect.op)) integer(effect.amount, 0, 999, `${card.id}.${effect.op}.amount`);
    if (effect.times !== undefined) integer(effect.times, 1, 99, `${card.id}.${effect.op}.times`);
    if (SIMPLE_TEXT[effect.op]) {
      const expected = SIMPLE_TEXT[effect.op](effect.amount);
      assert(normalized.includes(expected), `${card.id}: text/ops mismatch; expected ${expected}`);
    }
    if (effect.times > 1) assert(normalized.includes(`${effect.times}次`), `${card.id}: text/ops repeat mismatch`);
    if (effect.op === 'damage_all') assert(card.target === 'all_enemies', `${card.id}: damage_all requires all_enemies target`);
    if (effect.op === 'damage') assert(card.target === 'enemy', `${card.id}: damage requires enemy target`);
  }
}

const ART_KEYS = new Set(['art', 'portrait', 'background']);
const AUDIO_KEYS = new Set(['audio', 'sound', 'music', 'sfx']);
const CONTENT_REF_KEYS = new Set(['card_id', 'enemy_id', 'relic_id', 'keepsake_id', 'encounter_id', 'event_id', 'story_id']);

function checkReferences(value, ids, manifests, context) {
  if (Array.isArray(value)) { value.forEach(item => checkReferences(item, ids, manifests, context)); return; }
  if (!value || typeof value !== 'object') return;
  for (const [key, item] of Object.entries(value)) {
    if (ART_KEYS.has(key) || AUDIO_KEYS.has(key)) {
      validateId(item, `${context}.${key}`);
      const kind = ART_KEYS.has(key) ? 'art' : 'audio';
      if (manifests[kind]) assert(manifests[kind].has(item), `${context}: unknown ${kind} reference ${item}`);
    }
    if (CONTENT_REF_KEYS.has(key)) assert(typeof item === 'string' && ids.has(item), `${context}: unknown content reference ${item}`);
    checkReferences(item, ids, manifests, context);
  }
}

export function checkContent(root = ROOT) {
  const registry = loadRegistry(root);
  const warnings = [], manifests = {};
  for (const kind of ['art', 'audio']) {
    const manifest = loadAssetManifest(root, kind, { optional: true });
    manifests[kind] = manifest ? new Set(manifest.assets.map(asset => asset.id)) : null;
    if (!manifest) warnings.push(`${kind} manifest absent: resource references not checked; build resources before full check.`);
  }
  const ids = new Set(), items = [];
  let cards = 0, starterCount = 0;
  for (const entry of registry.files) {
    const data = readJson(root, `content/${entry.file}`);
    assert(Array.isArray(data), `${entry.file}: expected a top-level array`);
    for (const item of data) {
      assert(item && typeof item === 'object' && !Array.isArray(item), `${entry.file}: invalid record`);
      validateId(item.id, entry.file);
      unique(item.id, ids, 'content id');
      if (item.id.startsWith('card.')) { checkCard(item); cards++; starterCount += item.starterCount ?? 0; }
      if (item.id.startsWith('ui.')) text(item.text, `${item.id}.text`);
      items.push(item);
    }
  }
  for (const item of items) checkReferences(item, ids, manifests, item.id);
  assert(cards > 0, 'No card definitions registered');
  assert(starterCount === 10, `Starter deck must total 10 cards, got ${starterCount}`);
  return { scope: 'D0 content foundation, not full D1 content validation', files: registry.files.length, records: items.length, cards, starterCount, warnings };
}

if (isMain(import.meta.url)) {
  try {
    assert(process.argv.length === 2, 'Usage: node tools/qa/content-check.mjs');
    const result = checkContent();
    for (const warning of result.warnings) console.warn(`WARNING: ${warning}`);
    console.log(`content:check PASS — ${result.cards} card definitions / ${result.starterCount} starting cards, ${result.records} records; ${result.scope}`);
  } catch (error) { console.error(`content:check FAIL — ${error.message}`); process.exitCode = 1; }
}
