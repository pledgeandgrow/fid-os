// build-iso.js — Patch kernel binary into existing bootable ISO
// Strategy: Replace raw binary at p_offset, update p_filesz/memsz.
// Directory entry size is set to max(oldSize, newSize) — GRUB can't handle
// smaller sizes but handles larger sizes fine (reads extra zeros).
//
// Usage: node build-iso.js <raw-kernel.bin> [output.iso] [input-iso]
//   input-iso defaults to build/fides-os-base.iso
//   output-iso defaults to build/fides-os.iso
const fs = require('fs');

const rawKernel = fs.readFileSync(process.argv[2]);
const inputIso = process.argv[4] || 'build/fides-os-base.iso';
const outIso = process.argv[3] || 'build/fides-os.iso';

const iso = Buffer.from(fs.readFileSync(inputIso)); // writable copy

const kernelLba = 2548;
const kernelOff = kernelLba * 2048;
const p_offset = 120; // raw binary starts at ELF offset 120
const oldDirSize = 533344;
const newElfSize = p_offset + rawKernel.length;
const dirSize = Math.max(oldDirSize, newElfSize);

console.log('Input ISO:', inputIso, '(' + iso.length + ' bytes)');
console.log('Raw kernel:', rawKernel.length, 'bytes');
console.log('New ELF size:', newElfSize);
console.log('Directory size (max):', dirSize);

// Write new raw kernel at kernelOff + p_offset
rawKernel.copy(iso, kernelOff + p_offset);

// Update p_filesz and p_memsz in ELF header
iso.writeUInt32LE(rawKernel.length, kernelOff + 96);
iso.writeUInt32LE(rawKernel.length, kernelOff + 104);

// Update ISO directory entry size (use max to avoid GRUB issues)
const entryPos = 43310;
iso.writeUInt32LE(dirSize, entryPos + 10);
iso.writeUInt32BE(dirSize, entryPos + 14);

fs.writeFileSync(outIso, iso);
console.log('Written:', outIso, '(' + iso.length + ' bytes)');
