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

let failed = 0;
for (const c of cases) {
  const ts = canon(runTs(c).states);
  const sw = canon(runSwift(c).states);
  const tsStr = JSON.stringify(ts);
  const swStr = JSON.stringify(sw);
  if (tsStr === swStr) {
    console.log(`OK   ${c.name}`);
  } else {
    failed++;
    console.error(`FAIL ${c.name}`);
    // Find first divergent state index for a useful error.
    for (let i = 0; i < Math.max(ts.length, sw.length); i++) {
      const a = JSON.stringify(ts[i]);
      const b = JSON.stringify(sw[i]);
      if (a !== b) {
        console.error(`  diverge at state[${i}]:`);
        console.error(`    ts:    ${a}`);
        console.error(`    swift: ${b}`);
        break;
      }
    }
  }
}

if (failed > 0) {
  console.error(`\n${failed}/${cases.length} parity cases failed`);
  process.exit(1);
}
console.log(`\n${cases.length}/${cases.length} parity cases passed`);
