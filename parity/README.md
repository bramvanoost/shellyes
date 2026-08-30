# Cross-engine parity harness

Asserts byte-equivalent state traces between the TypeScript engine
(`src/engine.ts`) and the Swift engine (`ios/ShellYesEngine`).

## Run

From repo root:

    node parity/diff.mjs

## Add a case

Edit `cases.json`. Each case is `{ name, seed, playerIds, actions[] }`.
Actions are `{ type: ROLL | PICK | STOP, face?: 1..6 }`. Coin face is 6.

Run the diff and verify both engines agree before committing the new case.
