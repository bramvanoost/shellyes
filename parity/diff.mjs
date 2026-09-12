#!/usr/bin/env node
// Runs both engines on each case in cases.json. Asserts equal traces.

import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = dirname(__dirname);
const cases = JSON.parse(readFileSync(join(__dirname, 'cases.json'), 'utf8'));

const swiftCli = join(
  repoRoot,
  'ios/ShellYesEngine/.build/debug/shellyes-parity'
);

function runTs(c) {
  const r = spawnSync('npx', ['tsx', join(__dirname, 'run-ts.mjs')], {
    input: JSON.stringify(c),
    encoding: 'utf8',
    cwd: repoRoot,
  });
  if (r.status !== 0) throw new Error(`ts runner failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

function runSwift(c) {
  const r = spawnSync(swiftCli, [], { input: JSON.stringify(c), encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`swift runner failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

// Normalize: the two engines may emit fields in different orders.
// Stringify with sorted keys for stable comparison.
function canon(obj) {
  if (Array.isArray(obj)) return obj.map(canon);
  if (obj && typeof obj === 'object') {
    const out = {};
    for (const k of Object.keys(obj).sort()) out[k] = canon(obj[k]);
    return out;
  }
  return obj;
}

// Each runner emits `states` and the `odds` read off each of them.
// Both are compared: a state trace can agree while the probabilities
// explanation mode quotes drift apart, and that divergence would only
// ever show up on a player's screen.
const TRACKS = ['states', 'odds'];

let failed = 0;
for (const c of cases) {
  const ts = runTs(c);
  const sw = runSwift(c);
  const divergence = TRACKS.map((track) => {
    const a = canon(ts[track] ?? []);
    const b = canon(sw[track] ?? []);
    if (JSON.stringify(a) === JSON.stringify(b)) return null;
    // Find first divergent index for a useful error.
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
      const x = JSON.stringify(a[i]);
      const y = JSON.stringify(b[i]);
      if (x !== y) return { track, index: i, ts: x, swift: y };
    }
    return { track, index: -1, ts: '(length)', swift: '(length)' };
  }).filter(Boolean);

  if (divergence.length === 0) {
    console.log(`OK   ${c.name}`);
  } else {
    failed++;
    console.error(`FAIL ${c.name}`);
    for (const d of divergence) {
      console.error(`  diverge at ${d.track}[${d.index}]:`);
      console.error(`    ts:    ${d.ts}`);
      console.error(`    swift: ${d.swift}`);
    }
  }
}

if (failed > 0) {
  console.error(`\n${failed}/${cases.length} parity cases failed`);
  process.exit(1);
}
console.log(`\n${cases.length}/${cases.length} parity cases passed`);
