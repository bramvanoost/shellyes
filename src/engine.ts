// CHING engine. Pure reducer: (state, action, rng) => newState.
// No I/O. No Math.random/Date. All randomness flows through the injected rng.

export type Face = 1 | 2 | 3 | 4 | 5 | 6;
export const COIN: Face = 6;
export const TOTAL_DICE = 8;

export type Player = {
  id: string;
  tiles: number[];
};

export type Phase = 'roll' | 'pick' | 'chooseBank' | 'over';

export type State = {
  players: Player[];
  current: number;
  centerTiles: number[];
  diceInHand: number;
  rolled: Face[];
  setAside: Face[];
  pickedFaces: Face[];
  phase: Phase;
};

// At bank time the player picks one of these. `center` is the highest
// supply tile <= sum (Heckmeck rule, no sub-choice within the supply).
// `steal` is a rival's top tile whose value exactly equals sum.
export type BankOption =
  | { kind: 'center'; tile: number }
  | { kind: 'steal'; playerIndex: number; tile: number };

export type Action =
  | { type: 'ROLL' }
  | { type: 'PICK'; face: Face }
  | { type: 'STOP' }
  | { type: 'BANK'; target: BankOption };

export type Rng = () => number;

const ALL_FACES: readonly Face[] = [1, 2, 3, 4, 5, 6];

export function faceValue(f: Face): number {
  return f === COIN ? 5 : f;
}

export function tileCoins(tile: number): number {
  if (tile <= 24) return 1;
  if (tile <= 28) return 2;
  if (tile <= 32) return 3;
  return 4;
}

export function score(state: State): number[] {
  return state.players.map((p) => p.tiles.reduce((s, t) => s + tileCoins(t), 0));
}

export function initialState(playerIds: string[]): State {
  return {
    players: playerIds.map((id) => ({ id, tiles: [] })),
    current: 0,
    centerTiles: Array.from({ length: 16 }, (_, i) => 21 + i),
    diceInHand: TOTAL_DICE,
    rolled: [],
    setAside: [],
    pickedFaces: [],
    phase: 'roll',
  };
}

export function step(state: State, action: Action, rng: Rng): State {
  if (state.phase === 'over') return state;
  switch (action.type) {
    case 'ROLL':
      return doRoll(state, rng);
    case 'PICK':
      return doPick(state, action.face);
    case 'STOP':
      return doStop(state);
    case 'BANK':
      return doBank(state, action.target);
  }
}

// Enumerates every legal bank commitment from the current set-aside sum:
// each rival whose top tile matches exactly, plus the highest supply tile
// <= sum if one exists. Returns [] when banking would bust (no coin or
// no qualifying tile anywhere). Renderers should call this in the
// `chooseBank` phase to present the player's options.
export function bankOptions(state: State): BankOption[] {
  const sum = state.setAside.reduce((acc, f) => acc + faceValue(f), 0);
  if (!state.setAside.includes(COIN)) return [];
  const options: BankOption[] = [];
  for (let i = 0; i < state.players.length; i++) {
    if (i === state.current) continue;
    const tiles = state.players[i].tiles;
    if (tiles.length > 0 && tiles[tiles.length - 1] === sum) {
      options.push({ kind: 'steal', playerIndex: i, tile: sum });
    }
  }
  const eligible = state.centerTiles.filter((t) => t <= sum);
  if (eligible.length > 0) {
    options.push({ kind: 'center', tile: Math.max(...eligible) });
  }
  return options;
}

/// Most a die may be bent. `luck` is shared out over the three high
/// faces and taken from the three low ones, so at `0.5` the 1, 2 and 3
/// never come up at all — which is a different game rather than a
/// kinder one.
export const MAX_LUCK = 0.5;

/// How often each face comes up, lowest first, on a die bent by
/// `luck`.
///
/// The bonus is spread over the three high faces and paid for by the
/// three low ones: each of 4, 5 and the coin gains `luck / 3`, each of
/// 1, 2 and 3 loses the same. At Easy's 0.05 that is a face going from
/// 16.7% to 18.3%, three times over.
///
/// It was briefly the coin alone, which measured the same strength to
/// within a point but is a different thing to play: a coin faucet
/// rather than kinder dice. It also had a perverse edge — an inflated
/// coin is a bigger dead face once you keep it, so every roll after
/// the coin got deadlier.
export function faceWeights(luck: number = 0): number[] {
  const moved = Math.max(0, Math.min(luck, MAX_LUCK)) / 3;
  const sixth = 1 / 6;
  return [
    sixth - moved,
    sixth - moved,
    sixth - moved,
    sixth + moved,
    sixth + moved,
    sixth + moved,
  ];
}

/// Chance one die shows `face`, given how far it is bent. Fair dice
/// (`luck` 0) give every face `1/6`.
export function faceChance(face: Face, luck: number = 0): number {
  return faceWeights(luck)[face - 1];
}

/// A die bent toward the high faces. `luck` is the total probability
/// mass moved; see `faceWeights` for where it goes.
///
/// This is the app's Easy handicap, and it is the ONLY sanctioned way
/// to bend a roll. It lives here, next to `rollDie`, because it is the
/// one place that knows which slice of the injected `rng`'s range maps
/// to which face — a wrapper written anywhere else would be guessing
/// at that mapping and would break silently if `rollDie` changed.
///
/// The remap is an inverse CDF: find which face `u` falls on under the
/// bent distribution, then return a number inside *that* face's own
/// fair slice. Exactly one draw from `base` per die, same as a fair
/// roll, so a seed still replays a game step for step and the parity
/// harness can hold both engines to the same sequence. At `luck` 0 the
/// bent slices are the fair ones and every draw passes through
/// untouched.
///
/// The odds the app quotes are not left behind: `bustChance`,
/// `expectedRollGain` and `keepOptions` in `odds.ts` all take the same
/// `luck` and report what a bent die actually does. A handicap the
/// explanation screen doesn't know about would make every number it
/// prints a lie.
export function luckyRng(base: Rng, luck: number): Rng {
  const moved = Math.max(0, Math.min(luck, MAX_LUCK));
  if (moved === 0) return base;
  const weights = faceWeights(moved);
  const cumulative: number[] = [];
  let acc = 0;
  for (const w of weights) {
    acc += w;
    cumulative.push(acc);
  }
  return () => {
    const u = base();
    let i = 0;
    while (i < 5 && u >= cumulative[i]) i++;
    const low = i === 0 ? 0 : cumulative[i - 1];
    // Clamped just under 1 so the result can never round up into the
    // next face's slice. The literal is spelled the same in both
    // engines; the bias it introduces is a part in a trillion.
    const within = Math.min((u - low) / weights[i], 0.999999999999);
    return (i + within) / 6;
  };
}

function rollDie(rng: Rng): Face {
  const n = Math.floor(rng() * 6) + 1;
  return Math.min(6, Math.max(1, n)) as Face;
}

function doRoll(state: State, rng: Rng): State {
  if (state.phase !== 'roll') return state;
  if (state.diceInHand === 0) return state;
  const rolled: Face[] = Array.from({ length: state.diceInHand }, () => rollDie(rng));
  const hasNewFace = rolled.some((f) => !state.pickedFaces.includes(f));
  if (!hasNewFace) {
    return bust(state);
  }
  return { ...state, rolled, phase: 'pick' };
}

function doPick(state: State, face: Face): State {
  if (state.phase !== 'pick') return state;
  if (state.pickedFaces.includes(face)) return state;
  const taken = state.rolled.filter((f) => f === face);
  if (taken.length === 0) return state;
  const next: State = {
    ...state,
    setAside: [...state.setAside, ...taken],
    pickedFaces: [...state.pickedFaces, face],
    diceInHand: state.diceInHand - taken.length,
    rolled: [],
    phase: 'roll',
  };
  // If you've used all 8 dice, you must stop and try to bank.
  if (next.diceInHand === 0) {
    return tryBank(next);
  }
  return next;
}

function doStop(state: State): State {
  if (state.phase !== 'roll') return state;
  if (state.setAside.length === 0) return state;
  return tryBank(state);
}

function tryBank(state: State): State {
  if (!state.setAside.includes(COIN)) return bust(state);
  const options = bankOptions(state);
  if (options.length === 0) return bust(state);
  // Single option = no choice to make, commit immediately. Multiple options
  // park in `chooseBank` and wait for the player's BANK action. This is
  // the Heckmeck rule: stealing is always optional.
  if (options.length === 1) return commitBank(state, options[0]);
  return { ...state, phase: 'chooseBank' };
}

function commitBank(state: State, target: BankOption): State {
  if (target.kind === 'steal') {
    const players = state.players.map((p, idx) => {
      if (idx === target.playerIndex) return { ...p, tiles: p.tiles.slice(0, -1) };
      if (idx === state.current) return { ...p, tiles: [...p.tiles, target.tile] };
      return p;
    });
    return endTurn({ ...state, players });
  }
  const centerTiles = state.centerTiles.filter((t) => t !== target.tile);
  const players = state.players.map((p, i) =>
    i === state.current ? { ...p, tiles: [...p.tiles, target.tile] } : p,
  );
  return endTurn({ ...state, players, centerTiles });
}

function doBank(state: State, target: BankOption): State {
  if (state.phase !== 'chooseBank') return state;
  const valid = bankOptions(state).find(
    (o) =>
      o.kind === target.kind &&
      o.tile === target.tile &&
      (o.kind === 'center' || o.playerIndex === (target as { playerIndex: number }).playerIndex),
  );
  if (!valid) return state;
  return commitBank(state, valid);
}

function bust(state: State): State {
  let players = state.players;
  let centerTiles = state.centerTiles;
  const me = state.players[state.current];
  if (me.tiles.length > 0) {
    const top = me.tiles[me.tiles.length - 1];
    players = state.players.map((p, i) =>
      i === state.current ? { ...p, tiles: p.tiles.slice(0, -1) } : p,
    );
    centerTiles = [...centerTiles, top].sort((a, b) => a - b);
  }
  // Burn the highest remaining center tile so the supply depletes.
  if (centerTiles.length > 0) {
    centerTiles = centerTiles.slice(0, -1);
  }
  return endTurn({ ...state, players, centerTiles });
}

function endTurn(state: State): State {
  if (state.centerTiles.length === 0) {
    return { ...state, phase: 'over', rolled: [], setAside: [], pickedFaces: [], diceInHand: 0 };
  }
  return {
    ...state,
    current: (state.current + 1) % state.players.length,
    diceInHand: TOTAL_DICE,
    rolled: [],
    setAside: [],
    pickedFaces: [],
    phase: 'roll',
  };
}

// Exhaustiveness aid for ai.ts.
export const FACES = ALL_FACES;
