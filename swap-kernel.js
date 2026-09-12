// swap-kernel.js — Replace kernel.bin inside an existing El Torito ISO
// Usage: node swap-kernel.js <iso> <new-kernel.bin> <output.iso>
const fs = require('fs');

const isoPath = process.argv[2];
const kernelPath = process.argv[3];
const outPath = process.argv[4] || isoPath;

const iso = Buffer.from(fs.readFileSync(isoPath)); // writable copy
const kernel = fs.readFileSync(kernelPath);

// ── Find kernel.bin;1 directory entry in /boot directory (LBA 21) ──
const bootDirLBA = 21;
const bootDirOff = bootDirLBA * 2048;
// The boot directory is 2048 bytes. Parse entries to find kernel.bin;1
let dirOff = bootDirOff;
let kernelEntryOff = -1;
while (dirOff < bootDirOff + 2048) {
  const recLen = iso.readUInt8(dirOff);
  if (recLen === 0) break;
  const nameLen = iso.readUInt8(dirOff + 32);
  const name = iso.slice(dirOff + 33, dirOff + 33 + nameLen).toString();
  if (name.startsWith('kernel.bin')) {
    kernelEntryOff = dirOff;
    const oldLen = iso.readUInt32LE(dirOff + 10);
    const oldLBA = iso.readUInt32LE(dirOff + 2);
    console.log(`Found kernel.bin;1 at dir offset 0x${dirOff.toString(16)}`);
    console.log(`  Old LBA: ${oldLBA}, old size: ${oldLen}`);
    console.log(`  New size: ${kernel.length}`);
    break;
  }
  dirOff += recLen;
}

if (kernelEntryOff < 0) {
  console.error('ERROR: kernel.bin;1 not found in /boot directory');
  process.exit(1);
}

// ── Update file size in directory entry (both LE and BE) ──
iso.writeUInt32LE(kernel.length, kernelEntryOff + 10);  // LE
iso.writeUInt32BE(kernel.length, kernelEntryOff + 14);  // BE
console.log(`Updated directory entry file size to ${kernel.length} (LE+BE)`);

// ── Verify the kernel fits in the ISO ──
const kernelLBA = iso.readUInt32LE(kernelEntryOff + 2); // should be 2548
const kernelSectors = Math.ceil(kernel.length / 2048);
const kernelEndLBA = kernelLBA + kernelSectors;
const isoSectors = iso.length / 2048;
console.log(`Kernel LBA: ${kernelLBA}, sectors: ${kernelSectors}, end LBA: ${kernelEndLBA}`);
console.log(`ISO sectors: ${isoSectors}, free after kernel: ${isoSectors - kernelEndLBA}`);

if (kernelEndLBA > isoSectors) {
  console.error('ERROR: New kernel does not fit in ISO!');
  process.exit(1);
}

// ── Write new kernel data at kernelLBA ──
const kernelOff = kernelLBA * 2048;
console.log(`Writing ${kernel.length} bytes at offset 0x${kernelOff.toString(16)}`);
kernel.copy(iso, kernelOff);
// Zero-fill any remaining bytes in the last sector
const lastSectorUsed = kernel.length % 2048;
if (lastSectorUsed > 0) {
  const zeroStart = kernelOff + kernel.length;
  const zeroEnd = kernelOff + kernelSectors * 2048;
  iso.fill(0, zeroStart, zeroEnd);
}

// ── Write output ISO ──
fs.writeFileSync(outPath, iso);
console.log(`Wrote ${outPath} (${iso.length} bytes)`);
