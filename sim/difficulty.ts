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
//   3. Easy clears an absolute floor at middling skill. Monotone alone
//      is satisfied by three tiers nobody would call easy.
//
// The human seat is played by the same AI at a fixed discipline, which
// is a stand-in for player skill, not a claim about it. The absolute
// numbers move with that stand-in; the ordering is what's being tested.

import { initialState, luckyRng, step, score, type Rng } from '../src/engine.js';
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

/// Mirrors `Difficulty.seatDiscipline` and `Difficulty.luck` in
/// GameStore.swift. Keep the two in step — this file is what the
/// comment there tells you to re-run.
///
/// `luck` bends the *human's* dice and nobody else's: the coin comes
/// up `1/6 + luck` of the time. Easy is the only tier that gets any.
const LADDER: Record<string, { seats: [number, number]; luck: number }> = {
  easy: { seats: [0.0, 0.0], luck: 0.05 },
  normal: { seats: [0.2, 0.0], luck: 0 },
  hard: { seats: [0.2, 0.5], luck: 0 },
};

/// Bram's targets, roughly.
///
/// Easy used to buy its win rate entirely by making the bots greedy,
/// at -0.20 a seat, and greedy bots fail 56% of their turns — which
/// reads as a table of idiots rather than an easy game. It now sits at
/// 0.00, where they fail 49%, and the difference is paid back in the
/// human's dice instead.
const TARGETS: Record<string, number> = { easy: 63, normal: 50, hard: 40 };

/// Easy has to clear this at middling skill, not merely beat Normal.
/// A ladder can be perfectly monotone and still open on a tier nobody
/// would call easy, which is what 1.3 shipped.
const EASY_FLOOR = 60;

function humanWinRate(skill: number, seats: [number, number], luck: number): number {
  const discipline = [skill, seats[0], seats[1]];
  let wins = 0;
  for (let g = 0; g < GAMES; g++) {
    const base = mulberry32(g + 1);
    // One bent view of the same stream, handed to seat 0 only. The
    // bots keep rolling the fair dice off `base`.
    const lucky = luckyRng(base, luck);
    let state = initialState(['you', 'one', 'two']);
    let steps = 0;
    while (state.phase !== 'over') {
      if (steps++ >= MAX_STEPS) {
        console.error(`skill ${skill} vs [${seats}]: game ${g} never terminated`);
        process.exit(1);
      }
      state = step(
        state,
        decide(state, { discipline: discipline[state.current] }),
        state.current === 0 ? lucky : base,
      );
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
  for (const [name, { seats, luck }] of Object.entries(LADDER)) {
    const rate = humanWinRate(skill, seats, luck);
    rates.push(rate);
    const drift = rate - TARGETS[name];
    console.log(
      `  ${name.padEnd(7)}[${seats.map((s) => s.toFixed(2)).join(', ')}] luck ${luck.toFixed(2)}  ` +
        `${rate.toFixed(1)}%  (target ${TARGETS[name]}, ${drift >= 0 ? '+' : ''}${drift.toFixed(1)})`,
    );
  }
  // Rule 3: Easy has to be easy in absolute terms, at middling skill.
  if (skill === 0.5 && rates[0] <= EASY_FLOOR) {
    console.error(
      `  FAIL: easy is ${rates[0].toFixed(1)}% at middling skill, ` +
        `which is not above the ${EASY_FLOOR}% floor`,
    );
    failed = true;
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
