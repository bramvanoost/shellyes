#!/usr/bin/env node
// Reads one parity case as JSON from stdin, emits the trace to stdout.
import { initialState, luckyRng, step } from '../src/engine.js';
import { bustChance, expectedRollGain, keepOptions } from '../src/odds.js';

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function actionFromDto(dto) {
  if (dto.type === 'ROLL') return { type: 'ROLL' };
  if (dto.type === 'STOP') return { type: 'STOP' };
  if (dto.type === 'PICK') return { type: 'PICK', face: dto.face };
  if (dto.type === 'BANK') return { type: 'BANK', target: dto.target };
  throw new Error(`unknown action type ${dto.type}`);
}

// Probabilities are compared as scaled integers. Each engine formats
// doubles its own way in JSON, so nine decimal places of a fixed-point
// integer is the only shape both can agree on byte for byte.
const SCALE = 1e9;
const fixed = (x) => Math.round(x * SCALE);

function oddsFor(state, luck) {
  return {
    bust: fixed(bustChance(state.pickedFaces, state.diceInHand, luck)),
    ev: fixed(expectedRollGain(state.pickedFaces, state.diceInHand, luck)),
    keeps: keepOptions(state, luck).map((k) => ({
      face: k.face,
      count: k.count,
      gain: k.gain,
      diceLeft: k.diceLeft,
      bust: fixed(k.bustChance),
      ev: fixed(k.expectedRollGain),
      pearl: k.securesPearl,
    })),
  };
}

const raw = await new Promise((resolve) => {
  let buf = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => (buf += chunk));
  process.stdin.on('end', () => resolve(buf));
});
const testCase = JSON.parse(raw);
// A case may bend the dice, which is the app's Easy handicap. Both
// the rolls and the odds read off them have to answer to it, or the
// harness would be proving parity of a game nobody plays.
const luck = testCase.luck ?? 0;
const rng = luckyRng(mulberry32(testCase.seed), luck);
let state = initialState(testCase.playerIds);
const states = [state];
for (const dto of testCase.actions) {
  state = step(state, actionFromDto(dto), rng);
  states.push(state);
}
process.stdout.write(
  JSON.stringify({ states, odds: states.map((s) => oddsFor(s, luck)) }),
);
