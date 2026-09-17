import { describe, it, expect } from 'vitest';
import { initialState, step, type Face, type Rng } from '../src/engine.js';
import { bustChance, expectedRollGain, keepOptions } from '../src/odds.js';
import { faceChance, faceWeights, luckyRng, type Rng } from '../src/engine.js';

/// The same PRNG the sims and the parity harness use, so a bent stream
/// can be counted here against a fair one from the same seed.
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

function rngForFaces(faces: Face[]): Rng {
  let i = 0;
  return () => {
    const f = faces[i % faces.length];
    i++;
    return (f - 1) / 6 + 0.0001;
  };
}

describe('bustChance', () => {
  it('is zero with nothing picked yet', () => {
    expect(bustChance([], 8)).toBe(0);
  });

  it('is one face in six for a single die over one dead face', () => {
    expect(bustChance([1], 1)).toBeCloseTo(1 / 6, 12);
  });

  it('compounds across dice', () => {
    expect(bustChance([1, 2, 3], 2)).toBeCloseTo(0.25, 12);
  });

  it('is certain once every face is spent', () => {
    expect(bustChance([1, 2, 3, 4, 5, 6], 4)).toBe(1);
  });
});

describe('expectedRollGain', () => {
  it('is the mean best face for a single fresh die', () => {
    // Faces 1-5 score their pips, the coin scores 5: (1+2+3+4+5+5)/6.
    expect(expectedRollGain([], 1)).toBeCloseTo(20 / 6, 12);
  });

  it('is zero when every face is already spent', () => {
    expect(expectedRollGain([1, 2, 3, 4, 5, 6], 5)).toBe(0);
  });

  it('is zero with no dice left to roll', () => {
    expect(expectedRollGain([1], 0)).toBe(0);
  });

  it('counts only the live faces', () => {
    // One die, coin already picked: the coin's 5 becomes a blank, so
    // the mean is (1+2+3+4+5+0)/6.
    expect(expectedRollGain([6], 1)).toBeCloseTo(15 / 6, 12);
  });

  it('enumerates a whole probability mass, never more than one', () => {
    // Sanity on the multinomial walk: the best gain from eight dice is
    // capped at 8 * 5, so the expectation must sit inside that.
    const ev = expectedRollGain([], 8);
    expect(ev).toBeGreaterThan(0);
    expect(ev).toBeLessThan(40);
  });

  it('falls as dice leave the hand', () => {
    const many = expectedRollGain([6], 6);
    const few = expectedRollGain([6], 2);
    expect(many).toBeGreaterThan(few);
  });
});

describe('keepOptions', () => {
  it('is empty before anything is rolled', () => {
    expect(keepOptions(initialState(['A', 'B']))).toEqual([]);
  });

  it('describes each takeable face once', () => {
    const rng = rngForFaces([6, 3, 3, 3, 2, 2, 1, 1]);
    let s = initialState(['A', 'B']);
    s = step(s, { type: 'ROLL' }, rng);

    const options = keepOptions(s);
    expect(options.map((o) => o.face)).toEqual([1, 2, 3, 6]);

    const threes = options.find((o) => o.face === 3)!;
    expect(threes.count).toBe(3);
    expect(threes.gain).toBe(9);
    expect(threes.diceLeft).toBe(5);
    expect(threes.securesPearl).toBe(false);

    const coin = options.find((o) => o.face === 6)!;
    expect(coin.gain).toBe(5);
    expect(coin.securesPearl).toBe(true);
  });

  it('prices the worked example: one 2 against three 3s', () => {
    // Bram's case. Three 3s score nine now but spend three dice; the
    // lone 2 scores two and keeps them, so the dice that stay in hand
    // can still come back as 5s or coins.
    const rng = rngForFaces([2, 3, 3, 3, 1, 1, 1, 1]);
    let s = initialState(['A', 'B']);
    s = step(s, { type: 'ROLL' }, rng);

    const options = keepOptions(s);
    const two = options.find((o) => o.face === 2)!;
    const three = options.find((o) => o.face === 3)!;

    expect(two.gain).toBeLessThan(three.gain);
    expect(two.diceLeft).toBeGreaterThan(three.diceLeft);
    // The whole point of the example: more dice left is worth more
    // future value, and the immediate nine does not cover the gap on
    // its own.
    expect(two.expectedRollGain).toBeGreaterThan(three.expectedRollGain);
    expect(two.bustChance).toBeLessThan(three.bustChance);
  });

  it('skips faces already set aside', () => {
    const rng = rngForFaces([6, 6, 4, 4, 4, 4, 4, 4]);
    let s = initialState(['A', 'B']);
    s = step(s, { type: 'ROLL' }, rng);
    s = step(s, { type: 'PICK', face: 6 }, rng);
    s = step(s, { type: 'ROLL' }, rng);

    const options = keepOptions(s);
    expect(options.some((o) => o.face === 6)).toBe(false);
  });
});

/// The Easy handicap: a die bent toward the coin, and the odds that
/// have to know about it. Mirror of `LuckyDiceTests` in
/// `ios/ShellYesEngine/Tests/ShellYesEngineTests/OddsTests.swift` —
/// change one, change both, then run `node parity/diff.mjs`.
describe('lucky dice', () => {
  it('spreads the bonus over the three high faces', () => {
    for (const face of [4, 5, 6] as const) {
      expect(faceChance(face, 0.06)).toBeCloseTo(1 / 6 + 0.02, 12);
    }
    for (const face of [1, 2, 3] as const) {
      expect(faceChance(face, 0.06)).toBeCloseTo(1 / 6 - 0.02, 12);
    }
  });

  it('never bends past the cap', () => {
    // At 0.5 the low faces already never come up; more is clamped.
    for (const face of [1, 2, 3] as const) {
      expect(faceChance(face, 5)).toBeCloseTo(0, 12);
    }
    for (const face of [4, 5, 6] as const) {
      expect(faceChance(face, 5)).toBeCloseTo(1 / 3, 12);
    }
  });

  it('sums to one however far it is bent', () => {
    for (const luck of [0, 0.05, 0.2, 0.5]) {
      const total = ([1, 2, 3, 4, 5, 6] as const).reduce(
        (sum, f) => sum + faceChance(f, luck),
        0,
      );
      expect(total).toBeCloseTo(1, 12);
    }
  });

  it('makes spending the coin more dangerous than spending the one', () => {
    // The point of taking faces rather than a count. On a fair die the
    // two are the same; on a bent one they are not.
    expect(bustChance([6], 2, 0.05)).toBeGreaterThan(bustChance([1], 2, 0.05));
    expect(bustChance([6], 2)).toBeCloseTo(bustChance([1], 2), 12);
  });

  it('is the fair formula at zero luck', () => {
    expect(bustChance([1, 2, 3], 3)).toBeCloseTo(0.5 ** 3, 12);
  });

  it('is worth more per roll, which is the point of granting it', () => {
    expect(expectedRollGain([], 4, 0.05)).toBeGreaterThan(expectedRollGain([], 4));
  });

  it('is still worth nothing when every face is spent', () => {
    expect(expectedRollGain([1, 2, 3, 4, 5, 6], 5, 0.05)).toBe(0);
  });

  it('rolls the distribution it advertises, one draw a die', () => {
    const lucky = luckyRng(mulberry32(99), 0.06);
    const counts = new Array(7).fill(0);
    const rolls = 240_000;
    for (let i = 0; i < rolls; i++) counts[Math.floor(lucky() * 6) + 1]++;
    for (const face of [1, 2, 3, 4, 5, 6] as const) {
      expect(counts[face] / rolls).toBeCloseTo(faceChance(face, 0.06), 2);
    }
  });

  it('still adds up to one whole die', () => {
    const total = faceWeights(0.06).reduce((sum, w) => sum + w, 0);
    expect(total).toBeCloseTo(1, 12);
  });

  it('is the fair stream at zero luck', () => {
    const fair = mulberry32(7);
    const lucky = luckyRng(mulberry32(7), 0);
    for (let i = 0; i < 500; i++) expect(lucky()).toBe(fair());
  });
});
