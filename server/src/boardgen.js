// Offline board generation (Node only — NOT imported by the Worker). Runs the full
// 152k-word solver per redraw attempt, which is why boards are precomputed and stored
// in D1 rather than generated on the edge. Mirrors RUNG/Sources/Core/BoardGenerator.swift.

import { SplitMix64, seedForDay, LETTER_WEIGHTS, baseScore } from "./engine.js";

export const DEFAULT_GATES = {
  minVowels: 4, maxVowels: 6,
  minPlayable: 80, maxPlayable: 800,
  minLong: 1, longLen: 7,
  minShort: 20, shortLen: 4,
  maxAttempts: 10000, solveMax: 12,
};

const VOWELS = new Set([0, 4, 8, 14, 20]); // A E I O U

/** Build the solve set (words length 3..solveMax) with precomputed histograms. */
export class Dict {
  constructor(words, solveMax = 12) {
    this.has = new Set(words);
    const lens = [], scores = [], hists = [];
    for (const w of words) {
      const n = w.length;
      if (n < 3 || n > solveMax) continue;
      const h = new Uint8Array(26);
      let ok = true;
      for (let i = 0; i < n; i++) {
        const v = w.charCodeAt(i) - 65;
        if (v < 0 || v > 25) { ok = false; break; }
        h[v]++;
      }
      if (!ok) continue;
      lens.push(n);
      scores.push(baseScore(w));
      hists.push(h);
    }
    this.lens = lens; this.scores = scores; this.hists = hists; this.count = lens.length;
  }
}

export function generateBoard(dayIndex, dict, gates = DEFAULT_GATES) {
  const cum = []; let run = 0;
  for (const w of LETTER_WEIGHTS) { run += w; cum.push(run); }
  const total = BigInt(run);
  const rng = new SplitMix64(seedForDay(dayIndex));

  let attempts = 0;
  while (attempts < gates.maxAttempts) {
    attempts++;
    const hist = new Array(26).fill(0);
    let vowels = 0;
    for (let t = 0; t < 12; t++) {
      const r = Number(rng.next() % total);
      let i = 0; while (r >= cum[i]) i++;
      hist[i]++;
      if (VOWELS.has(i)) vowels++;
    }
    if (vowels < gates.minVowels || vowels > gates.maxVowels) continue;

    let playable = 0, maxScore = 0, long = 0, short = 0;
    for (let k = 0; k < dict.count; k++) {
      const h = dict.hists[k];
      let ok = true;
      for (let j = 0; j < 26; j++) { if (h[j] > hist[j]) { ok = false; break; } }
      if (ok) {
        playable++;
        const sc = dict.scores[k]; if (sc > maxScore) maxScore = sc;
        const L = dict.lens[k];
        if (L >= gates.longLen) long++;
        if (L <= gates.shortLen) short++;
      }
    }
    if (playable < gates.minPlayable || playable > gates.maxPlayable) continue;
    if (long < gates.minLong || short < gates.minShort) continue;

    let tiles = "";
    for (let idx = 0; idx < 26; idx++) for (let c = 0; c < hist[idx]; c++) tiles += String.fromCharCode(65 + idx);
    return { dayIndex, tiles, hist, playableCount: playable, maxWordScore: maxScore, attempts };
  }
  throw new Error("BoardGenerator exceeded maxAttempts for day " + dayIndex);
}
