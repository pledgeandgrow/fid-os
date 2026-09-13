// make-elf.js — Wrap a raw binary in a minimal ELF64 file for GRUB multiboot2
// Usage: node make-elf.js <input.bin> <output.elf> <load_addr_hex> [entry_hex]
const fs = require('fs');

const input = process.argv[2];
const output = process.argv[3];
const loadAddr = BigInt(parseInt(process.argv[4] || '0x100000', 16));
const entry = BigInt(parseInt(process.argv[5] || '0x100018', 16));

const raw = fs.readFileSync(input);
const rawSize = BigInt(raw.length);

const ehdrSize = 64n;  // ELF header
const phdrSize = 56n;  // Program header
const shdrSize = 64n;  // Section header (one null entry)
const dataOffset = ehdrSize + phdrSize; // 120
const shdrOffset = dataOffset + rawSize; // section headers after data

const totalSize = Number(shdrOffset + shdrSize);
const elf = Buffer.alloc(totalSize);

// ── ELF identification ──
elf[0] = 0x7F; elf[1] = 0x45; elf[2] = 0x4C; elf[3] = 0x46;
elf.writeUInt8(2, 4);   // ELFCLASS64
elf.writeUInt8(1, 5);   // ELFDATA2LSB
elf.writeUInt8(1, 6);   // EV_CURRENT

// ── ELF header ──
elf.writeUInt16LE(2, 16);       // ET_EXEC
elf.writeUInt16LE(62, 18);      // EM_X86_64
elf.writeUInt32LE(1, 20);       // EV_CURRENT
elf.writeBigUInt64LE(entry, 24);           // e_entry
elf.writeBigUInt64LE(ehdrSize, 32);        // e_phoff = 64
elf.writeBigUInt64LE(shdrOffset, 40);      // e_shoff = after data
elf.writeUInt32LE(0, 48);       // e_flags
elf.writeUInt16LE(64, 52);      // e_ehsize
elf.writeUInt16LE(56, 54);      // e_phentsize
elf.writeUInt16LE(1, 56);       // e_phnum = 1
elf.writeUInt16LE(64, 58);      // e_shentsize = 64
elf.writeUInt16LE(1, 60);       // e_shnum = 1 (null section)
elf.writeUInt16LE(0, 62);       // e_shstrndx = 0

// ── Program header (at offset 64) ──
const p = 64;
elf.writeUInt32LE(1, p + 0);    // PT_LOAD
elf.writeUInt32LE(7, p + 4);    // PF_R|PF_W|PF_X
elf.writeBigUInt64LE(dataOffset, p + 8);   // p_offset = 120
elf.writeBigUInt64LE(loadAddr, p + 16);    // p_vaddr = 0x100000
elf.writeBigUInt64LE(loadAddr, p + 24);    // p_paddr = 0x100000
elf.writeBigUInt64LE(rawSize, p + 32);     // p_filesz
elf.writeBigUInt64LE(rawSize, p + 40);     // p_memsz
elf.writeBigUInt64LE(1n, p + 48);          // p_align = 1

// ── Copy raw binary at offset 120 ──
raw.copy(elf, Number(dataOffset));

// ── Null section header at shdrOffset (64 bytes of zeros) ──
// Already zero-filled by Buffer.alloc

fs.writeFileSync(output, elf);
console.log(`Created ${output}: ${elf.length} bytes, load=0x${loadAddr.toString(16)}, entry=0x${entry.toString(16)}, shoff=0x${shdrOffset.toString(16)}`);
