#!/usr/bin/env node
/*
 * A51 boot image surgical repacker.
 *
 * Parses an Android boot image (v0/v1/v2), replaces only the kernel payload,
 * keeps the header, ramdisk, second stage, recovery_dtbo, DTB and trailing
 * bytes byte-for-byte, and re-pages the file. The kernel is gzip-compressed
 * when the stock kernel is gzip-compressed, so S-Boot's decompressor sees the
 * same format it expects.
 *
 * Usage:
 *   node mkboot.js --list  --stock stock-boot.img
 *   node mkboot.js --stock stock-boot.img --kernel loader.bin --out boot-a51-test1.img
 */
'use strict';

const fs = require('fs');
const zlib = require('zlib');

function fail(msg) {
  console.error('mkboot: ' + msg);
  process.exit(1);
}

function parseArgs(argv) {
  const out = { list: false, force: 'auto' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--list') out.list = true;
    else if (a === '--stock') out.stock = argv[++i];
    else if (a === '--kernel') out.kernel = argv[++i];
    else if (a === '--out') out.out = argv[++i];
    else if (a === '--force') out.force = argv[++i];
    else fail('unknown argument ' + a);
  }
  if (!out.stock) fail('--stock is required');
  return out;
}

function align(n, page) {
  return Math.ceil(n / page) * page;
}

function magicOf(buf) {
  if (buf.length >= 2 && buf[0] === 0x1f && buf[1] === 0x8b) return 'gzip';
  if (buf.length >= 4 && buf[0] === 0x02 && buf[1] === 0x21 &&
      buf[2] === 0x4c && buf[3] === 0x18) return 'lz4';
  if (buf.length >= 4 && buf[0] === 0x28 && buf[1] === 0xb5 &&
      buf[2] === 0x2f && buf[3] === 0xfd) return 'zstd';
  if (buf.length >= 4 && buf[0] === 0x89 && buf[1] === 0x4c &&
      buf[2] === 0x5a && buf[3] === 0x4f) return 'lzo';
  if (buf.length >= 4 && buf[0] === 0x5d && buf[1] === 0x00 &&
      buf[2] === 0x00 && buf[3] === 0x00) return 'lzma';
  return 'raw';
}

function parseBoot(file) {
  const buf = fs.readFileSync(file);
  if (buf.length < 64) fail('file too small');
  const magic = buf.subarray(0, 8).toString('latin1');
  if (magic !== 'ANDROID!') fail('not an Android boot image (magic ' + JSON.stringify(magic) + ')');

  const u32 = (o) => buf.readUInt32LE(o);
  const u64 = (o) => Number(buf.readBigUInt64LE(o));

  const hdr = {
    kernel_size: u32(8),
    kernel_addr: u32(12),
    ramdisk_size: u32(16),
    ramdisk_addr: u32(20),
    second_size: u32(24),
    second_addr: u32(28),
    tags_addr: u32(32),
    page_size: u32(36),
    header_version: u32(40),
    os_version: u32(44),
    name: buf.subarray(48, 64).toString('latin1').replace(/\0+$/, ''),
    cmdline: buf.subarray(64, 576).toString('latin1').replace(/\0+$/, ''),
  };

  const page = hdr.page_size;
  if (!page || (page & (page - 1)) !== 0) fail('bad page size ' + page);

  // Version detection: v0 stores dt_size at 40. A v0 header has no
  // recovery_dtbo/header_size fields; detect v1/v2 by a sane header_size.
  let version = 0;
  let headerSize = 1632;
  if (buf.length >= 1660) {
    const hs = u32(1644);
    const dtbSize = u32(1648);
    if (hs >= 1660 && hs <= page) {
      version = dtbSize || buf.length >= 1660 ? 2 : 1;
      headerSize = hs;
    }
  }
  if (version === 0) headerSize = Math.min(1632, page);

  const dtSizeV0 = version === 0 ? u32(40) : 0;
  const recoveryDtboSize = version >= 1 ? u32(1632) : 0;
  const dtbSize = version >= 2 ? u32(1648) : 0;
  const dtbAddr = version >= 2 ? u64(1652) : 0;
  const recoveryDtboOffset = version >= 1 ? u64(1636) : 0;

  let off = page; // header occupies at least one page
  const sections = [];
  const add = (name, size) => {
    const start = off;
    off += align(size, page);
    if (size) sections.push({ name, start, size });
  };
  add('kernel', hdr.kernel_size);
  add('ramdisk', hdr.ramdisk_size);
  add('second', hdr.second_size);
  if (version >= 1) add('recovery_dtbo', recoveryDtboSize);
  if (version >= 2) add('dtb', dtbSize);
  if (version === 0) add('dt', dtSizeV0);

  for (const s of sections) {
    if (s.start + s.size > buf.length) fail(`section ${s.name} out of bounds`);
  }
  const usedEnd = sections.length ? sections[sections.length - 1].start +
    align(sections[sections.length - 1].size, page) : page;

  return { buf, hdr, page, version, headerSize, sections, usedEnd, dtbAddr, recoveryDtboOffset };
}

function sectionOf(img, name) {
  const s = img.sections.find((x) => x.name === name);
  if (!s) return Buffer.alloc(0);
  return img.buf.subarray(s.start, s.start + s.size);
}

function describe(file) {
  const img = parseBoot(file);
  const kernel = sectionOf(img, 'kernel');
  const ramdisk = sectionOf(img, 'ramdisk');
  console.log(`boot image      : ${file} (${img.buf.length} bytes)`);
  console.log(`header version  : ${img.version} (header_size=${img.headerSize})`);
  console.log(`page size       : ${img.page}`);
  console.log(`kernel          : ${img.hdr.kernel_size} bytes @${img.sections[0].start}, ` +
    `addr=0x${img.hdr.kernel_addr.toString(16)}, ${magicOf(kernel)}`);
  console.log(`ramdisk         : ${img.hdr.ramdisk_size} bytes, ${magicOf(ramdisk)}`);
  if (img.hdr.second_size) console.log(`second          : ${img.hdr.second_size} bytes`);
  if (img.version >= 2) {
    console.log(`dtb             : ${img.sections.find((x) => x.name === 'dtb')?.size || 0} bytes, ` +
      `addr=0x${img.dtbAddr.toString(16)}`);
  }
  console.log(`cmdline         : ${img.hdr.cmdline}`);
  console.log(`trailing bytes  : ${img.buf.length - img.usedEnd}`);
  const tail = img.buf.subarray(img.usedEnd, Math.min(img.buf.length, img.usedEnd + 32));
  const text = tail.toString('latin1').replace(/[^\x20-\x7e]/g, '.');
  if (text) console.log(`tail text       : ${text}`);
  return img;
}

function build(stockFile, kernelFile, outFile, force) {
  const img = describe(stockFile);
  let kernel = fs.readFileSync(kernelFile);
  if (kernel.length === 0) fail('kernel payload is empty');

  const stockMagic = magicOf(sectionOf(img, 'kernel'));
  const mode = force === 'auto' ? stockMagic : force;
  if (mode !== 'gzip' && mode !== 'raw') fail('unsupported --force ' + mode);

  if (mode === 'gzip') {
    kernel = zlib.gzipSync(kernel, { level: 9 });
  } else if (stockMagic !== 'raw') {
    console.warn(`warning: stock kernel is ${stockMagic}, writing raw payload`);
  }

  if (kernel.length > 64 * 1024 * 1024) fail('kernel payload suspiciously large');

  const headerPages = img.page;
  const parts = [];
  const header = Buffer.from(img.buf.subarray(0, headerPages));
  header.writeUInt32LE(kernel.length, 8);
  parts.push(header);

  parts.push(kernel);
  parts.push(Buffer.alloc(align(kernel.length, img.page) - kernel.length));
  let written = headerPages + align(kernel.length, img.page);

  const order = ['ramdisk', 'second', 'recovery_dtbo', 'dtb', 'dt'];
  for (const name of order) {
    const s = img.sections.find((x) => x.name === name);
    if (!s) continue;
    const data = img.buf.subarray(s.start, s.start + s.size);
    parts.push(data);
    const pad = align(s.size, img.page) - s.size;
    if (pad) parts.push(Buffer.alloc(pad));
    written += align(s.size, img.page);
  }

  // Preserve everything after the last parsed section (Samsung trailer,
  // AVB footer, zero padding) so offsets that firmware may expect survive.
  const tail = img.buf.subarray(img.usedEnd);
  parts.push(tail);
  written += tail.length;

  const out = Buffer.concat(parts);
  fs.writeFileSync(outFile, out);
  console.log('');
  console.log(`kernel written  : ${kernel.length} bytes (${mode})`);
  console.log(`output          : ${outFile} (${out.length} bytes)`);
  console.log(`sha256          : ${require('crypto').createHash('sha256').update(out).digest('hex')}`);
}

const args = parseArgs(process.argv.slice(2));
if (args.list || !args.kernel) {
  describe(args.stock);
} else {
  if (!args.out) fail('--out is required when --kernel is given');
  build(args.stock, args.kernel, args.out, args.force);
}
