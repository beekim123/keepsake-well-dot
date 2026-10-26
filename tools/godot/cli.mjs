import { existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { ROOT, assert, isMain } from '../lib/paths.mjs';

export const REQUIRED_VERSION = '4.7.2';

export function assertGodotVersion(output) {
  const value = output.trim();
  assert(/^4\.7\.2(?:\.stable(?:\.[A-Za-z0-9_.-]+)?)?$/.test(value), `Godot ${REQUIRED_VERSION} is required; selected executable reports ${JSON.stringify(value)}. Set GODOT_BIN to the correct executable; no fallback was attempted.`);
  return value;
}

export function selectGodot(root = ROOT, env = process.env) {
  if (Object.hasOwn(env, 'GODOT_BIN')) {
    assert(typeof env.GODOT_BIN === 'string' && env.GODOT_BIN.trim().length > 0, 'GODOT_BIN is empty; set it to Godot 4.7.2 or unset it.');
    return env.GODOT_BIN;
  }
  const local = path.join(root, 'Godot.app', 'Contents', 'MacOS', 'Godot');
  return existsSync(local) ? local : 'godot';
}

export function verifyGodot(binary, spawn = spawnSync, env = process.env) {
  const result = spawn(binary, ['--version'], { encoding: 'utf8', timeout: 15_000, shell: false, env });
  assert(!result.error, `Cannot run selected Godot: ${result.error?.message}; install Godot ${REQUIRED_VERSION} and set GODOT_BIN.`);
  assert(result.status === 0, `Selected Godot --version exited ${result.status}: ${result.stderr ?? ''}`);
  validateOutput('version', result);
  return assertGodotVersion(result.stdout);
}

export function commandArguments(command, project, extra = []) {
  const common = ['--path', project];
  if (command === 'import') return ['--headless', ...common, '--editor', '--import', '--quit'];
  if (command === 'test') return ['--headless', ...common, '--script', 'res://tests/test_runner.gd', ...extra.length ? ['--', ...extra] : []];
  if (command === 'sim') return ['--headless', ...common, '--script', 'res://tests/sim_runner.gd', ...extra.length ? ['--', ...extra] : []];
  if (command === 'shots') return [...common, '--', '--shots', ...extra];
  if (command === 'dev') return [...common, ...extra.length ? ['--', ...extra] : []];
  throw new Error(`Unknown Godot command ${command}; use dev, import, test, sim, shots, version`);
}

// Keep command-line QA saves/editor caches out of the user's real profile and
// inside the workspace on sandboxed Linux, even when HOME/XDG are inherited globally.
// Interactive dev honors the user's explicit XDG choices.
export function commandEnvironment(root, command, env = process.env) {
  const result = { ...env };
  const local = path.join(root, '.local', command === 'dev' ? 'godot-dev' : 'godot-qa');
  if (command !== 'dev') result.HOME = path.join(local, 'home');
  for (const [key, folder] of [['XDG_DATA_HOME', 'data'], ['XDG_CONFIG_HOME', 'config'], ['XDG_CACHE_HOME', 'cache']]) {
    if (command !== 'dev' || !result[key]) result[key] = path.join(local, folder);
  }
  return result;
}

const isRecord = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const isCount = value => Number.isSafeInteger(value) && value >= 0;
const isRate = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1;

function completionReport(output, prefix, mode) {
  const lines = output.split(/\r?\n/).filter(line => line.startsWith(`${prefix}: `));
  assert(lines.length === 1, `Godot ${mode} produced ${lines.length === 0 ? 'no' : 'multiple'} completion report${lines.length > 1 ? 's' : ''}`);
  let summary;
  try { summary = JSON.parse(lines[0].slice(prefix.length + 2)); }
  catch { throw new Error(`Godot ${mode} completion report is invalid JSON`); }
  assert(isRecord(summary), `Godot ${mode} completion report must be an object`);
  return summary;
}

export function simulationCount(extra = []) {
  let count = 300;
  for (const arg of extra) {
    if (arg === '--quick') count = 50;
    else if (/^--count=[1-9][0-9]*$/.test(arg)) count = Number(arg.slice('--count='.length));
    else throw new Error(`Unknown or invalid simulation argument: ${arg}`);
    assert(Number.isSafeInteger(count), 'Simulation count must be a positive safe integer');
  }
  return count;
}

export function validateOutput(mode, result, extra = []) {
  assert(!result.error, `Godot ${mode} failed: ${result.error?.message}`);
  assert(result.status === 0, `Godot ${mode} exited ${result.status ?? result.signal}`);
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`.replace(/\u001b\[[0-9;]*m/g, '');
  // Godot can return zero after script/import errors or failed custom assertions.
  assert(!/^\s*(?:SCRIPT ERROR:|USER ERROR:|ERROR:|FATAL:|FAIL(?:\s|$))/m.test(output), `Godot ${mode} logged an engine/script/test error despite exit 0`);
  assert(!/(?:ObjectDB instances .*leaked|Leaked instance:|resources? still in use at exit|RID.*leaked|unclaimed string names at exit)/i.test(output), `Godot ${mode} logged leaked live engine resources despite exit 0`);
  if (mode === 'test') {
    const summary = completionReport(output, 'D1_TEST_RESULT', mode);
    const names = ['audio', 'battle', 'expedition', 'foundation', 'view'];
    assert(summary.format === 'd1-tests/1' && summary.stage === 'd1-integrated', 'Godot test report is not the integrated D1 contract');
    assert(isCount(summary.passed) && summary.passed > 0 && summary.failed === 0, 'Godot test completion report contains failures or no tests');
    assert(isRecord(summary.suites) && Object.keys(summary.suites).sort().join(',') === names.join(','), 'Godot test must complete audio, foundation, battle, expedition and view suites');
    let passed = 0;
    for (const name of names) {
      const suite = summary.suites[name];
      assert(isRecord(suite) && isCount(suite.passed) && suite.passed > 0 && suite.failed === 0, `Godot ${name} suite contains failures or no tests`);
      passed += suite.passed;
    }
    assert(summary.passed === passed, 'Godot test aggregate assertion total does not match completed suites');
  }
  if (mode === 'sim') {
    const summary = completionReport(output, 'D1_SIM_RESULT', mode);
    const count = simulationCount(extra);
    assert(summary.format === 'd1-simulation/1' && summary.stage === 'd1-expedition' && summary.full_simulation_implemented === true, 'Godot sim is not the actual D1 expedition simulation');
    assert(summary.completed === true && Array.isArray(summary.errors) && summary.errors.length === 0 && summary.requested_trips === count && summary.trips === count, 'Godot sim did not complete every requested expedition without errors');
    const names = ['biased_rewards', 'random_rewards'];
    assert(isRecord(summary.strategies) && Object.keys(summary.strategies).sort().join(',') === names.join(','), 'Godot sim must report both reward strategies');
    let battles = 0, turns = 0, nodes = 0;
    for (const name of names) {
      const data = summary.strategies[name];
      const expected = Math.floor(count / 2) + (name === 'random_rewards' ? count % 2 : 0);
      assert(isRecord(data) && data.trips === expected, `Godot sim ${name} trip count is incomplete`);
      for (const field of ['battles', 'turns', 'nodes', 'retries', 'boss_first_attempts', 'boss_first_wins']) assert(isCount(data[field]), `Godot sim ${name}.${field} is missing or invalid`);
      let attempts = 0;
      for (const category of ['normal', 'elite', 'boss']) {
        assert(isCount(data[`${category}_attempts`]) && isCount(data[`${category}_wins`]) && data[`${category}_wins`] <= data[`${category}_attempts`] && isRate(data[`${category}_win_rate`]), `Godot sim ${name}.${category} combat statistics are invalid`);
        attempts += data[`${category}_attempts`];
      }
      assert(data.battles === attempts && data.boss_first_wins <= data.boss_first_attempts && data.boss_first_attempts <= data.boss_attempts && isRate(data.boss_first_attempt_win_rate), `Godot sim ${name} combat totals disagree`);
      assert(Number.isFinite(data.estimated_seconds_per_trip) && data.estimated_seconds_per_trip >= 0 && Number.isFinite(data.average_battles_per_trip) && data.average_battles_per_trip >= 0, `Godot sim ${name} estimates are missing or invalid`);
      assert(expected === 0 || (data.battles > 0 && data.nodes > 0 && data.turns > 0), `Godot sim ${name} contains no actual gameplay`);
      battles += data.battles; turns += data.turns; nodes += data.nodes;
    }
    assert(battles > 0 && summary.actual_battle_attempts === battles && summary.turns === turns && summary.nodes === nodes, 'Godot sim aggregate combat totals disagree');
    assert(isCount(summary.campaigns_completed) && summary.campaigns_completed <= count && isCount(summary.boss_retries), 'Godot sim campaign/retry counts are invalid');
    assert(isRecord(summary.encounters) && Object.keys(summary.encounters).length > 0, 'Godot sim lacks actual encounter results');
    let encounterAttempts = 0;
    for (const [id, data] of Object.entries(summary.encounters)) {
      assert(isRecord(data) && isCount(data.attempts) && data.attempts > 0 && isCount(data.wins) && data.wins <= data.attempts && isCount(data.turns) && isCount(data.hp_loss) && isRate(data.win_rate) && Number.isFinite(data.average_turns) && Number.isFinite(data.average_hp_loss), `Godot sim encounter ${id} statistics are invalid`);
      encounterAttempts += data.attempts;
    }
    assert(encounterAttempts === battles, 'Godot sim encounter totals disagree with actual battles');
    assert(isRecord(summary.boss_retry_probe) && isRecord(summary.boss_retry_probe.policies), 'Godot sim lacks its actual boss retry probe');
    for (const policy of ['defensive', 'random_legal']) {
      const data = summary.boss_retry_probe.policies[policy];
      assert(isRecord(data) && data.samples === Math.max(1, Math.floor(count / 6)) && isCount(data.actual_battle_attempts) && data.actual_battle_attempts >= data.samples && isCount(data.actual_turns) && data.actual_turns > 0 && isRate(data.baseline_win_rate) && isRate(data.cumulative_success_with_one_retry) && isRate(data.cumulative_success_with_two_retries), `Godot sim ${policy} retry probe is incomplete`);
    }
    assert(typeof summary.timing_note === 'string' && summary.timing_note.length > 0 && typeof summary.relic_note === 'string' && summary.relic_note.length > 0 && isRecord(summary.relics) && Number.isFinite(summary.elapsed_seconds) && summary.elapsed_seconds >= 0, 'Godot sim lacks estimate/association limitations or elapsed time');
  }
}

export function main(args = process.argv.slice(2)) {
  const [command = 'dev', ...extra] = args;
  assert(['dev', 'import', 'test', 'sim', 'shots', 'version'].includes(command), `Unknown Godot command: ${command}`);
  const binary = selectGodot();
  const versionEnv = commandEnvironment(ROOT, 'version');
  for (const key of ['HOME', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) mkdirSync(versionEnv[key], { recursive: true });
  const version = verifyGodot(binary, spawnSync, versionEnv);
  console.log(`Godot ${version} verified (required ${REQUIRED_VERSION}).`);
  if (command === 'version') return;
  const project = path.join(ROOT, 'godot');
  assert(existsSync(path.join(project, 'project.godot')), 'Missing godot/project.godot');
  const env = commandEnvironment(ROOT, command);
  for (const key of ['XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME']) mkdirSync(env[key], { recursive: true });
  function run(mode, more = []) {
    const interactive = mode === 'dev';
    const result = spawnSync(binary, commandArguments(mode, project, more), { stdio: interactive ? 'inherit' : 'pipe', encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, shell: false, env });
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    validateOutput(mode, result, more);
  }
  // A fresh checkout must import before scripts load textures and font files.
  if (command === 'sim') simulationCount(extra);
  if (command !== 'import') run('import');
  if (command === 'sim') console.log('D1 sim plays actual seven-node expeditions; duration is formula-estimated, not human playtime.');
  run(command, extra);
}

if (isMain(import.meta.url)) {
  try { main(); }
  catch (error) { console.error(`godot CLI FAIL — ${error.message}`); process.exitCode = 1; }
}
