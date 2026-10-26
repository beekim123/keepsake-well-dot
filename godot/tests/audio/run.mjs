#!/usr/bin/env node
// Separate processes are essential: a SceneTree assertion cannot observe the
// ObjectDB leak diagnostics emitted only after Godot begins shutting down.
import assert from 'node:assert/strict';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { selectGodot, verifyGodot } from '../../../tools/godot/cli.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const local = path.join(root, '.local');
mkdirSync(local, { recursive: true });
const work = mkdtempSync(path.join(local, 'audio-shutdown-'));
const project = path.join(work, 'project');
const env = { ...process.env };
for (const [key, dir] of [['HOME', 'home'], ['XDG_DATA_HOME', 'data'], ['XDG_CONFIG_HOME', 'config'], ['XDG_CACHE_HOME', 'cache']]) {
  env[key] = path.join(work, dir);
  mkdirSync(env[key], { recursive: true });
}

function run(binary, name, args) {
  const result = spawnSync(binary, args, { env, encoding: 'utf8', timeout: 60_000, maxBuffer: 8 * 1024 * 1024, shell: false });
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`.replace(/\u001b\[[0-9;]*m/g, '');
  writeFileSync(path.join(work, `${name}.log`), output);
  process.stdout.write(output);
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${name} exited ${result.status ?? result.signal}`);
  assert.doesNotMatch(output, /^\s*(?:SCRIPT ERROR:|USER ERROR:|ERROR:|FATAL:|FAIL(?:\s|$))/m, `${name} logged an engine/script/test error`);
  assert.doesNotMatch(output, /(?:ObjectDB instances .*leaked|Leaked instance:|resources? still in use at exit|RID.*leaked|unclaimed string names at exit)/i, `${name} leaked engine objects/resources`);
  return output;
}

try {
  const binary = selectGodot(root, env);
  const version = verifyGodot(binary, spawnSync, env);
  mkdirSync(path.join(project, 'scripts', 'services'), { recursive: true });
  mkdirSync(path.join(project, 'tests', 'audio'), { recursive: true });
  cpSync(path.join(root, 'godot', 'scripts', 'services', 'audio_service.gd'), path.join(project, 'scripts', 'services', 'audio_service.gd'));
  for (const file of ['audio_suite.gd', 'audio_runner.gd']) cpSync(path.join(root, 'godot', 'tests', 'audio', file), path.join(project, 'tests', 'audio', file));
  cpSync(path.join(root, 'godot', 'resources', 'audio'), path.join(project, 'resources', 'audio'), { recursive: true });
  // Keep the real project's WAV importer policy without bringing unrelated
  // gameplay/autoloads or import caches into this narrow shutdown regression.
  const sourceProject = readFileSync(path.join(root, 'godot', 'project.godot'), 'utf8');
  const importerDefaults = sourceProject.match(/^\[importer_defaults\]\r?\n[\s\S]*?(?=^\[|$(?![\s\S]))/m)?.[0] ?? '';
  writeFileSync(path.join(project, 'project.godot'), `config_version=5\n[application]\nconfig/name="Keepsake Audio Shutdown Tests"\n[autoload]\nAudioService="*res://scripts/services/audio_service.gd"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n${importerDefaults}`);
  run(binary, 'import', ['--headless', '--path', project, '--editor', '--import', '--quit']);
  const reports = [];
  for (const scenario of ['immediate', 'stopped']) {
    const args = ['--headless', '--audio-driver', 'Dummy', '--verbose', '--path', project, '--script', 'res://tests/audio/audio_runner.gd'];
    if (scenario === 'stopped') args.push('--', '--stop-before-exit');
    const output = run(binary, scenario, args);
    const lines = output.split(/\r?\n/).filter(line => line.startsWith('AUDIO_TEST_RESULT: '));
    assert.equal(lines.length, 1, `${scenario} must emit exactly one completion report`);
    const report = JSON.parse(lines[0].slice('AUDIO_TEST_RESULT: '.length));
    assert.equal(report.format, 'audio-shutdown-tests/1');
    assert.equal(report.case, scenario);
    assert.equal(report.audio_driver, 'Dummy');
    assert.equal(report.physical_playback_enabled, false);
    assert.equal(report.loaded_streams, 3);
    assert.equal(report.listening_verified, false);
    assert.equal(report.failed, 0);
    assert(Number.isSafeInteger(report.passed) && report.passed > 0, 'audio suite must execute assertions');
    reports.push(report);
  }
  console.log(`AUDIO_SHUTDOWN_RESULT: ${JSON.stringify({ format: 'audio-shutdown-processes/1', godot: version, completed: true, reports, scope: 'actual Dummy backend, semantic cue loading and clean process shutdown; not audible listening' })}`);
  console.log(`Audio shutdown logs: ${path.relative(root, work)}`);
} catch (error) {
  console.error(`Audio shutdown regression FAIL: ${error.message}\nLogs: ${path.relative(root, work)}`);
  process.exitCode = 1;
}
