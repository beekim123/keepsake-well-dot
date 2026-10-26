import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, readdirSync, statSync, symlinkSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { ROOT, relativePath, safePath, sha256, jsonBytes } from '../tools/lib/paths.mjs';
import { checkContent } from '../tools/qa/content-check.mjs';
import { buildPlan, syncGodot } from '../tools/resources/sync-godot.mjs';
import { assertGodotVersion, selectGodot, verifyGodot, commandArguments, commandEnvironment, simulationCount, validateOutput } from '../tools/godot/cli.mjs';

function fixture(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'keepsake-foundation-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const write = (file, bytes) => { mkdirSync(path.dirname(path.join(root, file)), { recursive: true }); writeFileSync(path.join(root, file), bytes); };
  const json = (file, value) => write(file, jsonBytes(value));
  const read = file => JSON.parse(readFileSync(path.join(root, file), 'utf8'));
  for (const file of ['registry.json', 'data/cards.json', 'data/ui.json']) write(`content/${file}`, readFileSync(path.join(ROOT, 'tests/fixtures/d0/content', file)));
  for (const [kind, id, name] of [['art', 'ui.panel.default', 'ui/panel.png'], ['audio', 'sfx.ui_click', 'click.wav']]) {
    const bytes = Buffer.from(`${kind} byte-fixture; format correctness is tested by its independent pipeline`);
    write(`resources/${kind}/export/${name}`, bytes);
    json(`resources/${kind}/export/manifest.json`, { format: `${kind}-manifest/1`, assets: [{ id, file: name, hash: sha256(bytes) }] });
  }
  const font = 'third_party/fonts/fusion-pixel-12px';
  for (const file of ['fusion-pixel-12px-proportional-zh_hans.otf.woff2', 'OFL.txt', 'LICENSES/ark-pixel/OFL.txt', 'LICENSES/cubic-11/OFL.txt', 'LICENSES/galmuri/LICENSE.txt']) write(`${font}/${file}`, `test-fixture ${file}`);
  mkdirSync(path.join(root, 'godot'), { recursive: true });
  return { root, write, json, read };
}

function snapshot(root) {
  const result = {};
  function visit(relative) {
    for (const name of readdirSync(path.join(root, relative)).sort()) {
      const next = relative ? `${relative}/${name}` : name;
      const stat = statSync(path.join(root, next));
      if (stat.isDirectory()) visit(next);
      else result[next] = { hash: sha256(readFileSync(path.join(root, next))), mtime: stat.mtimeMs };
    }
  }
  visit('');
  return result;
}

test('D0 card definitions and UI pass with explicit scope', t => {
  const f = fixture(t), result = checkContent(f.root);
  assert.equal(result.cards, 4);
  assert.equal(result.starterCount, 10);
  assert.equal(result.records, 18);
  assert.deepEqual(result.warnings, []);
  assert.match(result.scope, /not full D1/);
});

test('content-only check warns rather than inventing absent resource checks', t => {
  const f = fixture(t);
  rmSync(path.join(f.root, 'resources'), { recursive: true });
  assert.equal(checkContent(f.root).warnings.length, 2);
  assert.throws(() => buildPlan(f.root), /Missing file/);
});

for (const [name, mutate, pattern] of [
  ['cost range', cards => { cards[0].cost = -1; }, /cost/],
  ['fractional amount', cards => { cards[0].ops[0].amount = 1.5; }, /amount/],
  ['wrong text number', cards => { cards[0].text = '造成 16 点伤害'; }, /text\/ops mismatch/],
  ['unknown op', cards => { cards[0].ops[0].op = 'explode_everything'; }, /unknown op/],
  ['wrong target', cards => { cards[2].target = 'enemy'; }, /damage_all/],
  ['missing repeat text', cards => { cards[0].ops[0].times = 2; }, /repeat mismatch/],
  ['duplicate id', cards => { cards[1].id = cards[0].id; }, /Duplicate content id/],
  ['invalid id', cards => { cards[0].id = 'Card.Knock'; }, /invalid id/],
  ['missing art', cards => { cards[0].art = 'cardart.not_yet_drawn'; }, /unknown art reference/],
  ['missing audio', cards => { cards[0].audio = 'sfx.missing'; }, /unknown audio reference/],
  ['missing content reference', cards => { cards[0].card_id = 'card.missing'; }, /unknown content reference/],
  ['starter quantity', cards => { cards[0].starterCount = 3; }, /total 10/],
]) test(`content rejects ${name}`, t => {
  const f = fixture(t), cards = f.read('content/data/cards.json');
  mutate(cards); f.json('content/data/cards.json', cards);
  assert.throws(() => checkContent(f.root), pattern);
});

test('safe relative paths reject traversal and ambiguous platform paths', t => {
  const f = fixture(t);
  for (const unsafe of ['../a', 'a/../b', '/tmp/a', 'C:/a', 'a\\b', './a', 'a//b', 'a/./b', 'a/']) assert.throws(() => relativePath(unsafe), /unsafe/);
  assert.equal(relativePath('story/pages.json'), 'story/pages.json');
  symlinkSync(path.join(f.root, 'content'), path.join(f.root, 'linked'));
  assert.throws(() => safePath(f.root, 'linked/data/cards.json'), /Symlink/);
  assert.throws(() => safePath(f.root, 'linked/new/not-created.json'), /Symlink/);
});

test('registry duplicate source and target paths fail, including case aliases', t => {
  const f = fixture(t), registry = f.read('content/registry.json');
  registry.files[1].target = 'CARDS.json'; f.json('content/registry.json', registry);
  assert.throws(() => checkContent(f.root), /Duplicate content target path/);
  registry.files[1].target = 'ui.json'; registry.files[1].file = registry.files[0].file; f.json('content/registry.json', registry);
  assert.throws(() => checkContent(f.root), /Duplicate content source path/);
});

test('asset manifest rejects duplicate ids, duplicate paths, hashes and traversal', t => {
  const f = fixture(t), file = 'resources/art/export/manifest.json', original = f.read(file);
  let manifest = structuredClone(original);
  manifest.assets.push({ ...manifest.assets[0] }); f.json(file, manifest);
  assert.throws(() => buildPlan(f.root), /Duplicate asset id/);
  manifest.assets[1].id = 'ui.second'; f.json(file, manifest);
  assert.throws(() => buildPlan(f.root), /Duplicate asset path/);
  manifest = structuredClone(original); manifest.assets[0].hash = '0'.repeat(64); f.json(file, manifest);
  assert.throws(() => buildPlan(f.root), /source hash mismatch/);
  manifest = structuredClone(original); manifest.assets[0].file = '../escape.png'; f.json(file, manifest);
  assert.throws(() => buildPlan(f.root), /unsafe path/);
});

test('sync is deterministic, preserves unmanaged files, and verify never writes', t => {
  const f = fixture(t);
  f.write('godot/resources/unmanaged.txt', 'keep me');
  f.write('resources/art/export/unregistered.png', 'must not copy');
  const first = syncGodot(f.root);
  const before = snapshot(f.root);
  assert.equal(syncGodot(f.root, { verify: true }).verified, true);
  assert.deepEqual(snapshot(f.root), before);
  assert.equal(syncGodot(f.root).files, first.files);
  assert.deepEqual(snapshot(f.root), before);
  assert.equal(readFileSync(path.join(f.root, 'godot/resources/unmanaged.txt'), 'utf8'), 'keep me');
  assert.equal(existsSync(path.join(f.root, 'godot/resources/art/unregistered.png')), false);
  for (const entry of f.read('godot/resource-pack.json').files) {
    assert.equal(path.isAbsolute(entry.path), false);
    assert.equal(path.isAbsolute(entry.source), false);
    assert.equal(entry.hash, sha256(readFileSync(path.join(f.root, 'godot', entry.path))));
  }
});

test('verify detects stale copies and pack without repairing either', t => {
  const f = fixture(t); syncGodot(f.root);
  f.write('godot/data/cards.json', 'changed');
  let before = snapshot(f.root);
  assert.throws(() => syncGodot(f.root, { verify: true }), /Synced bytes differ/);
  assert.deepEqual(snapshot(f.root), before);
  syncGodot(f.root);
  const pack = f.read('godot/resource-pack.json'); pack.files[0].hash = '0'.repeat(64); f.json('godot/resource-pack.json', pack);
  before = snapshot(f.root);
  assert.throws(() => syncGodot(f.root, { verify: true }), /Resource pack is stale/);
  assert.deepEqual(snapshot(f.root), before);
});

test('cleanup removes only former managed file and preserves unrelated files', t => {
  const f = fixture(t), manifest = f.read('resources/art/export/manifest.json');
  f.write('resources/art/export/old.png', 'old');
  manifest.assets.push({ id: 'ui.old', file: 'old.png', hash: sha256(Buffer.from('old')) });
  f.json('resources/art/export/manifest.json', manifest); syncGodot(f.root);
  f.write('godot/resources/art/notes.txt', 'unmanaged');
  manifest.assets.pop(); f.json('resources/art/export/manifest.json', manifest);
  assert.equal(syncGodot(f.root).removed, 1);
  assert.equal(existsSync(path.join(f.root, 'godot/resources/art/old.png')), false);
  assert.equal(readFileSync(path.join(f.root, 'godot/resources/art/notes.txt'), 'utf8'), 'unmanaged');
  assert.equal(syncGodot(f.root, { verify: true }).verified, true);
});

test('modified stale file aborts preflight without partial writes', t => {
  const f = fixture(t), registry = f.read('content/registry.json'); syncGodot(f.root);
  f.write('godot/data/ui.json', 'local edits');
  registry.files.pop(); f.json('content/registry.json', registry);
  const before = snapshot(f.root);
  assert.throws(() => syncGodot(f.root), /Stale managed file was modified/);
  assert.deepEqual(snapshot(f.root), before);
});

test('sync refuses unmanaged target collisions', t => {
  const f = fixture(t); f.write('godot/data/cards.json', 'unmanaged work');
  const before = snapshot(f.root);
  assert.throws(() => syncGodot(f.root), /overwrite unmanaged/);
  assert.deepEqual(snapshot(f.root), before);
});

test('unsafe old packs cannot delete outside managed directories', t => {
  const f = fixture(t); syncGodot(f.root);
  const pack = f.read('godot/resource-pack.json');
  pack.files[0].path = 'scenes/main.tscn'; f.json('godot/resource-pack.json', pack);
  assert.throws(() => syncGodot(f.root), /Not a managed resource path/);
  pack.files[0].path = 'data/../../outside.json'; f.json('godot/resource-pack.json', pack);
  assert.throws(() => syncGodot(f.root), /unsafe path/);
});

test('symlinked sources and destinations are rejected', t => {
  const f = fixture(t);
  const cards = path.join(f.root, 'content/data/cards.json');
  rmSync(cards); symlinkSync(path.join(ROOT, 'content/data/cards.json'), cards);
  assert.throws(() => syncGodot(f.root), /Symlink/);
  rmSync(cards); f.write('content/data/cards.json', readFileSync(path.join(ROOT, 'tests/fixtures/d0/content/data/cards.json')));
  symlinkSync(path.join(f.root, 'content/data'), path.join(f.root, 'godot/data'));
  assert.throws(() => syncGodot(f.root), /Symlink/);
});

test('every required font license is part of the managed plan', t => {
  const f = fixture(t), plan = buildPlan(f.root);
  assert.equal(plan.pack.files.filter(entry => entry.path.startsWith('resources/fonts/')).length, 5);
  rmSync(path.join(f.root, 'third_party/fonts/fusion-pixel-12px/LICENSES/galmuri/LICENSE.txt'));
  assert.throws(() => buildPlan(f.root), /Missing file/);
});

test('actual bundled font and all four licenses are unmodified authorized upstream bytes', () => {
  const directory = path.join(ROOT, 'third_party/fonts/fusion-pixel-12px');
  const font = readFileSync(path.join(directory, 'fusion-pixel-12px-proportional-zh_hans.otf.woff2'));
  assert.equal(font.length, 666264);
  assert.equal(font.subarray(0, 4).toString('ascii'), 'wOF2');
  assert.equal(sha256(font), '0ebd99e6f1e9b650a793a3f759c1c3dfa99f0c5b6502e78569b48ddb43767e40');
  const blobs = {
    'OFL.txt': '0427d1db87f97040016b5954b4892790878beeaa',
    'LICENSES/ark-pixel/OFL.txt': '264873a297a50e965af4875a4aa552fe594dd731',
    'LICENSES/cubic-11/OFL.txt': '4e863313ebd22ae0b44ea5f9538142b6b10e8f29',
    'LICENSES/galmuri/LICENSE.txt': 'ae34182f091c835710bef170e50059794377e3c4',
  };
  for (const [file, expectedBlob] of Object.entries(blobs)) {
    const bytes = readFileSync(path.join(directory, file));
    const blob = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
    assert.equal(blob, expectedBlob, `${file} must retain the complete original license`);
  }
});

test('Godot wrapper pins actual stable 4.7.2 and rejects wrong PATH versions', () => {
  assert.equal(assertGodotVersion('4.7.2.stable.official.ed1daf0bf\n'), '4.7.2.stable.official.ed1daf0bf');
  for (const version of ['4.6.stable.official', '4.7.1.stable.official', '4.7.20.stable', '4.7.2.dev.123', 'Godot 4.7.2', '']) assert.throws(() => assertGodotVersion(version), /4.7.2 is required/);
  const calls = [];
  assert.throws(() => verifyGodot('selected-wrong-godot', (...args) => { calls.push(args); return { status: 0, stdout: '4.6.stable.official', stderr: '' }; }), /no fallback/);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], 'selected-wrong-godot');
  assert.deepEqual(calls[0][1], ['--version']);
  assert.equal(selectGodot(ROOT, { GODOT_BIN: 'explicit-godot' }), 'explicit-godot');
  assert.throws(() => selectGodot(ROOT, { GODOT_BIN: '' }), /empty/);
});

test('Godot command routes are real test/sim/windowed shots with user args isolated', () => {
  assert.deepEqual(commandArguments('test', 'project'), ['--headless', '--path', 'project', '--script', 'res://tests/test_runner.gd']);
  assert.deepEqual(commandArguments('sim', 'project', ['--quick']), ['--headless', '--path', 'project', '--script', 'res://tests/sim_runner.gd', '--', '--quick']);
  assert.deepEqual(commandArguments('shots', 'project'), ['--path', 'project', '--', '--shots']);
  assert.throws(() => commandArguments('invented', 'project'), /Unknown/);
});

test('QA uses ignored local XDG storage rather than modifying the real player profile', t => {
  const f = fixture(t);
  const qa = commandEnvironment(f.root, 'test', { HOME: '/example-home', OTHER: 'kept' });
  const dev = commandEnvironment(f.root, 'dev', {});
  assert.equal(qa.HOME, path.join(f.root, '.local/godot-qa/home'));
  assert.equal(commandEnvironment(f.root, 'version', { HOME: '/unwritable-global-default' }).HOME, qa.HOME);
  assert.equal(commandEnvironment(f.root, 'dev', { HOME: '/player-home' }).HOME, '/player-home');
  assert.equal(qa.XDG_DATA_HOME, path.join(f.root, '.local/godot-qa/data'));
  assert.notEqual(dev.XDG_DATA_HOME, qa.XDG_DATA_HOME);
  assert.equal(qa.OTHER, 'kept');
  assert.equal(commandEnvironment(f.root, 'dev', { XDG_DATA_HOME: 'explicit-user-choice' }).XDG_DATA_HOME, 'explicit-user-choice');
  assert.equal(commandEnvironment(f.root, 'test', { XDG_DATA_HOME: '/unwritable-global-default' }).XDG_DATA_HOME, qa.XDG_DATA_HOME);
});

function testReport() {
  const suites = Object.fromEntries(['audio', 'foundation', 'battle', 'expedition', 'view'].map(name => [name, { passed: 10, failed: 0 }]));
  return { format: 'd1-tests/1', stage: 'd1-integrated', passed: 50, failed: 0, suites };
}

function simReport(count = 50) {
  const strategies = {};
  let battles = 0, turns = 0, nodes = 0;
  for (const name of ['random_rewards', 'biased_rewards']) {
    const trips = Math.floor(count / 2) + (name === 'random_rewards' ? count % 2 : 0);
    strategies[name] = { trips, battles: trips * 3, turns: trips * 12, nodes: trips * 7, retries: 0, boss_first_attempts: trips, boss_first_wins: trips, boss_first_attempt_win_rate: trips ? 1 : 0, estimated_seconds_per_trip: trips ? 201 : 0, average_battles_per_trip: trips ? 3 : 0 };
    for (const category of ['normal', 'elite', 'boss']) Object.assign(strategies[name], { [`${category}_attempts`]: trips, [`${category}_wins`]: trips, [`${category}_win_rate`]: trips ? 1 : 0 });
    battles += trips * 3; turns += trips * 12; nodes += trips * 7;
  }
  const samples = Math.max(1, Math.floor(count / 6));
  const probe = { samples, actual_battle_attempts: samples, actual_turns: samples * 10, baseline_win_rate: 1, cumulative_success_with_one_retry: 1, cumulative_success_with_two_retries: 1 };
  return {
    format: 'd1-simulation/1', stage: 'd1-expedition', full_simulation_implemented: true, completed: true, requested_trips: count, trips: count, errors: [], strategies,
    actual_battle_attempts: battles, turns, nodes, campaigns_completed: Math.floor(count / 2), boss_retries: 0,
    encounters: { 'enc.test': { attempts: battles, wins: battles, turns, hp_loss: count, win_rate: 1, average_turns: 4, average_hp_loss: 1 / 3 } },
    boss_retry_probe: { policies: { defensive: { ...probe }, random_legal: { ...probe } } },
    relics: {}, timing_note: 'Formula estimate, not observed human playtime.', relic_note: 'Observational, not causal.', elapsed_seconds: 1,
  };
}
const output = (prefix, report) => ({ status: 0, stdout: `${prefix}: ${JSON.stringify(report)}\n`, stderr: '' });

test('version probe receives the same isolated environment before any Godot launch', t => {
  const f = fixture(t), env = commandEnvironment(f.root, 'version', { HOME: '/real-player' });
  let options;
  verifyGodot('godot', (_binary, _args, value) => { options = value; return { status: 0, stdout: '4.7.2.stable.official', stderr: '' }; }, env);
  assert.equal(options.env, env);
  assert.equal(options.env.HOME, path.join(f.root, '.local/godot-qa/home'));
  assert.throws(() => verifyGodot('godot', () => ({ status: 0, stdout: '4.7.2.stable.official', stderr: 'ERROR: broken startup' }), env), /despite exit 0/);
});

test('simulation count matches the requested preset and rejects malformed inputs', () => {
  assert.equal(simulationCount(), 300);
  assert.equal(simulationCount(['--quick']), 50);
  assert.equal(simulationCount(['--count=7']), 7);
  assert.equal(simulationCount(['--quick', '--count=3']), 3);
  assert.equal(simulationCount(['--count=3', '--quick']), 50);
  for (const arg of ['--count=0', '--count=-1', '--count=abc', '--count=1.5', '--count=9007199254740992', '--invented']) assert.throws(() => simulationCount([arg]), /invalid|safe integer/);
});

test('wrapper rejects zero-exit engine/script/assertion errors, even indented or ANSI-colored', () => {
  for (const error of ['ERROR: broken import', '  SCRIPT ERROR: bad call', '\u001b[31mERROR: bad font\u001b[0m', 'USER ERROR: bad resource', 'FATAL: stopped', 'FAIL suite: missing effect']) {
    assert.throws(() => validateOutput('import', { status: 0, stdout: '', stderr: error }), /despite exit 0/);
    assert.throws(() => validateOutput('test', { ...output('D1_TEST_RESULT', testReport()), stderr: error }), /despite exit 0/);
  }
  assert.throws(() => validateOutput('test', { status: 1, stdout: '', stderr: '' }), /exited 1/);
  assert.throws(() => validateOutput('test', { status: null, signal: 'SIGTERM', stdout: '' }), /SIGTERM/);
  assert.throws(() => validateOutput('test', { error: new Error('spawn failed') }), /spawn failed/);
});

test('wrapper rejects zero-exit ObjectDB and RID shutdown leaks without rejecting ordinary warnings', () => {
  for (const warning of [
    'WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).',
    '  WARNING: ObjectDB instances leaked at exit.',
    'WARNING: 2 resources still in use at exit.',
    'WARNING: 3 RIDs of type CanvasItem were leaked.',
    'Leaked instance: AudioStreamPlaybackWAV:123',
    'WARNING: 2 unclaimed string names at exit.',
  ]) assert.throws(() => validateOutput('test', { ...output('D1_TEST_RESULT', testReport()), stderr: warning }), /leaked live engine resources/);
  validateOutput('import', { status: 0, stdout: '', stderr: 'WARNING: benign tool notice' });
});

test('wrapper requires exactly one valid D1 test report with all completed suites and matching counts', () => {
  validateOutput('test', output('D1_TEST_RESULT', testReport()));
  for (const mutate of [
    r => { r.format = 'd0-tests/1'; }, r => { r.stage = 'foundation'; }, r => { r.failed = 1; }, r => { r.passed = 0; }, r => { r.passed = '40'; },
    r => { delete r.suites.audio; }, r => { delete r.suites.battle; }, r => { r.suites.extra = { passed: 1, failed: 0 }; }, r => { r.suites.view.passed = 0; }, r => { r.suites.expedition.failed = 1; },
    r => { r.suites.foundation.passed = 1.5; }, r => { r.suites.battle = null; }, r => { r.passed += 1; },
  ]) { const report = testReport(); mutate(report); assert.throws(() => validateOutput('test', output('D1_TEST_RESULT', report))); }
  assert.throws(() => validateOutput('test', output('D0_TEST_RESULT', { passed: 45, failed: 0 })), /no completion report/);
  assert.throws(() => validateOutput('test', { status: 0, stdout: 'D1_TEST_RESULT: {bad', stderr: '' }), /invalid JSON/);
  assert.throws(() => validateOutput('test', output('D1_TEST_RESULT', null)), /object/);
  const duplicated = output('D1_TEST_RESULT', testReport()); duplicated.stdout += duplicated.stdout;
  assert.throws(() => validateOutput('test', duplicated), /multiple completion reports/);
});

test('wrapper validates actual D1 simulation completion, requested trips and gameplay totals', () => {
  validateOutput('sim', output('D1_SIM_RESULT', simReport()), ['--quick']);
  validateOutput('sim', output('D1_SIM_RESULT', simReport(300)));
  validateOutput('sim', output('D1_SIM_RESULT', simReport(1)), ['--count=1']);
  for (const mutate of [
    r => { r.stage = 'foundation-smoke'; }, r => { r.full_simulation_implemented = false; }, r => { r.completed = false; }, r => { r.errors.push('failed battle'); },
    r => { delete r.errors; }, r => { r.trips -= 1; }, r => { r.requested_trips = 300; }, r => { r.trips = '50'; }, r => { delete r.strategies.biased_rewards; },
    r => { r.strategies.random_rewards.trips = 0; }, r => { r.strategies.random_rewards.battles = 0; }, r => { r.strategies.random_rewards.boss_wins = 100; },
    r => { r.strategies.random_rewards.boss_win_rate = 2; }, r => { r.strategies.random_rewards.estimated_seconds_per_trip = null; }, r => { r.actual_battle_attempts += 1; },
    r => { r.turns += 1; }, r => { r.nodes += 1; }, r => { r.encounters = {}; }, r => { r.encounters['enc.test'].attempts -= 1; }, r => { delete r.boss_retry_probe; },
    r => { r.boss_retry_probe.policies.random_legal.samples = 0; }, r => { r.timing_note = ''; }, r => { r.relic_note = ''; }, r => { r.elapsed_seconds = -1; },
  ]) { const report = simReport(); mutate(report); assert.throws(() => validateOutput('sim', output('D1_SIM_RESULT', report), ['--quick'])); }
  assert.throws(() => validateOutput('sim', { status: 0, stdout: '{"stage":"foundation-smoke","cases":4,"passed":4}', stderr: '' }), /no completion report/);
  assert.throws(() => validateOutput('sim', output('D1_SIM_RESULT', simReport())), /every requested expedition/);
  const duplicated = output('D1_SIM_RESULT', simReport()); duplicated.stdout += duplicated.stdout;
  assert.throws(() => validateOutput('sim', duplicated, ['--quick']), /multiple completion reports/);
});
