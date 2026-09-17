# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CHING

A push-your-luck dice game. Collect coins, bank them as tiles, steal rivals' tiles when you hit their exact number. Get greedy and bust, you lose a tile. 80s/8-bit terminal aesthetic. Signature payoff sound: ka-ching. (Mechanics inspired by Regenwormen/Heckmeck, reskinned, original name + theme.)

## Architecture (do NOT violate)

- `src/engine.ts` is PURE: `(state, action, rng) => newState`. No I/O, no rendering, no `Date.now`/`Math.random` inside, all randomness via the injected `rng`. This is what keeps multiplayer + mobile a port, not a rewrite.
- `src/odds.ts` is PURE and depends only on engine types. Exact probabilities for explanation mode (bust chance, expected value of a roll, per-keep comparison). Mirrored in `ios/ShellYesEngine/Sources/ShellYesEngine/Odds.swift`, and the parity harness compares both engines' odds alongside their state traces — change one, change both.
- `src/ai.ts` depends ONLY on engine. Decides PICK + STOP/ROLL. Difficulty via a single `discipline` knob (0 = greedy, 1 = cautious). No I/O.
- `src/cli.ts` is a SWAPPABLE renderer (ANSI/terminal). A future web/mobile shell imports the SAME engine + ai. Never put game rules in the renderer.
- Dice rolls are the only randomness and MUST flow through injected `rng` so a server can own them (fair, cheat-proof) in multiplayer.

## Domain language

- `coins` = the collectible (face value 1-5; the COIN face = 5)
- `tiles` = banked stacks worth 1-4 coins, numbered 21-36
- "ching" = successful bank | "bust" = greedy fail, return top tile AND burn the highest remaining center tile (Heckmeck-style depletion, prevents stalemates)
- "steal" = land on a rival's exact top-tile number, take it

## Commands

- `npm run play` — play in terminal vs AI (`-- --discipline=0.x` to tune)
- `npm test` — engine + AI tests (vitest)
- `npm run sim` — 200-game AI-vs-AI regression

## Definition of done (verify, don't assume)

- `npm test` green.
- Regression: 200-game AI-vs-AI sim terminates cleanly AND higher discipline beats lower discipline over the sample (proves AI tiers aren't cosmetic).
- `npm run sim:difficulty` also covers `Difficulty.luck`. Bending the player's dice moves the ladder as surely as moving a seat does, so tune the two together and read the number.
- `npm run sim:difficulty` green if you touched `Difficulty.seatDiscipline`, the AI, or anything that moves scoring. Proves each tier is harder than the one below it at every player skill. The two-seat regression above structurally cannot catch this — see the Easy-was-harder note below.
- No `Math.random`/`Date` references inside `engine.ts`, `ai.ts` or `odds.ts`.
- `node parity/diff.mjs` green (needs `swift build --package-path ios/ShellYesEngine --product shellyes-parity` first).
- iOS: `xcodebuild test -scheme ShellYes -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ShellYesTests`.

## Non-obvious decisions (read before relitigating)

### `discipline` is inverted from "risk"
Higher discipline = harder AI = stops earlier and banks any reachable tile. Lower discipline = greedy, holds out for 4-coin tiles, busts trying. In CHING (with the burn-on-bust rule), banking reliably accumulates more total coins than chasing 33-36. Empirically: discipline 0.8 beats 0.2 over 200 games (~104 vs 81). The knob name reads slightly inverted on purpose; do not rename back to "risk" without reversing the semantics.

### AI strength is NOT monotone in discipline at three seats
The line above holds head to head. At the app's three-seat table it does not: holding out for big shells pays when there are two rivals to steal from, so the middle ambition band outscores the top one. 1.2 shipped an Easy whose second AI seat was *stronger* than Normal's because of this — Easy won 38.2% against Normal's 39.7% over 20,000 games.

Two consequences. Ambition is quantised — `round(4 - discipline * 3.5)` gives three bands (≤0.357, ≤0.786, above), so small nudges often change nothing at all. And "lower discipline" cannot be assumed to mean "weaker opponent". Tune `Difficulty.seatDiscipline` with `npm run sim:difficulty` and read the number; do not reason about it.

### `discipline` is signed, and Easy lives below zero
Documented 0..1, clamped by neither engine. Below 0 only `bustCeiling = 0.75 - discipline * 0.6` keeps moving, rising until it passes 1.0 at about -0.417, where the AI stops bailing on risk entirely; the ambition term saturates at once because `min(ceiling, ...)` caps it. Both seats at 0.00 — the floor of the documented range — gave Easy only 58.6%, which played as a coin flip, so 1.4 moved Easy to -0.20 for 65.2%. Bust probability is `(pickedFaces / 6) ^ diceInHand`, a discrete set, so the lever is stepped: 0.00, -0.20 and -0.417 are the only distinct settings below zero, and anything in between changes nothing. `sim/difficulty.ts` now enforces an absolute floor for Easy as well as monotonicity — a ladder can be perfectly monotone and still open on a tier nobody would call easy.

`pickFace` ignores discipline entirely, so every tier picks dice identically and the whole ladder rides on stop/roll. That is the strongest untapped lever if Easy ever needs to go further: making Easy take the least valuable face measures at ~90% and is far too weak, but it shows the range.

### Easy bends the player's dice, and the odds know it

Difficulty used to live entirely in `ai.ts`: same dice for everybody,
only the AI's stop/roll rule moved. Easy bought its whole win rate by
making the bots greedy (-0.20 a seat), and greedy bots fail **56% of
their turns** — a table of opponents busting every other turn reads as
broken rather than as easy. Bram played 1.6 and said so.

So Easy now sits at 0.00 a seat, where bots fail 49%, and the
difference is paid back to the player as dice: `luckyRng` in
`engine.ts` moves `luck` of the probability mass off the 1 and onto the
coin, for the human seat only. At Easy's 0.05 the coin comes up 21.7%
of the time instead of 16.7%. Measured 62.6% player wins at middling
skill, monotone at every skill.

Three rules around it:

- **`odds.ts` takes the same `luck`.** `bustChance`, `expectedRollGain`
  and `keepOptions` all report what a bent die actually does. A
  handicap the explanation screen cannot see would make every figure it
  prints a lie, and that is the line this feature does not cross.
- **`bustChance` takes faces, not a count.** A bent die is not bent
  evenly, so *which* faces are spent decides the danger: spending the
  coin costs more than spending the 1.
- **Only Easy gets any.** Normal and Hard roll fair dice, so a score on
  those boards means what it always did.

One consequence to hold in mind: the Easy leaderboards now mix scores
rolled on fair dice (1.6 and earlier) with scores rolled on bent ones.
The weekly Easy board heals itself every Monday. The all-time Easy
board never resets, so its old entries are held to a slightly harder
game than new ones — a known, accepted unfairness, not an oversight.

`luckyRng` lives next to `rollDie` because it is the one place that
knows which slice of the injected `rng`'s range maps to which face. A
wrapper written anywhere else would be guessing at that mapping. It
spends exactly one draw per die, so a seed still replays a game step
for step and `parity/cases.json` can hold both engines to the same bent
sequence.

### Bust burns the highest center tile (Heckmeck flip)
"Return your top tile" alone caused 153/200 sim games to stalemate, tiles cycling in and out of the center forever. The burn rule is what makes the supply monotonically deplete. Do not remove it unless you add another depletion mechanism, and update CLAUDE.md if you do.

### Banking with both steal and center available is a player choice
When the active player's sum could either steal a rival's top tile OR take a tile from the supply, the engine parks in a new `chooseBank` phase and waits for a `BANK` action. This is the Heckmeck rule (stealing is always optional) and replaces the older "steal takes priority over center" behavior, which silently denied players game-ending plays (e.g. banking sum 26 with [25] on the beach and a rival holding 26: the old engine forced the steal and the game dragged on; the new engine lets the player end it). When only one option exists, the engine still auto-commits to keep the rhythm of the common case. AI policy: prefer a game-ending center pick (`centerTiles.count == 1`), otherwise prefer steal to keep the sim baseline close to the pre-change numbers.

### CLI must fit the terminal frame
Renderer uses the alternate screen buffer (`\x1b[?1049h`/`l`) and writes a fixed 22-row frame: header(4) + center(6) + vaults(5) + turn(6) + footer(1). NEVER append after `render()` returns. Status/prompt/AI-thinking lines must go through `opts.footer` so they're part of the same cleared frame. The flash banner overwrites the footer row via `\r`, not new lines. Past 22 rows the screen scrolls and you see stale frames stacking.

### Glyph vocabulary
- `◆` filled diamond = gem, on-tile collectible visual, gradient-coloured for glint
- `◇` hollow diamond = empty / dimmed / tie heading
- `$` = coin face on a die (face value 5)
- `◐◓◑◒` = spinning frames for a coin during roll reveal
- Renderer labels say "vault" for a player's banked pile (panel is `VAULTS`, not `PLAYERS`).

## Roadmap (build order)

1. Solo vs AI + local pass-and-play (free multiplayer, no backend).
2. Same engine on a server (PartyKit/Colyseus or a Pi over ssh). Server owns RNG. Disconnect -> AI takes the seat.
3. Android. A third engine (Kotlin) joining `parity/`, not a rewrite -- this is what engine purity was for. Decide the shell separately from the engine: native Compose, or reuse `src/engine.ts` through a JS runtime. Cross-play needs step 2 first, which is why it sits here.
4. Accounts/leaderboards only if retention justifies it.

## Conventions

- TypeScript strict, no `any` in engine/ai.
- Engine stays framework-free and dependency-free.
- Commits imperative mood, <=72 chars.
