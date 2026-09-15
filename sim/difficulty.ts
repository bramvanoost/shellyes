// Difficulty tuning harness for the iOS app's three-seat table.
//
// `sim/regression.ts` proves the AI tiers aren't cosmetic head to head.
// This one answers a different question: what does the *human* win rate
// look like at each difficulty, on the table the app actually deals?
//
// It exists because 1.2 shipped an Easy that was harder than Normal and
// nothing caught it. The regression sim couldn't: it plays two seats,
// and the bug only appears with three. See `Difficulty.seatDiscipline`
// in `GameStore.swift` for the full story.
//
// Two rules a difficulty ladder has to pass:
//   1. Win rate strictly decreases from easy to hard.
//   2. It does so at EVERY player skill, not just the one it was tuned
//      at. A ladder that inverts for weak players is the bug again.
//
// The human seat is played by the same AI at a fixed discipline, which
// is a stand-in for player skill, not a claim about it. The absolute
// numbers move with that stand-in; the ordering is what's being tested.

import { initialState, step, score, type Rng } from '../src/engine.js';
import { decide } from '../src/ai.js';

function mulberry32(seed: number): Rng {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const GAMES = 20_000;
const MAX_STEPS = 200_000;

/// Stand-ins for weak, middling and strong play.
const SKILLS = [0.35, 0.5, 0.65];

/// Mirrors `Difficulty.seatDiscipline` in GameStore.swift. Keep the two
/// in step — this file is what the comment there tells you to re-run.
const LADDER: Record<string, [number, number]> = {
  easy: [0.0, 0.0],
  normal: [0.2, 0.0],
  hard: [0.2, 0.5],
};

/// Bram's targets, roughly. Easy is capped by what the discipline knob
/// can actually reach (~59%), which he accepted rather than growing the
/// AI a second knob.
const TARGETS: Record<string, number> = { easy: 58.6, normal: 50, hard: 40 };

function humanWinRate(skill: number, seats: [number, number]): number {
  const discipline = [skill, seats[0], seats[1]];
  let wins = 0;
  for (let g = 0; g < GAMES; g++) {
    const rng = mulberry32(g + 1);
    let state = initialState(['you', 'one', 'two']);
    let steps = 0;
    while (state.phase !== 'over') {
      if (steps++ >= MAX_STEPS) {
        console.error(`skill ${skill} vs [${seats}]: game ${g} never terminated`);
        process.exit(1);
      }
      state = step(state, decide(state, { discipline: discipline[state.current] }), rng);
    }
    const scores = score(state);
    if (scores[0] === Math.max(...scores)) wins++;
  }
  return (100 * wins) / GAMES;
}

let failed = false;

for (const skill of SKILLS) {
  console.log(`\nplayer skill ${skill.toFixed(2)}  (${GAMES} games per difficulty)`);
  const rates: number[] = [];
  for (const [name, seats] of Object.entries(LADDER)) {
    const rate = humanWinRate(skill, seats);
    rates.push(rate);
    const drift = rate - TARGETS[name];
    console.log(
      `  ${name.padEnd(7)}[${seats.map((s) => s.toFixed(2)).join(', ')}]  ` +
        `${rate.toFixed(1)}%  (target ${TARGETS[name]}, ${drift >= 0 ? '+' : ''}${drift.toFixed(1)})`,
    );
  }
  // Rule 1 and 2: strictly decreasing, here and at every other skill.
  for (let i = 1; i < rates.length; i++) {
    if (rates[i] >= rates[i - 1]) {
      const names = Object.keys(LADDER);
      console.error(
        `  FAIL: ${names[i]} (${rates[i].toFixed(1)}%) is not harder than ` +
          `${names[i - 1]} (${rates[i - 1].toFixed(1)}%) at skill ${skill}`,
      );
      failed = true;
    }
  }
}

if (failed) {
  console.error('\nFAIL: the difficulty ladder is not monotone at every skill');
  process.exit(1);
}
console.log('\nOK: every difficulty is harder than the one below it, at every skill');
