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

export function verifyGodot(binary, spawn = spawnSync) {
  const result = spawn(binary, ['--version'], { encoding: 'utf8', timeout: 15_000, shell: false });
  assert(!result.error, `Cannot run selected Godot: ${result.error?.message}; install Godot ${REQUIRED_VERSION} and set GODOT_BIN.`);
  assert(result.status === 0, `Selected Godot --version exited ${result.status}: ${result.stderr ?? ''}`);
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
// inside the workspace on sandboxed Linux, even when XDG is inherited globally.
// Interactive dev honors the user's explicit XDG choices.
export function commandEnvironment(root, command, env = process.env) {
  const result = { ...env };
  const local = path.join(root, '.local', command === 'dev' ? 'godot-dev' : 'godot-qa');
  for (const [key, folder] of [['XDG_DATA_HOME', 'data'], ['XDG_CONFIG_HOME', 'config'], ['XDG_CACHE_HOME', 'cache']]) {
    if (command !== 'dev' || !result[key]) result[key] = path.join(local, folder);
  }
  return result;
}

export function validateOutput(mode, result) {
  assert(!result.error, `Godot ${mode} failed: ${result.error?.message}`);
  assert(result.status === 0, `Godot ${mode} exited ${result.status ?? result.signal}`);
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`.replace(/\u001b\[[0-9;]*m/g, '');
  // Godot can return zero after script/import errors; those are not a pass.
  assert(!/^(?:SCRIPT ERROR:|ERROR:)/m.test(output), `Godot ${mode} logged an engine/script error despite exit 0`);
  if (mode === 'test') {
    const report = output.match(/^D0_TEST_RESULT: (.+)$/m);
    assert(report, 'Godot test produced no completion report');
    const summary = JSON.parse(report[1]);
    assert(summary.failed === 0 && summary.passed > 0, 'Godot test completion report contains failures or no tests');
  }
  if (mode === 'sim') {
    const line = output.split('\n').find(value => value.startsWith('{'));
    assert(line, 'Godot sim produced no completion report');
    const summary = JSON.parse(line);
    assert(summary.stage === 'foundation-smoke' && summary.full_simulation_implemented === false && summary.cases > 0 && summary.passed === summary.cases, 'D0 sim smoke report is missing, failed, or claims unimplemented full simulation');
  }
}

export function main(args = process.argv.slice(2)) {
  const [command = 'dev', ...extra] = args;
  assert(['dev', 'import', 'test', 'sim', 'shots', 'version'].includes(command), `Unknown Godot command: ${command}`);
  const binary = selectGodot();
  const version = verifyGodot(binary);
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
    validateOutput(mode, result);
  }
  // A fresh checkout must import before scripts load textures and font files.
  if (command !== 'import') run('import');
  if (command === 'sim') console.log('D0 sim is a foundation smoke check only; full expedition win rates and timing are deferred to D1.');
  run(command, extra);
}

if (isMain(import.meta.url)) {
  try { main(); }
  catch (error) { console.error(`godot CLI FAIL — ${error.message}`); process.exitCode = 1; }
}
