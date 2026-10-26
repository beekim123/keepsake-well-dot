import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { cueIds, cueSpec, renderCue } from '../resources/audio/synth.ts';
import { analyzeSamples, buildAudioPack, checkAudioPack, decodePcm16Wav, encodePcm16Wav, validateMetrics } from '../tools/resources/audio-pack.ts';

const cli = fileURLToPath(new URL('../tools/resources/audio-pack.ts', import.meta.url));

async function withPack(run) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'keepsake-audio-'));
  try { await run(directory, await buildAudioPack(directory)); }
  finally { await rm(directory, { recursive: true, force: true }); }
}

async function snapshot(directory) {
  return Promise.all((await readdir(directory)).sort().map(async file => [file, await readFile(path.join(directory, file))]));
}

test('D0 catalog contains exactly the three agreed cues', () => {
  assert.deepEqual(cueIds, ['music.title', 'sfx.ui_click', 'sfx.card_play_attack']);
  assert.equal(cueSpec('music.title').duration, 8);
  assert.equal(cueSpec('music.title').sampleRate, 22050);
  assert.equal(cueSpec('sfx.ui_click').sampleRate, 44100);
  assert.equal(cueSpec('sfx.card_play_attack').sampleRate, 44100);
});

for (const id of cueIds) {
  test(`${id}: deterministic independent Float32 samples, finite levels and PCM metrics`, () => {
    const spec = cueSpec(id);
    const a = renderCue(id, spec.sampleRate);
    // Render another cue between calls to detect accidentally shared PRNG/oscillator state.
    renderCue('sfx.card_play_attack', 22050);
    const b = renderCue(id, spec.sampleRate);
    assert(a instanceof Float32Array);
    assert.notEqual(a, b);
    assert.equal(a.length, Math.round(spec.duration * spec.sampleRate));
    assert.deepEqual(a, b);
    assert(Object.is(a[0], 0));
    assert(Object.is(a.at(-1), 0));
    const encoded = encodePcm16Wav(a, spec.sampleRate);
    assert(encoded.length < 2_000_000);
    const decoded = decodePcm16Wav(encoded);
    assert.equal(decoded.sampleRate, spec.sampleRate);
    assert.equal(decoded.samples.length, a.length);
    validateMetrics(id, analyzeSamples(a, spec.sampleRate), spec.loop);
    validateMetrics(id, analyzeSamples(decoded.samples, spec.sampleRate), spec.loop);
    a[12] = 0.9;
    assert.deepEqual(renderCue(id, spec.sampleRate), b, 'caller mutation must not alter the next render');
  });
}

test('invalid cue ids and sample rates fail explicitly', () => {
  for (const id of ['', 'music.missing', 'music.title.wav', '__proto__', 'toString', '../music.title']) {
    assert.throws(() => renderCue(id, 22050), /Unknown audio cue/);
    assert.throws(() => cueSpec(id), /Unknown audio cue/);
  }
  for (const rate of [0, -1, 7999, 96001, 22050.5, Infinity, NaN, '22050', undefined]) {
    assert.throws(() => renderCue('music.title', rate), /sampleRate must be/);
  }
});

test('renderer supports non-export sample rates without changing duration or deterministic output', () => {
  for (const sampleRate of [8000, 48000, 96000]) {
    const a = renderCue('sfx.ui_click', sampleRate);
    assert.equal(a.length, Math.round(0.1 * sampleRate));
    assert.deepEqual(a, renderCue('sfx.ui_click', sampleRate));
    assert(a.every(Number.isFinite));
  }
});

test('PCM16 encoding is canonical little-endian mono and reports decoded levels', () => {
  const input = new Float32Array([0, 0.5, -0.5, 1, -1, 0]);
  const wav = encodePcm16Wav(input, 44100);
  assert.equal(wav.toString('ascii', 0, 4), 'RIFF');
  assert.equal(wav.readUInt16LE(22), 1);
  assert.equal(wav.readUInt16LE(34), 16);
  const { samples, sampleRate } = decodePcm16Wav(wav);
  assert.equal(sampleRate, 44100);
  assert.deepEqual([...samples], [0, 0.5, -16383 / 32768, 32767 / 32768, -32767 / 32768, 0]);
  assert.equal(wav.length, 44 + input.length * 2);
});

test('WAV decoder rejects malformed headers, truncation, trailers and unsupported formats', () => {
  const wav = encodePcm16Wav(renderCue('sfx.ui_click', 44100), 44100);
  for (const offset of [0, 4, 8, 12, 16, 20, 22, 28, 32, 34, 36, 40]) {
    const broken = Buffer.from(wav);
    broken[offset] ^= 0xff;
    assert.throws(() => decodePcm16Wav(broken), /Invalid/);
  }
  assert.throws(() => decodePcm16Wav(wav.subarray(0, wav.length - 2)), /Invalid/);
  assert.throws(() => decodePcm16Wav(Buffer.concat([wav, Buffer.from([0, 0])])), /Invalid/);
});

test('invalid/clipped/silent sources and files at 2 MB are rejected rather than normalized', () => {
  for (const sample of [NaN, Infinity, -Infinity, 1.001, -1.001]) {
    const samples = new Float32Array([0, sample, 0]);
    assert.throws(() => encodePcm16Wav(samples, 22050), /Invalid or clipped/);
    assert.throws(() => analyzeSamples(samples, 22050), /Invalid or clipped/);
  }
  assert.throws(() => analyzeSamples(new Float32Array(32), 22050), /silent/);
  assert.throws(() => encodePcm16Wav(new Float32Array(999978), 22050), /smaller than 2 MB/);
});

test('active RMS trims only outside silence and preserves internal rests in the measurement', () => {
  const samples = new Float32Array(1000);
  samples.fill(0.2, 200, 400);
  samples.fill(0.2, 600, 800);
  const metrics = analyzeSamples(samples, 22050);
  assert.equal(metrics.activeFrames, 600);
  assert(Math.abs(metrics.activeRmsDbfs - 20 * Math.log10(Math.sqrt(0.04 * 400 / 600))) < 1e-6);
});

test('peak, quiet/loud cues and each music seam condition fail the numerical gate', () => {
  const good = analyzeSamples(renderCue('music.title', 22050), 22050);
  const bad = [
    { peakDbfs: -0.5 }, { rmsDbfs: -22.1 }, { rmsDbfs: -17.9 }, { first: 0.0001 }, { last: 0.0001 },
    { seam: { ...good.seam, amplitude: 0.0101 } },
    { seam: { ...good.seam, slope: 0.0011 } },
    { seam: { ...good.seam, slopeMismatch: 0.0011 } },
  ];
  for (const change of bad) assert.throws(() => validateMetrics('music.title', { ...good, ...change }, true));
  for (const level of [-21.1, -14.9]) assert.throws(() => validateMetrics('sfx.ui_click', { ...good, activeRmsDbfs: level }, false), /RMS/);
});

test('two complete builds have identical samples, hashes, manifests and WAV bytes', async () => {
  await withPack(async (directory, first) => {
    const before = await snapshot(directory);
    assert.deepEqual(await buildAudioPack(directory), first);
    assert.deepEqual(await snapshot(directory), before);
    assert.equal(first.format, 'audio-manifest/1');
    for (const asset of first.assets) {
      assert.match(asset.hash, /^[0-9a-f]{64}$/);
      assert.match(asset.sampleHash, /^[0-9a-f]{64}$/);
      assert.equal(asset.channels, 1);
    }
  });
});

test('successful check is read-only', async () => {
  await withPack(async (directory, manifest) => {
    const before = await snapshot(directory);
    assert.deepEqual(await checkAudioPack(directory), manifest);
    assert.deepEqual(await snapshot(directory), before);
  });
});

test('WAV sample tampering fails check without repairing the file', async () => {
  await withPack(async (directory, manifest) => {
    const file = path.join(directory, manifest.assets[0].file);
    const damaged = await readFile(file);
    damaged[5044] ^= 1;
    await writeFile(file, damaged);
    const before = await snapshot(directory);
    await assert.rejects(checkAudioPack(directory), /hash\/bytes differ/);
    assert.deepEqual(await snapshot(directory), before);
  });
});

test('manifest metric, cue, hash and path tampering is rejected without following arbitrary paths', async () => {
  await withPack(async (directory, manifest) => {
    for (const change of [{ id: 'music.fake' }, { file: '../outside.wav' }, { hash: '0'.repeat(64) }, { metrics: {} }]) {
      const tampered = structuredClone(manifest);
      Object.assign(tampered.assets[0], change);
      const text = JSON.stringify(tampered, null, 2) + '\n';
      await writeFile(path.join(directory, 'manifest.json'), text);
      await assert.rejects(checkAudioPack(directory), /manifest differs/);
      assert.equal(await readFile(path.join(directory, 'manifest.json'), 'utf8'), text);
    }
  });
});

test('missing and unregistered WAV exports fail verification', async () => {
  await withPack(async (directory, manifest) => {
    const extra = path.join(directory, 'unregistered.wav');
    await writeFile(extra, await readFile(path.join(directory, manifest.assets[0].file)));
    await assert.rejects(checkAudioPack(directory), /Unregistered WAV/);
    await rm(extra);
    await rm(path.join(directory, manifest.assets[1].file));
    await assert.rejects(checkAudioPack(directory), /ENOENT/);
  });
});

test('CLI check succeeds, bad commands fail, and tampering yields a nonzero exit', async () => {
  await withPack(async (directory, manifest) => {
    const run = args => spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8' });
    const checked = run(['check', '--out', directory]);
    assert.equal(checked.status, 0, checked.stderr);
    assert.match(checked.stdout, /Listening not verified/);
    assert.equal(run(['invalid']).status, 1);
    assert.equal(run(['check', '--unknown', directory]).status, 1);
    const file = path.join(directory, manifest.assets[1].file);
    const damaged = await readFile(file);
    damaged[1004] ^= 1;
    await writeFile(file, damaged);
    const result = run(['check', '--out', directory]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /hash\/bytes differ/);
    assert.deepEqual(await readFile(file), damaged);
  });
});
