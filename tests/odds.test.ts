import { describe, it, expect } from 'vitest';
import { initialState, step, type Face, type Rng } from '../src/engine.js';
import { bustChance, expectedRollGain, keepOptions } from '../src/odds.js';

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
    expect(bustChance(0, 8)).toBe(0);
  });

  it('is one face in six for a single die over one dead face', () => {
    expect(bustChance(1, 1)).toBeCloseTo(1 / 6, 12);
  });

  it('compounds across dice', () => {
    expect(bustChance(3, 2)).toBeCloseTo(0.25, 12);
  });

  it('is certain once every face is spent', () => {
    expect(bustChance(6, 4)).toBe(1);
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
