/** Pure first-party synthesis. No I/O, external samples, global random state or DSP dependencies. */
import { title, titleHarmony, titleMelody } from './cues/music-title.ts';
import { cardPlayAttack, uiClick } from './cues/sfx.ts';

export const cueIds = Object.freeze(['music.title', 'sfx.ui_click', 'sfx.card_play_attack'] as const);
export type CueId = typeof cueIds[number];

const TAU = 2 * Math.PI;
const specs = Object.freeze({
  'music.title': Object.freeze({ duration: title.duration, sampleRate: 22050, loop: true }),
  'sfx.ui_click': Object.freeze({ duration: uiClick.duration, sampleRate: 44100, loop: false }),
  'sfx.card_play_attack': Object.freeze({ duration: cardPlayAttack.duration, sampleRate: 44100, loop: false }),
});

export function cueSpec(id: string): Readonly<{ duration: number; sampleRate: number; loop: boolean }> {
  if (!Object.hasOwn(specs, id)) throw new RangeError(`Unknown audio cue: ${id}`);
  return specs[id as CueId];
}

/** xorshift32: each renderer owns a fresh fixed seed, so call order cannot affect output. */
function noise(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return (state >>> 0) / 0x100000000 * 2 - 1;
  };
}

function frequency(note: string): number {
  const match = /^([A-G])(#?)([0-8])$/.exec(note);
  if (!match) throw new RangeError(`Invalid note: ${note}`);
  const semitone = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 }[match[1]]!;
  const midi = (Number(match[3]) + 1) * 12 + semitone + (match[2] ? 1 : 0);
  return 440 * 2 ** ((midi - 69) / 12);
}

function ramp(x: number): number {
  const clipped = Math.max(0, Math.min(1, x));
  return 0.5 - 0.5 * Math.cos(Math.PI * clipped);
}

function envelope(t: number, duration: number, attack: number, release: number): number {
  return ramp(t / attack) * ramp((duration - t) / release);
}

function addFlute(out: Float32Array, sampleRate: number, note: string, start: number, duration: number, gain: number): void {
  const first = Math.round(start * sampleRate);
  const count = Math.round(duration * sampleRate);
  const hz = frequency(note);
  let phase = 0;
  for (let i = 0; i < count && first + i < out.length; i++) {
    const t = i / sampleRate;
    const breath = envelope(t, duration, 0.026, Math.min(0.060, duration / 3));
    // Very shallow vibrato, introduced after the note speaks.
    phase += TAU * hz / sampleRate * (1 + 0.0018 * ramp(t / 0.12) * Math.sin(TAU * 4.7 * t));
    const tone = Math.sin(phase) + 0.12 * Math.sin(2 * phase) + 0.035 * Math.sin(3 * phase);
    out[first + i] += gain * breath * tone;
  }
}

function addPluck(out: Float32Array, sampleRate: number, note: string, start: number, duration: number, gain: number, seed: number): void {
  const first = Math.round(start * sampleRate);
  const count = Math.round(duration * sampleRate);
  // Fractional-period interpolation preserves pitch without depending on a platform DSP library.
  const period = sampleRate / frequency(note) - 0.5;
  const length = Math.ceil(period) + 2;
  const ring = new Float64Array(length);
  const random = noise(seed);
  for (let i = 0; i < length; i++) ring[i] = random();
  let index = 0;
  let previous = 0;
  for (let i = 0; i < count && first + i < out.length; i++) {
    const read = (index - period + length) % length;
    const floor = Math.floor(read);
    const fraction = read - floor;
    const delayed = ring[floor] * (1 - fraction) + ring[(floor + 1) % length] * fraction;
    const sample = 0.498 * (delayed + previous);
    ring[index] = sample;
    previous = delayed;
    index = (index + 1) % length;
    out[first + i] += gain * sample * envelope(i / sampleRate, duration, 0.006, 0.070);
  }
}

function renderTitle(sampleRate: number): Float32Array {
  const out = new Float32Array(Math.round(title.duration * sampleRate));
  const eighth = 30 / title.bpm;
  let beat = 0;
  titleMelody.forEach(([note, eighths], i) => {
    const duration = eighths * eighth;
    const phraseAccent = [0.98, 0.88, 0.82, 0.90][Math.floor(beat / 8)];
    addFlute(out, sampleRate, note, beat * eighth + 0.012, duration - 0.036,
      0.205 * phraseAccent * (i % 4 === 0 ? 1.05 : 1));
    beat += eighths;
  });
  titleHarmony.forEach((bar, barIndex) => {
    bar.forEach((note, i) => {
      addPluck(out, sampleRate, note, barIndex * 2 + i * 0.5 + 0.010,
        Math.min(0.72, 8 - (barIndex * 2 + i * 0.5) - 0.03),
        i === 0 ? 0.18 : 0.13, title.seed + barIndex * 17 + i);
    });
    addFlute(out, sampleRate, bar[0], barIndex * 2 + 0.018, 1.84, 0.036);
  });
  for (let i = 0; i < out.length; i++) {
    out[i] *= title.gain * envelope(i / sampleRate, title.duration, 0.020, 0.035);
  }
  return out;
}

function renderClick(sampleRate: number): Float32Array {
  const out = new Float32Array(Math.round(uiClick.duration * sampleRate));
  const random = noise(uiClick.seed);
  let phase = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / sampleRate;
    phase += TAU * (1020 + 460 * Math.exp(-t * 50)) / sampleRate;
    const body = 0.83 * Math.sin(phase) + 0.17 * Math.sin(phase * 0.501);
    const dust = random() * 0.045 * Math.exp(-t * 90);
    out[i] = uiClick.gain * (body * Math.exp(-t * 26) + dust)
      * envelope(t, uiClick.duration, 0.0025, 0.012);
  }
  return out;
}

function renderAttack(sampleRate: number): Float32Array {
  const out = new Float32Array(Math.round(cardPlayAttack.duration * sampleRate));
  const random = noise(cardPlayAttack.seed);
  let low = 0;
  let phase = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / sampleRate;
    low += (1 - Math.exp(-TAU * 1500 / sampleRate)) * (random() - low);
    phase += TAU * (80 + 170 * Math.exp(-t * 24)) / sampleRate;
    const body = Math.sin(phase) * Math.exp(-t * 12);
    const swipe = low * Math.sin(Math.PI * Math.min(1, t / 0.22)) * Math.exp(-t * 5);
    out[i] = cardPlayAttack.gain * (0.78 * body + 0.52 * swipe)
      * envelope(t, cardPlayAttack.duration, 0.006, 0.030);
  }
  return out;
}

/** Render an independent buffer. Only integer sample rates 8–96 kHz are accepted. */
export function renderCue(id: string, sampleRate: number): Float32Array {
  cueSpec(id);
  if (!Number.isInteger(sampleRate) || sampleRate < 8000 || sampleRate > 96000) {
    throw new RangeError('sampleRate must be an integer from 8000 through 96000');
  }
  const out = id === 'music.title' ? renderTitle(sampleRate)
    : id === 'sfx.ui_click' ? renderClick(sampleRate) : renderAttack(sampleRate);
  // An explicit exact-zero endpoint contract, including float negative zero.
  out[0] = 0;
  out[out.length - 1] = 0;
  return out;
}
