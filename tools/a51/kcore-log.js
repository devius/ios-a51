#!/usr/bin/env node
/*
 * Fallback log extractor for TWRP kernels that block /dev/mem.
 *
 * /proc/kcore exposes physical memory through ELF LOAD segments whose p_paddr
 * is the physical address, so we can seek straight to the surviving Samsung
 * log regions without any device-side tooling beyond dd.
 *
 *   node kcore-log.js <outdir> [adb.exe]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const adb = process.argv[3] || 'E:\\platform-tools-latest-windows\\platform-tools\\adb.exe';
const out = process.argv[2] || '.';
const tmp = path.join(out, 'kcore-head.bin');

const regions = [
  { name: 'sec_avc_log',    pa: 0x91202000n },
  { name: 'sec_disp_log',   pa: 0x91286000n },
  { name: 'sec_debug_next', pa: 0x91388000n },
  { name: 'ess_setup',      pa: 0xf9000000n },
];

function shellDump(cmd, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  execSync(`"${adb}" exec-out "${cmd}" > "${dest}" 2>nul`, { stdio: 'ignore', shell: 'cmd.exe' });
  return fs.existsSync(dest) ? fs.statSync(dest).size : 0;
}

if (shellDump('dd if=/proc/kcore bs=4096 count=2 2>/dev/null', tmp) < 64) {
  console.log('kcore-log: cannot read /proc/kcore');
  process.exit(1);
}
const hdr = fs.readFileSync(tmp);
if (hdr.readUInt32LE(0) !== 0x464c457f) {
  console.log('kcore-log: /proc/kcore is not an ELF');
  process.exit(1);
}
const phoff = Number(hdr.readBigUInt64LE(0x20));
const phentsize = hdr.readUInt16LE(0x36);
const phnum = hdr.readUInt16LE(0x38);
console.log(`kcore-log: ELF64, ${phnum} program headers, phoff=${phoff}, phentsize=${phentsize}`);

const need = phoff + phnum * phentsize;
if (need > hdr.length) {
  const blocks = Math.ceil(need / 4096) + 1;
  shellDump(`dd if=/proc/kcore bs=4096 count=${blocks} 2>/dev/null`, tmp);
}
const full = fs.readFileSync(tmp);

const segs = [];
for (let i = 0; i < phnum; i++) {
  const o = phoff + i * phentsize;
  if (o + phentsize > full.length) break;
  const type = full.readUInt32LE(o);
  if (type !== 1) continue; // PT_LOAD
  segs.push({
    paddr: full.readBigUInt64LE(o + 24),
    memsz: full.readBigUInt64LE(o + 40),
    offset: full.readBigUInt64LE(o + 8),
    vaddr: full.readBigUInt64LE(o + 16),
  });
}
console.log(`kcore-log: ${segs.length} LOAD segments`);
for (const s of segs) {
  console.log(`  pa=0x${s.paddr.toString(16)} size=0x${s.memsz.toString(16)} off=0x${s.offset.toString(16)}`);
}

let found = 0;
for (const r of regions) {
  const seg = segs.find((s) => r.pa >= s.paddr && r.pa < s.paddr + s.memsz);
  const dst = path.join(out, r.name + '.bin');
  if (fs.existsSync(dst) && fs.statSync(dst).size >= 24) continue;
  if (!seg) { console.log(`  ${r.name}: no kcore segment covers 0x${r.pa.toString(16)}`); continue; }
  const fileOff = Number(seg.offset + (r.pa - seg.paddr));
  if (fileOff % 4096 !== 0) { console.log(`  ${r.name}: unaligned file offset ${fileOff}`); continue; }
  const skip = fileOff / 4096;
  const n = shellDump(`dd if=/proc/kcore bs=4096 skip=${skip} count=1 2>/dev/null`, dst);
  console.log(`  ${r.name}: read ${n} bytes from kcore skip=${skip}`);
  if (n >= 24) found++;
}

if (!found) {
  console.log('kcore-log: no region readable');
  process.exit(1);
}
const decoder = path.join(__dirname, 'decode-log.js');
execSync(`"${process.execPath}" "${decoder}" "${out}"`, { stdio: 'inherit' });
