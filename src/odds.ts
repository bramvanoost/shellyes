// Exact odds for explanation mode. Pure: no I/O, no rng, no Date.
//
// The AI already carries a bust probability inline (`ai.ts`), but it
// only ever needs one number for itself. Explaining a decision to a
// player needs the same maths broken out per keep option, so this file
// owns it and `ai.ts` is free to keep its private shortcut.
//
// Scope is one roll of lookahead, deliberately. The full "play to the
// end optimally" value needs a search over every future keep, and the
// number it produces is less use to a player than "what does this roll
// cost me" — which is the question a keep decision actually asks.

import { COIN, faceValue, type Face, type State } from './engine.js';

const ALL_FACES: readonly Face[] = [1, 2, 3, 4, 5, 6];

/// One face the player could take from the current roll, with what it
/// costs and buys. `gain` is immediate, the other two are what the
/// board looks like afterwards.
export type KeepOption = {
  face: Face;
  /// How many dice show this face.
  count: number;
  /// Value added to the set-aside sum by taking them. The coin scores
  /// 5, same as `faceValue`.
  gain: number;
  /// Dice still in hand after taking them.
  diceLeft: number;
  /// Chance the next roll shows nothing takeable, i.e. a bust.
  bustChance: number;
  /// Expected value the next roll adds, counting a bust as zero.
  expectedRollGain: number;
  /// True when this face is the coin, so taking it makes the pile
  /// bankable. Without one, stopping busts however high the sum.
  securesPearl: boolean;
};

/// Chance that a roll of `diceInHand` dice shows only faces already
/// picked, which is exactly the engine's bust condition.
///
/// Each die independently lands on one of the `pickedCount` dead faces
/// with probability `pickedCount / 6`, so the roll is dead with
/// probability `(pickedCount / 6) ^ diceInHand`. Exact, not sampled.
export function bustChance(pickedCount: number, diceInHand: number): number {
  return Math.pow(pickedCount / 6, diceInHand);
}

/// Expected value a single roll of `diceInHand` dice adds, given the
/// faces already spent.
///
/// Enumerates every distribution of the dice across the six faces with
/// its exact multinomial probability, then credits the best face
/// available in that roll. "Best" is the greedy rule a player reads as
/// obvious — highest `count * faceValue` — not a search, so the number
/// is a floor on what careful play scores, not a ceiling.
///
/// A roll with no available face contributes zero, which is what folds
/// the bust case into the same number.
export function expectedRollGain(pickedFaces: readonly Face[], diceInHand: number): number {
  if (diceInHand <= 0) return 0;
  const dead = new Set(pickedFaces);
  const counts = new Array<number>(6).fill(0);
  let total = 0;

  // Walk the compositions of `diceInHand` over six faces. At most
  // C(13,5) = 1287 of them for a full hand, so exhaustive is cheap.
  const walk = (faceIndex: number, remaining: number): void => {
    if (faceIndex === 5) {
      counts[5] = remaining;
      total += multinomial(counts, diceInHand) * bestGain(counts, dead);
      return;
    }
    for (let n = 0; n <= remaining; n++) {
      counts[faceIndex] = n;
      walk(faceIndex + 1, remaining - n);
    }
    counts[faceIndex] = 0;
  };
  walk(0, diceInHand);
  return total;
}

/// Every face the player could take from the roll on the table, with
/// the odds that follow it. Empty in any phase but `pick`, and empty
/// when the roll is dead — which is the bust the engine is about to
/// apply.
export function keepOptions(state: State): KeepOption[] {
  if (state.phase !== 'pick') return [];
  const dead = new Set(state.pickedFaces);
  const options: KeepOption[] = [];
  for (const face of ALL_FACES) {
    if (dead.has(face)) continue;
    const count = state.rolled.filter((f) => f === face).length;
    if (count === 0) continue;
    const diceLeft = state.diceInHand - count;
    const nextPicked = [...state.pickedFaces, face];
    options.push({
      face,
      count,
      gain: count * faceValue(face),
      diceLeft,
      bustChance: bustChance(nextPicked.length, diceLeft),
      expectedRollGain: expectedRollGain(nextPicked, diceLeft),
      securesPearl: face === COIN,
    });
  }
  return options;
}

/// Probability mass of one exact count vector under six fair dice:
/// `d! / (c0!...c5!) * (1/6)^d`.
function multinomial(counts: readonly number[], dice: number): number {
  let coefficient = factorial(dice);
  for (const c of counts) coefficient /= factorial(c);
  return coefficient * Math.pow(1 / 6, dice);
}

/// Best immediate gain from one rolled count vector, or zero when
/// every face in it has already been picked.
function bestGain(counts: readonly number[], dead: ReadonlySet<Face>): number {
  let best = 0;
  for (let i = 0; i < 6; i++) {
    const face = (i + 1) as Face;
    if (dead.has(face) || counts[i] === 0) continue;
    const gain = counts[i] * faceValue(face);
    if (gain > best) best = gain;
  }
  return best;
}

/// Eight dice is the whole game, so the table is nine entries long and
/// exact in a double the entire way.
const FACTORIALS = [1, 1, 2, 6, 24, 120, 720, 5040, 40320];

function factorial(n: number): number {
  return FACTORIALS[n];
}
