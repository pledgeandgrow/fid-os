# Fides OS — Roadmap

> What's done, what's next, and what's hard.

## Status Summary

| # | Goal | Status |
|---|------|--------|
| 1 | Shell commands (echo, mem, info, time, poweroff) | ✅ Done |
| 2 | Interrupt-driven keyboard (IDT, PIC, IRQ1) | ✅ Done |
| 3 | Memory management (p_malloc/p_free heap) | ✅ Done |
| 4 | Port bare-metal stubs to self-hosted compiler | ✅ Done |
| 5 | Multi-module kernel linking | ✅ Done |
| 6 | Filesystem / disk I/O (ATA/PIO) | ✅ Done |
| 7 | User-mode program loading | ✅ Done |

---

## Done

### 1. Shell Commands
- `help` — list all commands
- `clear` — clear VGA screen
- `echo <text>` — print text back
- `mem` — show memory map (kernel, VGA, stack, heap)
- `info` — system info (arch, boot, display, input, serial)
- `time` — read CMOS RTC, show HH:MM:SS
- `reboot` — restart system
- `poweroff` — ACPI shutdown
- `malloc` — test heap allocation
- `disk` — read disk sector 0 via ATA/PIO
- `run` — load & run user program in ring 3
- `halt` — stop CPU

### 2. Interrupt-Driven Keyboard
- Boot trampoline auto-wires `irq1_handler` to IDT vector 0x21
- PIC remapped (IRQ0-15 → vectors 0x20-0x2F)
- IRQ1 unmasked, all other IRQs masked
- Scancode circular buffer at 0x600 (16 entries)
- `kbd_read_scancode()` uses `hlt` to sleep until key press
- CPU no longer busy-waits — sleeps until interrupt
- `p_hlt` changed to `hlt` only (no `cli`) so interrupts wake the CPU

### 3. Memory Management
- Bare-metal bump allocator in PE backend
- Heap at `0x300000`, 8-byte aligned
- `p_malloc(size)` returns pointer, `p_free(ptr)` is no-op
- Ported to both Rust (`src/pe.rs`) and self-hosted (`compiler/pe.fd`)

### 4. Port to Self-Hosted Compiler
- `p_outw`, `p_inw` — 16-bit I/O port access
- `p_malloc`, `p_free` — bare-metal heap
- `p_hlt` — fixed to not disable interrupts
- All stubs added to `compiler/pe.fd`

### 5. Multi-Module Kernel Linking
- `emit_boot()` now resolves `use` imports
- Loads `.fd` files from disk
- Merges modules into single program
- Verified with `vga_test.fd` + `vga_helper.fd`

### 6. Filesystem / Disk I/O
- `ata_read_sector(lba, buf)` — full ATA/PIO read
- `p_inw` stub for 16-bit port reads
- `disk` command reads sector 0, shows hex + MBR signature
- Tested with QEMU + test disk image

### 7. User-Mode Program Loading
- GDT with user code (0x18/0x1B) and user data (0x20/0x23) segments
- TSS at 0x4000 with rsp0=0x90000 (kernel stack for syscalls)
- `p_enter_user_mode(entry, stack)` — iretq to ring 3
- Syscall handler (int 0x80, DPL=3) — modifies iret frame to return to kernel
- `user_program_done()` — called when user program exits
- `run` command loads user program from disk sector 1 to 0x10000
- User stack at 0x12000
- Page tables have user bit set (ring 3 can access first 1GB)
- Verified: user program writes to VGA, calls int 0x80, returns to kernel

---

## Future Goals (Beyond 1-7)

- **Filesystem** — FAT32 or custom FS on disk (currently only
  raw sector reads)
- **Networking** — network card driver + TCP/IP stack
- **Graphics** — VBE/VGA framebuffer with text rendering
- **Multi-core** — SMP support (APIC + per-CPU state)
- **USB** — USB host controller driver
- **Sound** — PC speaker + Sound Blaster 16
- **Shell scripting** — pipes, redirects, variables
