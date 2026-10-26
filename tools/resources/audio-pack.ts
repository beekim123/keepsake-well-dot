#!/usr/bin/env node
/** Offline PCM16 packer and read-only verifier; Node built-ins only. */
import { createHash } from 'node:crypto';
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { cueIds, cueSpec, renderCue } from '../../resources/audio/synth.ts';

export const defaultOutput = fileURLToPath(new URL('../../resources/audio/export/', import.meta.url));
const MAX_FILE_BYTES = 2_000_000;
const ACTIVE_THRESHOLD = 0.001; // -60 dBFS; trim only leading/trailing silence, not interior rests.
const PEAK_LIMIT_DBFS = -1;

export type Metrics = {
  peak: number; peakDbfs: number; rmsDbfs: number; activeRmsDbfs: number;
  activeFrames: number; first: number; last: number;
  seam: { windowFrames: number; amplitude: number; slope: number; slopeMismatch: number };
};
type Asset = {
  id: string; file: string; sampleRate: number; channels: 1; frames: number;
  duration: number; loop: boolean; hash: string; metrics: Metrics; sampleHash: string;
};
type Manifest = { format: 'audio-manifest/1'; assets: Asset[] };

function sha256(data: Uint8Array): string { return createHash('sha256').update(data).digest('hex'); }
function db(amplitude: number): number { return amplitude > 0 ? 20 * Math.log10(amplitude) : -Infinity; }
function round(value: number): number { return Math.round(value * 1e9) / 1e9; }

function validSamples(samples: Float32Array): void {
  if (!(samples instanceof Float32Array) || samples.length < 2) throw new Error('Expected at least two Float32 samples');
  for (let i = 0; i < samples.length; i++) {
    if (!Number.isFinite(samples[i]) || Math.abs(samples[i]) > 1) throw new Error(`Invalid or clipped audio sample at ${i}`);
  }
}

export function analyzeSamples(samples: Float32Array, sampleRate: number): Metrics {
  validSamples(samples);
  if (!Number.isInteger(sampleRate) || sampleRate < 8000 || sampleRate > 96000) throw new Error('Invalid sample rate');
  let peak = 0;
  let squareSum = 0;
  let firstActive = -1;
  let lastActive = -1;
  for (let i = 0; i < samples.length; i++) {
    const amplitude = Math.abs(samples[i]);
    peak = Math.max(peak, amplitude);
    squareSum += samples[i] * samples[i];
    if (amplitude >= ACTIVE_THRESHOLD) {
      if (firstActive < 0) firstActive = i;
      lastActive = i;
    }
  }
  if (firstActive < 0) throw new Error('Cue is silent below -60 dBFS');
  let activeSquares = 0;
  for (let i = firstActive; i <= lastActive; i++) activeSquares += samples[i] * samples[i];
  const activeFrames = lastActive - firstActive + 1;
  const windowFrames = Math.min(Math.ceil(sampleRate * 0.002), Math.floor(samples.length / 2));
  let edgeAmplitude = 0;
  let edgeSlope = 0;
  for (let i = 0; i < windowFrames; i++) {
    const end = samples.length - 1 - i;
    edgeAmplitude = Math.max(edgeAmplitude, Math.abs(samples[i]), Math.abs(samples[end]));
    if (i > 0) edgeSlope = Math.max(edgeSlope, Math.abs(samples[i] - samples[i - 1]), Math.abs(samples[end + 1] - samples[end]));
  }
  return {
    peak: round(peak), peakDbfs: round(db(peak)),
    rmsDbfs: round(db(Math.sqrt(squareSum / samples.length))),
    activeRmsDbfs: round(db(Math.sqrt(activeSquares / activeFrames))), activeFrames,
    first: samples[0], last: samples[samples.length - 1],
    seam: {
      windowFrames, amplitude: round(edgeAmplitude), slope: round(edgeSlope),
      slopeMismatch: round(Math.abs((samples[1] - samples[0]) - (samples[samples.length - 1] - samples[samples.length - 2]))),
    },
  };
}

export function validateMetrics(id: string, metrics: Metrics, loop: boolean): void {
  const fail = (reason: string) => { throw new Error(`${id}: ${reason}`); };
  if (metrics.peakDbfs > PEAK_LIMIT_DBFS) fail(`peak ${metrics.peakDbfs} dBFS exceeds -1 dBFS`);
  const music = id.startsWith('music.');
  const level = music ? metrics.rmsDbfs : metrics.activeRmsDbfs;
  const minimum = music ? -22 : -21;
  const maximum = music ? -18 : -15;
  if (!Number.isFinite(level) || level < minimum || level > maximum) fail(`RMS ${level} dBFS is outside ${minimum}..${maximum}`);
  if (loop) {
    if (metrics.first !== 0 || metrics.last !== 0) fail('loop endpoints must be exactly zero');
    if (metrics.seam.amplitude > 0.01) fail('2 ms loop-edge amplitude exceeds 0.01');
    if (metrics.seam.slope > 0.001 || metrics.seam.slopeMismatch > 0.001) fail('loop-edge slope exceeds 0.001/sample');
  }
}

export function encodePcm16Wav(samples: Float32Array, sampleRate: number): Buffer {
  validSamples(samples);
  if (!Number.isInteger(sampleRate) || sampleRate < 8000 || sampleRate > 96000) throw new Error('Invalid sample rate');
  const bytes = Buffer.alloc(44 + samples.length * 2);
  if (bytes.length >= MAX_FILE_BYTES) throw new Error('WAV must be smaller than 2 MB');
  bytes.write('RIFF', 0); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write('WAVE', 8);
  bytes.write('fmt ', 12); bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20);
  bytes.writeUInt16LE(1, 22); bytes.writeUInt32LE(sampleRate, 24); bytes.writeUInt32LE(sampleRate * 2, 28);
  bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34);
  bytes.write('data', 36); bytes.writeUInt32LE(samples.length * 2, 40);
  for (let i = 0; i < samples.length; i++) bytes.writeInt16LE(Math.round(samples[i] * 32767), 44 + i * 2);
  return bytes;
}

/** Require our canonical little-endian, mono PCM16 RIFF layout; no ignored trailer/chunk. */
export function decodePcm16Wav(bytes: Buffer): { samples: Float32Array; sampleRate: number } {
  if (bytes.length < 48 || bytes.length >= MAX_FILE_BYTES || bytes.length % 2) throw new Error('Invalid WAV size');
  if (bytes.toString('ascii', 0, 4) !== 'RIFF' || bytes.toString('ascii', 8, 12) !== 'WAVE'
    || bytes.toString('ascii', 12, 16) !== 'fmt ' || bytes.toString('ascii', 36, 40) !== 'data'
    || bytes.readUInt32LE(4) !== bytes.length - 8 || bytes.readUInt32LE(16) !== 16
    || bytes.readUInt16LE(20) !== 1 || bytes.readUInt16LE(22) !== 1 || bytes.readUInt16LE(34) !== 16
    || bytes.readUInt16LE(32) !== 2 || bytes.readUInt32LE(40) !== bytes.length - 44) throw new Error('Invalid canonical mono PCM16 WAV header');
  const sampleRate = bytes.readUInt32LE(24);
  if (sampleRate < 8000 || sampleRate > 96000 || bytes.readUInt32LE(28) !== sampleRate * 2) throw new Error('Invalid WAV sample rate');
  const samples = new Float32Array((bytes.length - 44) / 2);
  // PCM16 full scale is 32768; check what the player will actually decode.
  for (let i = 0; i < samples.length; i++) samples[i] = bytes.readInt16LE(44 + i * 2) / 32768;
  return { samples, sampleRate };
}

function sampleBytes(samples: Float32Array): Buffer {
  const bytes = Buffer.alloc(samples.length * 4);
  for (let i = 0; i < samples.length; i++) bytes.writeFloatLE(samples[i], i * 4);
  return bytes;
}

function synthesizePack(): { manifest: Manifest; files: Map<string, Buffer> } {
  const manifest: Manifest = { format: 'audio-manifest/1', assets: [] };
  const files = new Map<string, Buffer>();
  for (const id of cueIds) {
    const spec = cueSpec(id);
    const a = renderCue(id, spec.sampleRate);
    const b = renderCue(id, spec.sampleRate);
    if (a.length !== b.length) throw new Error(`${id}: nondeterministic sample count`);
    for (let i = 0; i < a.length; i++) if (!Object.is(a[i], b[i])) throw new Error(`${id}: nondeterministic sample ${i}`);
    const sampleHash = sha256(sampleBytes(a));
    if (sampleHash !== sha256(sampleBytes(b))) throw new Error(`${id}: nondeterministic float sample hash`);
    if (a.length !== Math.round(spec.duration * spec.sampleRate)) throw new Error(`${id}: unexpected duration`);
    validateMetrics(id, analyzeSamples(a, spec.sampleRate), spec.loop);
    const wav = encodePcm16Wav(a, spec.sampleRate);
    if (!wav.equals(encodePcm16Wav(b, spec.sampleRate))) throw new Error(`${id}: nondeterministic WAV bytes`);
    const decoded = decodePcm16Wav(wav);
    const metrics = analyzeSamples(decoded.samples, decoded.sampleRate);
    validateMetrics(id, metrics, spec.loop);
    const file = `${id.replaceAll('.', '_')}.wav`;
    files.set(file, wav);
    manifest.assets.push({
      id, file, sampleRate: spec.sampleRate, channels: 1, frames: a.length,
      duration: a.length / spec.sampleRate, loop: spec.loop, hash: sha256(wav), metrics, sampleHash,
    });
  }
  return { manifest, files };
}

function manifestText(manifest: Manifest): string { return `${JSON.stringify(manifest, null, 2)}\n`; }

export async function buildAudioPack(output = defaultOutput): Promise<Manifest> {
  const { manifest, files } = synthesizePack();
  await mkdir(output, { recursive: true });
  for (const [file, bytes] of files) await writeFile(path.join(output, file), bytes);
  await writeFile(path.join(output, 'manifest.json'), manifestText(manifest));
  return manifest;
}

/** Read-only: never repairs/rebuilds a stale export, even on failure. */
export async function checkAudioPack(output = defaultOutput): Promise<Manifest> {
  const { manifest, files } = synthesizePack();
  const actualManifest = await readFile(path.join(output, 'manifest.json'), 'utf8');
  if (actualManifest !== manifestText(manifest)) throw new Error('Audio manifest differs from current source; rebuild or investigate tampering');
  for (const asset of manifest.assets) {
    const actual = await readFile(path.join(output, asset.file));
    const decoded = decodePcm16Wav(actual);
    if (decoded.sampleRate !== asset.sampleRate || decoded.samples.length !== asset.frames) throw new Error(`${asset.id}: WAV format differs`);
    validateMetrics(asset.id, analyzeSamples(decoded.samples, decoded.sampleRate), asset.loop);
    if (sha256(actual) !== asset.hash || !actual.equals(files.get(asset.file)!)) throw new Error(`${asset.id}: WAV hash/bytes differ from source`);
  }
  const unexpected = (await readdir(output)).filter(file => file.endsWith('.wav') && !files.has(file));
  if (unexpected.length) throw new Error(`Unregistered WAV exports: ${unexpected.join(', ')}`);
  return manifest;
}

function report(manifest: Manifest, action: string): void {
  for (const asset of manifest.assets) {
    const m = asset.metrics;
    console.log(`${asset.id}: ${asset.frames} samples / ${asset.sampleRate} Hz / ${asset.duration.toFixed(3)} s / ${44 + asset.frames * 2} bytes`);
    console.log(`  peak ${m.peakDbfs.toFixed(3)} dBFS; RMS ${m.rmsDbfs.toFixed(3)}; active RMS ${m.activeRmsDbfs.toFixed(3)}; seam amplitude ${m.seam.amplitude}, slope ${m.seam.slope}, mismatch ${m.seam.slopeMismatch}`);
    console.log(`  WAV SHA-256 ${asset.hash}; Float32 SHA-256 ${asset.sampleHash}`);
  }
  console.log(`${action}: ${manifest.assets.length} cues pass numerical checks and double-render equality. Listening not verified.`);
}

async function main(args: string[]): Promise<void> {
  const action = args.shift();
  if (action !== 'build' && action !== 'check') throw new Error('Usage: node tools/resources/audio-pack.ts build|check [--out <directory>]');
  let output = defaultOutput;
  if (args.length) {
    if (args.length !== 2 || args[0] !== '--out' || !args[1] || args[1].startsWith('--')) throw new Error('Only --out <directory> is supported');
    output = path.resolve(args[1]);
  }
  const manifest = action === 'build' ? await buildAudioPack(output) : await checkAudioPack(output);
  report(manifest, action);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch(error => { console.error(`audio: ${error.message}`); process.exitCode = 1; });
}
