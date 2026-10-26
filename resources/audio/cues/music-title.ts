/** Original D0 score: four 4/4 bars at 120 BPM = exactly eight seconds.
 * Eighth-note counts are recorded in README.md. Not the final 76 BPM title cue.
 */
export const title = Object.freeze({
  id: 'music.title',
  duration: 8,
  bpm: 120,
  gain: 0.82,
  seed: 0x57454c4c,
});

export const titleMelody: readonly (readonly [string, number])[] = Object.freeze([
  ['A4', 2], ['G4', 1], ['F4', 1], ['E4', 2], ['D4', 2],
  ['G4', 2], ['E4', 2], ['D4', 1], ['C4', 1], ['A3', 2],
  ['C4', 2], ['D4', 1], ['E4', 1], ['G4', 2], ['E4', 2],
  ['E4', 1], ['G4', 1], ['A4', 2], ['D5', 4],
].map(([note, eighths]) => Object.freeze([note, eighths] as [string, number])));

/** Dm(add9), C, Am7, Dsus2. Each row is one bar, four soft plucks. */
export const titleHarmony: readonly (readonly string[])[] = Object.freeze([
  ['D3', 'A3', 'E4', 'F4'],
  ['C3', 'G3', 'E4', 'G3'],
  ['A2', 'E3', 'G3', 'C4'],
  ['D3', 'A3', 'E4', 'A3'],
].map(notes => Object.freeze(notes)));
