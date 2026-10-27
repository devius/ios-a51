#!/usr/bin/env node
/* Decode A51 shim log records dumped from the surviving Samsung RAM regions. */
'use strict';
const fs = require('fs');
const path = require('path');

const dir = process.argv[2] || '.';
const names = ['sec_avc_log', 'sec_disp_log', 'sec_debug_next', 'ess_setup'];
const labels = {
  0: 'signature', 1: 'CurrentEL', 2: 'SCTLR_EL1', 3: 'FDT PA', 4: 'image PA',
  5: 'MPIDR_EL1', 6: 'CNTFRQ_EL0', 7: 'CNTPCT_EL0', 8: 'ID_AA64MMFR0_EL1',
  9: 'GICD_TYPER', 10: 'UFS version', 11: 'DECON GLOBAL_CONTROL',
  12: 'DECON SHADOW_REQ', 13: 'DECON HW_SW_TRIG_CONTROL', 14: 'DECON HW_TE_CNT',
  15: 'DSIM STATUS', 16: 'DPP0 IDMA IN_BASE_ADDR_Y', 17: 'DPP0 IDMA SRC_SIZE',
  18: 'DPP0 IDMA ENABLE', 19: 'framebuffer PA', 20: 'stage', 21: 'loops',
  22: 'loops/s x100', 23: 'run counter',
};

let any = false;
for (const name of names) {
  const file = path.join(dir, name + '.bin');
  if (!fs.existsSync(file)) continue;
  const buf = fs.readFileSync(file);
  if (buf.length < 24) continue;
  const sig = buf.subarray(0, 8).toString('latin1').replace(/\0+$/, '');
  const isOurs = buf.readBigUInt64LE(0) === 0x314d494853313541n;
  console.log(`\n=== ${name} (${buf.length} bytes) signature=${JSON.stringify(sig)} ${isOurs ? '[A51 shim]' : '[not ours]'}`);
  if (!isOurs) continue;
  any = true;
  for (let i = 0; i < 24; i++) {
    if (i * 8 + 8 > buf.length) break;
    const v = buf.readBigUInt64LE(i * 8);
    if (v === 0n && i !== 0) continue;
    const hex = '0x' + v.toString(16).padStart(16, '0');
    console.log(`  [${String(i).padStart(2)}] ${labels[i].padEnd(26)} ${hex}  (${v})`);
  }
  const stage = Number(buf.readBigUInt64LE(20 * 8));
  const stageText = {
    1: 'entered main, record written',
    2: 'painted framebuffer, trigger kicked',
    3: '15 s loop finished, asking bootloader for recovery',
    4: 'PMU recovery reset attempted, trying PSCI',
    5: 'all resets failed, halted',
  }[stage] || 'unknown';
  console.log(`  stage: ${stage} (${stageText})`);
}
if (!any) console.log('\nNo A51 shim record found. Either the shim never ran, or /dev/mem is restricted in this TWRP.');
