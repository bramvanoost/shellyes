# 1.3 — Difficulty retune, quit penalty, rank fallback — 2026-09-15

Scope: iOS app (`ios/ShellYes/ShellYes/*.swift`) plus a new tuning sim
(`sim/difficulty.ts`). Six fixes off a play-test triage. No engine or
rules changes — `src/engine.ts`, `src/ai.ts` and both Swift engine
mirrors are untouched, and parity still passes 4/4.

## Easy was harder than Normal

`Difficulty.modifier` shifted both AI seats by ±0.15 off one base. That
model could not work. The AI derives ambition from
`round(4 - discipline * 3.5)`, which quantises the knob into three
bands, so a ±0.15 nudge usually lands inside one band and changes
nothing at all.

Worse, strength is not monotone in discipline at a three-seat table:
holding out for big shells pays when there are two rivals to steal
from, so the middle band outscores the top one. Easy's second seat sat
at 0.70 and Normal's at 0.85, which made **Easy's opponent the stronger
of the two**. Measured over 20,000 games: Easy won 38.2% against
Normal's 39.7%.

Replaced with a per-seat table per difficulty, tuned to roughly
60/50/40 and verified monotone at low, mid and high player skill rather
than at one assumed skill.

| difficulty | seats | human win rate (mid skill) |
|---|---|---|
| easy | `[0.00, 0.00]` | 59.4% |
| normal | `[0.20, 0.00]` | 51.7% |
| hard | `[0.20, 0.50]` | 41.0% |

Dice are unchanged and identical across difficulties. Difficulty has
never moved the odds of a roll, only how the AI plays one.

New `npm run sim:difficulty` is the harness. It fails the build if any
tier stops being harder than the one below it, at any skill — the check
the two-seat `npm run sim` structurally could not make.

## Quitting a bad game is no longer free

`recordGameOver` only fired when the engine reached `.over`, and
nothing about a game survived a launch. Force-quitting a game you were
losing left `winStreak` untouched, which is exactly what the best-streak
boards measure; the weekly score board sums a player's best three
games, so quitting the bad ones kept that pool clean too.

New `AbandonGuard` persists a flag once a game has actually been played
into — dealing one and backing out still costs nothing. A game found
still armed at launch is filed as a loss before anything reads the
stats. Walking out through Home or New Game is charged the same way, at
the moment it happens.

An abandoned game counts as a game played and breaks the streak. It
does not touch best score, the best-runs archive, or the weekly pool.

Win rates on the dashboard will fall for everybody at the 1.3 boundary.
The denominator grew and the numerator did not; that is the fix working.

## A bust gave itself away before the dice landed

Four pieces of state were already frozen during the post-bust fake roll.
The player's own vault was not — so the shell a bust costs vanished off
their stack a full second before the banner said why. Frozen alongside
the rest.

Same window, second leak: a bust that emptied the beach presented the
tally screen immediately, because the cover was gated on `bustFlash`,
which is not raised until after the roll finishes. Now gated on the
roll as well.

## Ranks on the home screen

Two bugs, one symptom.

The splash asked for ranks from its `.task`, which on a cold launch runs
while Game Center is still deciding who the player is. `loadStandings`
returned nothing on its auth guard and nothing ever asked again, so a
signed-in player saw no rank until they backgrounded the app and came
back. Ranks now also refresh when auth lands — the same hook the
achievement backfill already used.

And the splash only ever showed *weekly* ranks. Weekly boards are
deliberately never backfilled, so a player with years of history and no
game yet this week had nothing to show. All-time ranks now stand in
until a weekly one exists; the held-number-one crown is not printed
twice when they do.

## Achievements recovered from stored runs

The one-time catch-up granted the seven achievements derivable from
lifetime totals. `bestRuns` also keeps each run's difficulty, score and
result, so `hard.win` and `squeaker` are recoverable too, and now are.

Guarded by its own key rather than a cleared old one — reusing
`didBackfill` would have meant the two new achievements never reached a
single existing player, which is the entire group the backfill is for.
Score submissions are not repeated.

The remaining five (`clean.win`, `last.shell`, `steal.3`, `bust.3`,
`bookends`) turn on per-game facts that were never written down. They
stay locked rather than guessed at.

## Share card can be saved

`ShareLink` carried the App Store URL in `message:`, making the payload
image-plus-text — and Photos only offers "Save Image" when every item is
an image. The card also vended only raw PNG `Data`, which reaches the
sheet as a file rather than a picture.

Dropped the message, added an image representation alongside the data
one. The card keeps its own "Shell Yes" and "Free on the App Store!"
art, so discovery is now a name to search rather than a link to tap.
Putting the URL back in `message:` silently removes Save Image again.

---

# 0.7 — Audio, tally polish, settings split — 2026-06-10

Scope: iOS app (`ios/ShellYes/ShellYes/*.swift`). New sound effects,
counting-ceremony audio fix, last-shell copy, pluralization, chrome bar
position, dedicated Statistics pane, settings section type bump.

## Audio

- Counting ceremony tally now plays the full `count.m4a` clip per pearl,
  overlapping naturally instead of the trimmed `count_tick` attack. Pool
  bumped to 16 copies for ~40ms tick spacing without cutoff. Removed
  unused `count_tick.m4a` from the bundle.
- New `aiclaimsshell.m4a` short confirm tone after an AI claims a shell
  from the beach. Fires when the AI loop dispatches a `.took` event, in
  both mid-game and final-shell paths.
- New `playerlosesshell.m4a` sting when an AI steals from the human seat.
  Fires on `.stole` events where `victim == "you"`.

## Banner copy

- Final-shell claim by the human now reads
  `"Shell yes!\nYou claimed the last shell."` — forced break after the
  exclamation, brand voice up front.
- `AIEventBanner` card maxWidth bumped 320 → 360 so titles have more
  room before they wrap.

## Beach copy

- `ShellsGrid` pluralizes: "1 shell on the sand" / "N shells on the sand".

## In-game chrome

- `ChromeBar` (wordmark, debug, gear) nudged down 8pt — `padding(.top)`
  16 → 24 — so the top bar isn't crowding the safe-area edge.

## Settings

- Stats card on Settings trimmed to four headline rows: Games played,
  Wins (w/ %), Win streak (current/best), Best score. The full
  per-difficulty and per-pace breakdowns moved out to a dedicated
  Statistics pane.
- New `StatsView` reachable via a `Statistics →` row in Settings. Four
  cards: Overview, Details (biggest keep, steals, busts, hot face),
  By difficulty, By pace. Route enum gains `.stats`; `ShellYesApp`
  navigation wired.
- Section titles capitalize their first letter and bump from 11pt
  italic / tracking 2 to 15pt italic / tracking 1.5 — closer in
  weight to the row labels they head.
- `SettingsRow` now sets `contentShape(Rectangle())` so the entire row
  is tappable — previously the `Spacer()` gap between label and chevron
  swallowed taps on Home, How to play, About.

---

# Theme & copy refinement — 2026-06-07

Scope: iOS app (`ios/CHING/CHING/*.swift`). Copy, two-noun model, pearl visual,
shell-card tile geometry. No engine, scoring, probability, steal, or stacking
rule changes.

## 1. Two-noun model

| Concept           | Before                | After (UI)         |
|-------------------|-----------------------|--------------------|
| Claimed object    | "tile" / "safe"       | **shell**          |
| Points-token      | gold "coin" pip       | **golden pearl**   |
| Wildcard die face | "coin" face / shell medallion | **pearl** face / Pearl glyph |
| Player total      | "X tiles"             | **X pearls**       |

Engine code keeps `tile` / `safe` identifiers. The model split lives at the UI
layer only: `Player.tiles` still returns the same array, but every user-facing
label that referred to them is now "shell". The points-token visual was a flat
gold dot; it is now a pearlescent golden pearl.

Score display switched from counting **shells** to counting **pearls**. Engine
`score(state)` already returns total worms (= total pearls), so this was a
label change, not a math change.

## 2. Copy swaps (calm tone, no exclamation marks in-game)

| Location                                       | Before                              | After                            |
|------------------------------------------------|-------------------------------------|----------------------------------|
| `SplashView.swift:46`                          | they have shells. … score the shore. | soft maths, golden light.        |
| `SafesGrid.swift:16`                           | tiles left to steal                  | shells on the sand               |
| `GameStore.swift:67-80` phaseHint (your turn) | You're up. Roll the dice.            | no rush. read the tide.          |
| phaseHint (mid-turn)                           | Roll again, or bank.                 | roll on, or keep.                |
| phaseHint (pick)                               | Choose wisely.                       | pick what you'll keep.           |
| phaseHint (game over)                          | Game over.                           | the tide rolls back.             |
| phaseHint (opponent)                           | {name} is thinking…                  | {name} reads the tide…           |
| `GameStore.swift:56-65` bank button (default) | Bank                                 | Keep                             |
| bank button (steal variant)                    | Steal {name}'s tile                  | Take {name}'s shell              |
| `GameView.swift:402` roll button               | Roll / Roll Again                    | Roll On                          |
| `GameView.swift:280` bust headline             | bust.                                | the tide takes.                  |
| `GameView.swift:104-105` bust subline (greedy) | you had no coins and got greedy      | no coin in hand. try again.      |
| bust subline (rolled)                          | the roll gave you nothing            | the tide gave nothing. try again. |
| `GameView.swift:304` burned tile label         | tile burned                          | a shell drifts away              |
| `Scoreboard.swift:49` per-column total         | {n} tile / tiles                     | {n} pearls (or "0 shells" empty) |
| `Scoreboard.swift:83` steal flash              | stolen!                              | taken.                           |
| `CountingCeremony.swift:99` empty vault        | no safes claimed                     | 0 shells                         |
| `CountingCeremony.swift:21-29` winner          | You win. / It's a tie!               | you win. / a tie.                |
| `GameOverSheet.swift` (unused, kept in sync)   | game over. / tie at the top.         | the tide rolls back. / a tie.    |

Kept as-is (already calm or non-user-facing): `ActionBar` "game over",
"waiting…", `DiceStage` "dice ready", "locked".

The "shell yes" wordmark stays untouched on `SplashView` and `ChromeBar` — only
the wordmark keeps that energy; everything else is calm.

## 3. Pearl visual

`DesignSystem.swift`:

- New colors: `pearlHighlight` (cream center), `pearlCore` (mid amber),
  `pearlEdge` (deep amber rim), `pearlGlow` (outer halo).
- New view `Pearl(diameter:)` renders a radial gradient (cream → amber) with a
  diffuse `plusLighter` halo. No metallic hard highlight.
- `CoinPips` renamed to `PearlRow` (same call signature). All five callers
  updated: `VaultStack`, `SafesGrid`, `CountingCeremony.tileChip`,
  `GameView.burnedTileChip`. The end-ceremony big coin glyph now uses `Pearl`
  too (was `coinGlyph`, replaced with `pearlGlyph`).

`Color.gold` is kept — still used by gold dice faces, winner headline, and
sparkle effects (which are not pearls).

## 4. Shell-card tile geometry — Option A confirmed

Decided after browser mockup comparison (`/tmp/shell-stacking-options.html`).

- New `ShellCardShape: InsettableShape` in `DesignSystem.swift`: 5 scalloped
  crown bumps across the top, **straight parallel sides** (required for clean
  vertical stacking per `CLAUDE.md`), centered umbo nub at the bottom.
  Configurable crown / nub ratios.
- Applied wherever a tile is drawn:
  `VaultStack.safeView`, `SafesGrid.cellLayer`, `GameView.burnedTileChip`,
  `CountingCeremony.tileChip`, `Scoreboard.safePlaceholder`,
  `GameOverSheet.miniSafe`.
- Stacking direction in `VaultStack` is unchanged (newest on top, in front,
  5-px layer offset). With shells, each lower shell's 5-px peek below the top
  shell now reads as the umbo nub of the older shell rather than a bare bottom
  edge. Only the top (steal-target) shell renders the value + pearls — same as
  before.

## 5. Reward feedback — hook points + sound manifest

Wired vs. staged:

| Feel target                              | UI / sound trigger              | Wired? |
|------------------------------------------|---------------------------------|--------|
| Good outcome (sparkle + soft chime)      | `DiceStage.handlePick` → `GameSFX.playConfirm()` + `pickSparkleTrigger` | ✅ wired |
| Bank (warm low "tucked away" tone)       | `GameView.act` on vault-grow → `GameSFX.playBank()` + `VaultStack` sparkle | ✅ sound + sparkle wired; "tucked away." text **staged, not wired** (see below) |
| Bust (gentle wash / wave)                | `GameView.triggerBustFlash` → `GameSFX.playBust()` + full-screen flash | ✅ wired |
| Good-grab microcopy variants             | n/a                             | **strings staged, not wired** (see below) |

### Sound manifest

| Filename                                      | Pool size | Trigger                            | Intended mood                                              |
|-----------------------------------------------|-----------|------------------------------------|------------------------------------------------------------|
| `dice_picking.m4a` (+ `_2`)                   | 6         | each roll-anim frame, ~12/s        | soft pebble click; gentle pace, never percussive           |
| `dice_confirm.m4a`                            | 2         | `playConfirm()` on a die pick      | tiny chime / single bell, the "sparkle on the pearl" cue   |
| `outcome-success.m4a`                         | 2         | `playBank()` on a successful bank  | warm low "tucked away" tone; calmer than the pick chime    |
| `outcome-failure.m4a`                         | 2         | `playBust()` on bust               | gentle wash / wave; never a buzzer or descending stinger    |
| `farran_ez-minimal-piano-underscore-…mp3`     | n/a       | `HomeAudio` ambient loop           | unchanged. balearic piano underscore.                       |

All assets exist; no new asset files need to be commissioned for the wired
hooks to work. The user can audit each clip against the mood column above and
swap if any feels off-spec (esp. `outcome-success` — it should be a warmer,
lower tone than the pick chime to read distinct from "good-grab").

### Strings staged but not wired (deliberately out of scope)

These were listed in the spec but no UI element exists yet, and adding one is
feature-scope past "copy + visual-model + geometry only":

- **"tucked away."** — bank confirm banner. Hook point: `GameView.act` line 54
  (where `playBank()` already fires). Pattern to mirror: the bust overlay
  (`GameView` lines 250-317), but smaller / floating / warmer.
- **"nice." / "lovely." / "the tide gives."** — good-grab microcopy variants
  on a die pick. Hook point: `DiceStage.handlePick` line 268. Pattern: brief
  inline flash above the dice-stage sum.

If you want either wired, it's a follow-up of ~40 lines of SwiftUI each.

## 6. Files touched

- `ios/CHING/CHING/DesignSystem.swift` — pearl colors, `Pearl` + `PearlRow`,
  `ShellCardShape`.
- `ios/CHING/CHING/VaultStack.swift` — `ShellCardShape`, `PearlRow`.
- `ios/CHING/CHING/SafesGrid.swift` — header copy, `ShellCardShape`, `PearlRow`.
- `ios/CHING/CHING/GameStore.swift` — `bankActionLabel`, `phaseHint`.
- `ios/CHING/CHING/GameView.swift` — Roll button copy, bust headline + subline,
  burned-tile label, `burnedTileChip` shape + `PearlRow`.
- `ios/CHING/CHING/Scoreboard.swift` — score label, stolen flash, placeholder.
- `ios/CHING/CHING/CountingCeremony.swift` — empty-vault label, winner copy,
  `tileChip` shape, `coinGlyph` → `pearlGlyph`, `PearlRow`.
- `ios/CHING/CHING/SplashView.swift` — tagline.
- `ios/CHING/CHING/GameOverSheet.swift` — currently unused, updated for
  consistency in case it's re-wired later (`ShellCardShape`, calm copy).

## 7. Engine — explicit confirmation

**No engine changes.** No file under `src/` or `ios/CHINGEngine/` was touched.

- `npm test` — 107/107 pass.
- `xcodebuild … build` — succeeds.
- Tile values 21-36 → pearl counts 1/2/3/4: unchanged (engine `tileCoins`).
- Steal rule (exact match on rival's top shell): unchanged.
- Stacking rule (newest on top, top is steal target): unchanged.
- Burn-on-bust rule: unchanged.

## 8. Skipped / out of scope

- Terminal renderer (`src/cli.ts`, `src/render.ts`) and CLI README: unchanged.
  CLAUDE.md notes the terminal keeps the 80s/8-bit aesthetic separately. The
  theme refinement target was the iOS app's balearic vibe.
- `package.json` name `"ching"`, repo name, `~/.ching/session.json` paths:
  outside this pass; belongs to the broader `shell-yes-rebrand` work.
- No new string catalog / `Localizable.strings` introduced. Strings stay
  inline, matching the existing codebase convention.
