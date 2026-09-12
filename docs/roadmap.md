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
| 8 | Modular kernel (shell.fd split into 22 modules) | ✅ Done |
| 9 | E1000 network driver + TCP/IP stack | ✅ Done |
| 10 | Graphical framebuffer text rendering | ✅ Done |
| 11 | SMP boot via LAPIC IPIs | ✅ Done |
| 12 | Shell scripting (pipes, redirects, variables) | ✅ Done |
| 13 | MMIO page mapping (LAPIC + E1000) | ✅ Done |
| 14 | Multiboot2 info parsing + framebuffer | ✅ Done |
| 15 | Kernel panic register dump + stack trace | ✅ Done |
| 16 | LAPIC timer (enable/disable/count) | ✅ Done |
| 17 | Kernel threads (create/yield/join/exit) | ✅ Done |
| 18 | Spinlocks (atomic xchg) | ✅ Done |
| 19 | FAT32 write support (create/delete files) | ✅ Done |
| 20 | Initrd directory tree (hierarchical paths) | ✅ Done |
| 21 | Disk block cache (8-sector LRU) | ✅ Done |
| 22 | DHCP client (DISCOVER) | ✅ Done |
| 23 | UDP socket API (create/send/close) | ✅ Done |
| 24 | ICMP ping statistics (sent/recv/loss/RTT) | ✅ Done |
| 25 | ARP table management (arp command) | ✅ Done |
| 26 | Shell history (up/down arrow recall) | ✅ Done |
| 27 | Shell tab completion | ✅ Done |
| 28 | PS/2 mouse cursor (absolute position + framebuffer) | ✅ Done |
| 29 | Syscall expansion (open/close + existing) | ✅ Done |
| 30 | Preemptive scheduler | ⚠ Cooperative only (PE backend bug) |
| 31 | Per-CPU GDT + TSS | ⚠ Needs working SMP |
| 32 | AHCI/SATA driver | ⚠ Needs PCI DMA |
| 33 | Keyboard scancode set 2 | ✅ 0xE0 handling works (addition not OR) |

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

## Future Goals (Beyond 1-12)

- **USB** — USB host controller driver
- **Sound** — PC speaker + Sound Blaster 16
- **Real ARP resolution** — ARP cache populated on demand, used by IPv4 send
- **TCP connections** — full 3-way handshake, state machine, data transfer
- **Framebuffer console** — replace VGA text mode as primary output
- **SMP scheduling** — distribute processes across CPUs
- **FAT32 write** — create/delete files, directory operations

---

## Done (Goals 8-12)

### 8. Modular Kernel
- `shell.fd` split from 3019-line monolith into 22 module files
- All modules compile under `--boot` mode with bare-metal primitives
- Multi-module `--boot` linking verified: 402KB boot-ready Multiboot2 image
- Module dependency graph resolved (no circular imports)
- Modules: vga, serial, console, isr, keyboard, kalloc, sched, ata, vfs,
  initrd, pci, acpi, vm, mouse, apic, elf, syscall, net, framebuffer, smp,
  dma, shell_script, shell

### 9. E1000 Network Driver + TCP/IP Stack
- E1000 PCI discovery (vendor 0x8086, device 0x100E)
- MMIO register access via BAR0
- MAC address read from EEPROM
- TX/RX descriptor rings (16 descriptors each)
- Ethernet frame send/receive
- ARP request/reply with cache (16 entries)
- IPv4 packet construction with checksum
- ICMP echo request/reply (real `ping`)
- UDP send
- TCP send (SYN/ACK/FIN flags)
- `net` command shows E1000 status, MAC, IP
- `ping` command sends real ICMP echo, waits for reply

### 10. Graphical Framebuffer Text Rendering
- Framebuffer metadata at 0x1B0000 (addr, width, height, bpp, pitch)
- Built-in 8x16 bitmap font (96 characters, programmatically generated)
- Font includes digits, uppercase A-Z, lowercase a-z, punctuation
- `fb_putpixel(x, y, color)` — individual pixel plotting
- `fb_draw_char(x, y, c, fg, bg)` — glyph rendering
- `fb_putc(c)` — text output with cursor tracking
- `fb_scroll()` — line scrolling when cursor reaches bottom
- `fb_clear_screen()` — clear framebuffer
- `fb_set_info(addr, w, h, bpp, pitch)` — for multiboot2 framebuffer parsing
- `fb` command shows framebuffer status

### 11. SMP Boot via LAPIC IPIs
- AP trampoline at physical 0x8000 (SIPI vector 0x08)
- Trampoline: real mode → 32-bit → 64-bit long mode transition
- Reuses BSP page tables (PML4 at 0x70000)
- Per-CPU state at 0x1C0000 (16 CPUs × 64 bytes)
- CPU count tracking at 0x1C0400
- INIT-SIPI-SIPI sequence per Intel spec
- AP entry function increments CPU count, sets state to alive
- `smp` command boots AP 1, shows per-CPU status
- AP stacks at 0x1C1000 (4KB per AP)

### 12. Shell Scripting
- Variable storage at 0x1D0000 (32 variables × 64 bytes)
- Variable assignment: `name=value`
- Variable expansion: `$name` → value
- `vars` command shows all variables
- Pipe support: `cmd1 | cmd2` (output capture + display)
- Redirect support: `cmd > file` and `cmd >> file`
- Output capture buffer at 0x1D1000 (8KB)
- Console output capture via CAPTURE_FLAG at 0x1D5000
- `shell_dispatch()` function for command execution
