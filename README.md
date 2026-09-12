# Fides OS

A bare-metal operating system written in [Fides](https://github.com/pledgeandgrow/p-lang).

## What is this?

Fides OS is a separate project from the Fides compiler. It uses the Fides
language to build a kernel that boots on real hardware (or QEMU) via
Multiboot2/GRUB. The kernel is a modular, single-address-space,
identity-mapped bare-metal OS with a built-in interactive shell.

```
p-lang/          ← The Fides compiler (language)
  compiler/*.fd    Self-hosted compiler (52 modules)
  stdlib/*.fd       Language standard library (core, vec, string, ...)
  release/fides-c3.exe

fides-os/        ← This project (the OS)
  kernel/*.fd       Kernel source (30+ modules, written in Fides)
  kernel/shell.fd   Canonical kernel entry point (boots directly)
  kernel/minimal.fd Minimal bootable kernel (serial output only)
  docs/             Architecture + roadmap
  initrd/mkinitrd.c Ramdisk builder
  Makefile          Build system
  build-iso.sh      ISO builder (no make required)
  run-qemu.bat      QEMU launcher for Windows
```

## Quick Start

### Build the kernel

```bash
# Using the self-hosted Fides compiler:
../p-lang/release/fides-c3.exe emit kernel/shell.fd --boot -o build/kernel-raw.bin

# Or using make (handles ELF wrapping + ISO creation):
make iso
```

This produces a multiboot2-compatible kernel binary (~760 KB), wrapped in
an ELF for GRUB compatibility.

### Build a bootable ISO

```bash
# Requires: grub-mkrescue + xorriso + gcc + ld
make iso
# Or:
./build-iso.sh
```

### Run in QEMU

```bash
make run
# Or directly:
qemu-system-x86_64 -cdrom build/fides-os.iso -m 256 -serial stdio -no-reboot
```

### On Windows

1. Install [QEMU for Windows](https://qemu.org/download/#windows)
2. Build the ISO on Linux (or download from releases)
3. Run: `run-qemu.bat path\to\fides-os.iso`

## Architecture

The kernel entry point is `kernel/shell.fd`, which imports 30+ modules via
`use` declarations. All modules compile under `--boot` mode with bare-metal
primitives (i64, port I/O, memory access — no stdlib).

### Boot flow

```
GRUB → boot trampoline (PE backend)
         → 32-bit → 64-bit long mode switch
         → GDT, PAE, page tables, EFER.LME, paging
         → call main() in shell.fd
              → init serial, VGA, console
              → init IDT, PIC, keyboard
              → init heap, buddy allocator, slab allocator
              → init process table, scheduler
              → init FAT32, tmpfs, VFS
              → init E1000, ARP, TCP/UDP
              → start interactive shell loop
```

### Kernel modules

| File | Purpose |
|------|---------|
| `shell.fd` | Main entry point + shell loop + command dispatch (50+ commands) |
| `vga.fd` | VGA text mode output (0xB8000) |
| `serial.fd` | COM1 serial output (0x3F8) |
| `console.fd` | Console bridge + input buffer + print utils + capture |
| `isr.fd` | Interrupt service routines (exceptions + IRQ0–IRQ12) |
| `keyboard.fd` | Interrupt-driven keyboard + scancode buffer |
| `kalloc.fd` | Heap + buddy page-frame allocator + slab allocator |
| `vm.fd` | Virtual memory, page mapping, mmap/munmap, NX/guard pages |
| `sched.fd` | Process table + cooperative scheduler + priority scheduling |
| `syscall.fd` | Syscall interface, process descriptors, signals, FD table, pipes |
| `ata.fd` | ATA/PIO disk driver (LBA28) |
| `vfs.fd` | FAT32 filesystem + VFS layer + tmpfs + procfs |
| `initrd.fd` | Initrd ramdisk loading + hierarchical file access |
| `pci.fd` | PCI bus enumeration |
| `acpi.fd` | ACPI power management |
| `mouse.fd` | PS/2 mouse driver |
| `framebuffer.fd` | VBE framebuffer + 8×16 bitmap font + text rendering |
| `apic.fd` | APIC interrupt controller |
| `elf.fd` | ELF executable loader |
| `net.fd` | E1000 driver + ARP/IPv4/ICMP/UDP/TCP + DNS + DHCP + socket API |
| `dma.fd` | ATA DMA (bus-master) info |
| `shell_script.fd` | Shell variables, pipes, redirects |
| `smp.fd` | SMP boot via LAPIC IPIs + AP trampoline |
| `audio.fd` | PC speaker + audio tones |
| `graphics.fd` | Graphics primitives |
| `gamepad.fd` | Gamepad input |
| `gameloop.fd` | Game loop + snake game |
| `gpio.fd` | GPIO support |
| `button.fd` | Button input |
| `arm_boot.fd` | ARM Cortex-M target info |

### Memory management

- **Bump allocator** — `p_malloc`/`p_free` (heap at 0x300000)
- **Buddy page-frame allocator** — multi-order free-page tracking
  (`buddy_alloc`/`buddy_free`/`buddy_free_pages`)
- **Slab allocator** — 4 size classes (16/32/64/128 bytes) for small kernel
  objects (`slab_alloc`/`slab_free`/`slab_free_count`)
- **Virtual memory** — `vm_map`/`vm_unmap` with 2 MB page splitting
- **mmap/munmap** — anonymous mapping via `mmap_anon`/`munmap`
- **Memory protection** — `VM_PROT_READ/WRITE/NX` flags, guard pages,
  `vm_protect`/`vm_guard`

### Process management

- **Process descriptors** — 64-byte entries with PID, state, entry, pml4,
  parent PID, priority, child count, exit code, pending signals
- **fork/wait/kill** — `sys_fork` creates child descriptors, `sys_wait`
  reaps zombies, `sys_kill` delivers signals (SIGKILL/SIGSTOP/SIGTERM/...)
- **Signal delivery** — `sig_deliver_pending` checks handlers and applies
  default actions
- **Priority scheduling** — `proc_next_by_priority` selects runnable
  processes by nice level (−20..19)
- **Cooperative threads** — `kthread_create`/`yield`/`join`/`exit`

### Filesystem

- **FAT32** — full read/write (create/delete files, directory listing)
- **tmpfs** — in-memory filesystem with create/mkdir/read/write/remove
- **VFS layer** — `vfs_open`/`vfs_read`/`vfs_write` dispatches to tmpfs
  (`/tmp/`), procfs (`/proc/`), or FAT32 by path prefix
- **procfs** — synthetic `/proc/meminfo`, `/proc/cpuinfo`, `/proc/uptime`
- **Directory ops** — `mkdir`, `rmdir`, `readdir`, `chdir`, `pwd`
- **FD table** — `sys_open`/`sys_close`/`sys_dup2` with per-process entries

### Networking

- **E1000 driver** — PCI discovery, MMIO, TX/RX rings, MAC from EEPROM
- **ARP** — request/reply with 16-entry cache
- **IPv4** — packet construction with checksum
- **ICMP** — echo request/reply (real ping) with statistics
- **UDP** — send + receive routing to bound sockets
- **TCP** — 3-way handshake, data transfer, listen/accept, FIN handling
- **DNS** — A-record query construction + response parsing
- **DHCP** — full DORA (DISCOVER → OFFER → REQUEST → ACK)
- **Socket API** — `sock_socket`/`bind`/`listen`/`accept`/`connect`/
  `send`/`recv`/`close` wrapping TCP and UDP

### Shell commands (50+)

```
help, clear, echo, mem, info, time, date, reboot, poweroff, halt,
malloc, free, heap, buddy, slab, mmap,
disk, run, elf, ticks,
ps, procs, threads, sched, nice, kill, fork,
ls, cat, touch, rm, tmpfs, mkdir, rmdir, tmpwrite, tmpread, pwd, cd,
net, arp, pstats, dhcp, dhcpd, ping, tcp, listen, dns,
vm, mouse, apic, acpi, fb, smp, dma, vars, audio, music, gfx, snake,
gpad, gpio, btn, arm
```

## Status

### What works

- **Full modular kernel boots in QEMU** — `kernel/shell.fd` compiles with
  the self-hosted Fides compiler (`fides-c3.exe emit --boot`), producing a
  ~760 KB multiboot2 binary that boots via GRUB into an interactive shell.
- **30+ kernel modules** — all type-check and link under `--boot` mode.
- **VGA + framebuffer text output** — 80×25 VGA and VBE framebuffer with
  8×16 bitmap font.
- **Interrupt-driven keyboard + mouse** — IDT, PIC remap, scancode buffer.
- **Memory management** — bump heap, buddy allocator, slab allocator,
  mmap/munmap, NX/guard pages.
- **Process management** — process descriptors, fork/wait/kill, signals,
  priority scheduling (cooperative — preemption blocked by PE backend bug).
- **FAT32 read/write** — create/delete files, directory listing.
- **tmpfs + VFS + procfs** — in-memory filesystem, unified VFS dispatch,
  synthetic /proc files.
- **E1000 networking** — ARP, IPv4, ICMP ping, UDP send/receive, TCP
  connections (listen/accept/connect), DNS resolver, DHCP DORA.
- **Shell scripting** — variables, pipes, redirects, 50+ commands.
- **SMP trampoline** — AP boot code + LAPIC IPIs (AP1 startup still fails).

### Known limitations

- **Preemptive scheduling** — blocked by PE backend interrupt handler code
  layout bug; scheduler is cooperative only.
- **SMP AP startup** — AP1 times out; root cause unresolved.
- **AHCI/SATA DMA** — blocked by the same PE backend bug.
- **No real hardware testing** — QEMU only.

## License

Same as Fides (see p-lang repo).
