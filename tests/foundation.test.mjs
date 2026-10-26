import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, readdirSync, statSync, symlinkSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { ROOT, relativePath, safePath, sha256, jsonBytes } from '../tools/lib/paths.mjs';
import { checkContent } from '../tools/qa/content-check.mjs';
import { buildPlan, syncGodot } from '../tools/resources/sync-godot.mjs';
import { assertGodotVersion, selectGodot, verifyGodot, commandArguments, commandEnvironment, validateOutput } from '../tools/godot/cli.mjs';

function fixture(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'keepsake-foundation-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const write = (file, bytes) => { mkdirSync(path.dirname(path.join(root, file)), { recursive: true }); writeFileSync(path.join(root, file), bytes); };
  const json = (file, value) => write(file, jsonBytes(value));
  const read = file => JSON.parse(readFileSync(path.join(root, file), 'utf8'));
  for (const file of ['registry.json', 'data/cards.json', 'data/ui.json']) write(`content/${file}`, readFileSync(path.join(ROOT, 'content', file)));
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
  rmSync(cards); f.write('content/data/cards.json', readFileSync(path.join(ROOT, 'content/data/cards.json')));
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
  assert.equal(qa.XDG_DATA_HOME, path.join(f.root, '.local/godot-qa/data'));
  assert.notEqual(dev.XDG_DATA_HOME, qa.XDG_DATA_HOME);
  assert.equal(qa.OTHER, 'kept');
  assert.equal(commandEnvironment(f.root, 'dev', { XDG_DATA_HOME: 'explicit-user-choice' }).XDG_DATA_HOME, 'explicit-user-choice');
  assert.equal(commandEnvironment(f.root, 'test', { XDG_DATA_HOME: '/unwritable-global-default' }).XDG_DATA_HOME, qa.XDG_DATA_HOME);
});

test('wrapper rejects zero-exit engine errors and absent or failing completion reports', () => {
  const result = { status: 0, stdout: '', stderr: '' };
  assert.throws(() => validateOutput('import', { ...result, stderr: 'ERROR: broken import' }), /despite exit 0/);
  assert.throws(() => validateOutput('test', result), /no completion report/);
  assert.throws(() => validateOutput('test', { ...result, stdout: 'D0_TEST_RESULT: {"failed":1,"passed":4}' }), /contains failures/);
  validateOutput('test', { ...result, stdout: 'D0_TEST_RESULT: {"failed":0,"passed":45}' });
  validateOutput('sim', { ...result, stdout: '{"stage":"foundation-smoke","full_simulation_implemented":false,"cases":4,"passed":4}' });
  assert.throws(() => validateOutput('sim', { ...result, stdout: '{"stage":"full-game","full_simulation_implemented":true,"cases":300,"passed":300}' }), /claims unimplemented/);
});
