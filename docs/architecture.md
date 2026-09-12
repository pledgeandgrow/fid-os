# Fides OS — Architecture

> A bare-metal operating system written in Fides, compiled by the
> self-hosted Fides compiler, booted via GRUB/Multiboot2.

## 1. Boot Flow

```
    Power On
       │
       ▼
  BIOS / UEFI
       │
       ▼
  GRUB (from ISO)
       │  loads kernel binary at 0x100000
       │  sets up Multiboot2 info struct
       ▼
  boot trampoline (in PE backend)
       │  sets up stack
       │  saves multiboot pointer
       │  calls main()
       ▼
  kernel/shell.fd :: main()
       │  p_serial_init()
       │  vga_clear()
       │  print banner
       │  run shell loop
       ▼
  Shell (interactive)
```

## 2. Memory Layout

```
  0x000000 - 0x000FFF   ── unused / low memory
  0x001000 - 0x001FFF   ── IDT (256 entries × 16 bytes)
  0x000500 - 0x00050A   ── IDT descriptor (limit + base)
  0x004000 - 0x004067   ── TSS (104 bytes, rsp0=0x90000)
  0x00600  - 0x0068F    ── Scancode buffer (16 entries + head/tail)
  0x008000 - 0x008FFF   ── SMP AP trampoline (SIPI vector 0x08)
  0x10000  - 0x11FFF    ── User program load address
  0x12000              ── User stack (grows down)
  0x100000             ── Kernel load address (GRUB/Multiboot2)
  0xB8000              ── VGA text buffer (80×25, 2 bytes/cell)
  0x200000             ── Kernel stack region
  0x300000             ── Kernel heap (bump allocator, ptr at 0x300000)
  0x3F8                 ── COM1 serial port
  0x60 / 0x64           ── Keyboard data / status ports
  0x70 / 0x71            ── CMOS / RTC
  0x1F0 - 0x1F7         ── Primary ATA/PIO disk controller
  0x604 / 0xB004        ── QEMU ACPI shutdown ports
  0x150000             ── PCI device table
  0x190000             ── (reserved, was ARP cache in monolith)
  0x1A0000 - 0x1AEFFF  ── E1000 TX/RX descriptors, buffers, MAC, ARP cache
  0x1AE300 - 0x1AE30F  ── ICMP ping statistics (sent/recv/RTT)
  0x1AE400 - 0x1AE5FF  ── DHCP packet buffer + UDP socket table
  0x1B0000 - 0x1B0FFF  ── Framebuffer metadata + cursor + font data
  0x1C0000 - 0x1C0FFF  ── SMP per-CPU state + CPU count
  0x1C1000 - 0x1CFFFF  ── SMP AP stacks (4KB per AP)
  0x1D0000 - 0x1D0FFF  ── Shell variable table (32 vars × 64 bytes)
  0x1D1000 - 0x1D2FFF  ── Output capture buffer (8KB, pipes/redirects)
  0x1D3000 - 0x1D4000  ── Pipe input buffer (4KB)
  0x1D5000 - 0x1D5008  ── Capture flag + length (console output capture)
  0x1D6000 - 0x1D6FFF  ── Shell history (16 entries × 128 bytes)
  0x190000 - 0x190FFF  ── File descriptor table (16 entries × 32 bytes)
  0x330000 - 0x33FFFF  ── Kernel thread table (16 threads × 128 bytes)
  0x340000 - 0x34FFFF  ── Kernel thread stacks (16 × 4KB)
  0x350000 - 0x35FFFF  ── Disk block cache (8 sectors × 520 bytes)
  0x50000              ── Multiboot2 info pointer (saved by boot trampoline)
  0xFEE00000           ── LAPIC MMIO base
```

## 3. Subsystems

### 3.1 VGA Text Output
- **File:** `kernel/shell.fd`
- **Address:** `0xB8000`
- **Mode:** 80 columns × 25 rows, 2 bytes per cell (char + attr)
- **Functions:** `vga_putc`, `vga_clear`, `vga_scroll`, `con_putc`

### 3.2 Serial Output
- **File:** `kernel/shell.fd`
- **Port:** COM1 (`0x3F8`)
- **Functions:** `p_serial_init`, `p_serial_write`, `serial_putc`
- **Purpose:** Debug output mirrored to QEMU `-serial stdio`

### 3.3 Keyboard Input (Interrupt-Driven)
- **File:** `kernel/shell.fd`
- **Ports:** `0x60` (data), `0x64` (status)
- **Mode:** Interrupt-driven (IRQ1 → IDT vector 0x21)
- **Handler:** `interrupt fn irq1_handler()` — reads scancode, stores in buffer, sends EOI
- **Buffer:** Circular buffer at 0x600 (16 entries), head/tail at 0x680/0x688
- **Functions:** `kbd_read_scancode()` — uses `hlt` to sleep until key press
- **Boot trampoline:** Auto-wires irq1_handler to IDT, remaps PIC, enables interrupts

### 3.4 Shell
- **File:** `kernel/shell.fd`
- **Input buffer:** Fixed-size array, character-by-character
- **Commands:** `help`, `clear`, `echo`, `mem`, `info`, `time`,
  `reboot`, `poweroff`, `malloc`, `disk`, `halt`
- **Matching:** `input_matches` (5-char) and `input_matches8` (8-char)

### 3.5 Memory Management
- **File:** `src/pe.rs` (Rust backend), `compiler/pe.fd` (self-hosted)
- **Type:** Bump allocator (no free)
- **Heap:** Starts at `0x300000`, pointer stored at that address
- **Functions:** `p_malloc(size)`, `p_free(ptr)` (no-op in bare mode)
- **Alignment:** 8 bytes

### 3.6 Disk I/O (ATA/PIO)
- **File:** `kernel/shell.fd`
- **Controller:** Primary ATA (`0x1F0-0x1F7`)
- **Mode:** PIO (programmed I/O, no DMA)
- **Functions:** `ata_read_sector(lba, buf)` — reads one 512-byte sector
- **Command:** `disk` — reads sector 0, shows hex dump + MBR signature

### 3.7 RTC (Real-Time Clock)
- **File:** `kernel/shell.fd`
- **Ports:** `0x70` (index), `0x71` (data)
- **Command:** `time` — reads CMOS RTC, converts BCD to binary

### 3.8 Power Management
- **File:** `kernel/shell.fd`
- **Commands:** `poweroff`, `reboot`
- **Method:** QEMU ACPI shutdown (`p_outw(0x604, 0x2000)`)

### 3.9 User-Mode Program Loading
- **File:** `kernel/shell.fd`
- **Command:** `run` — loads user program from disk sector 1
- **GDT:** User code (0x18/0x1B), user data (0x20/0x23), TSS (0x28)
- **TSS:** At 0x4000, rsp0=0x90000 (kernel stack for syscalls)
- **Transition:** `p_enter_user_mode(entry, stack)` — iretq to ring 3
- **Syscall:** int 0x80 (DPL=3) — modifies iret frame to return to kernel
- **User program:** Flat binary at 0x10000, stack at 0x12000
- **Page tables:** User bit set (ring 3 can access first 1GB)

## 4. Build System

### 4.1 Compile
```bash
# Using Rust bootstrap compiler:
../p-lang/target/release/fidesc.exe emit kernel/shell.fd --boot -o build/kernel-raw.bin

# Using self-hosted compiler:
../p-lang/release/fides-c3.exe emit kernel/shell.fd --boot -o build/kernel-raw.bin
```

### 4.2 ISO
```bash
make iso
# Uses grub-mkrescue to create build/fides-os.iso
```

### 4.3 QEMU
```bash
# Headless (serial only):
qemu-system-x86_64 -cdrom build/fides-os.iso -m 256 -serial stdio -no-reboot -display none

# With display:
qemu-system-x86_64 -cdrom build/fides-os.iso -m 256 -serial stdio -no-reboot -display sdl

# With test disk:
qemu-system-x86_64 -cdrom build/fides-os.iso -hda build/testdisk.img -boot d -m 256 -serial stdio
```

## 5. Compiler Support

### 5.1 Rust PE Backend (`src/pe.rs`)
Bare-metal stubs generated in `gen_runtime_stubs()`:
- `p_inb`, `p_outb`, `p_inw`, `p_outw` — I/O port access
- `p_hlt`, `p_cli`, `p_sti` — CPU control
- `p_lidt`, `p_idt_set_entry` — IDT management
- `p_lgdt`, `p_gdt_set_entry` — GDT management
- `p_enter_user_mode` — ring 3 transition via iretq
- `p_cr3_read/write`, `p_cr0_read/write` — MMU
- `p_mem_read8`, `p_mem_write8` — Memory access
- `p_serial_init`, `p_serial_write` — Serial
- `p_malloc`, `p_free` — Heap (bump allocator in bare mode)

Boot trampoline features:
- 32-bit → 64-bit long mode switch
- GDT with kernel/user code/data segments + TSS
- IDT setup (auto-wires `irq1_handler` if present)
- PIC remap (IRQ0-15 → vectors 0x20-0x2F)
- TSS setup (rsp0=0x90000)
- Syscall handler (int 0x80, DPL=3) — auto-wired if `syscall_handler` label exists
- Page tables with user bit (ring 3 can access first 1GB)

### 5.2 Self-Hosted PE Backend (`compiler/pe.fd`)
Same stubs ported to Fides source. The self-hosted compiler is the
intended compiler for future generations (c4, c5, ...).

### 5.3 Multi-Module Boot Mode
`emit_boot()` in `src/compiler.rs` resolves `use` imports:
- Loads `.fd` files from disk relative to source path
- Registers imported modules with typechecker
- Merges all functions/structs/enums into one program
- Enables splitting the kernel into modules (vga.fd, keyboard.fd, etc.)

## 6. Kernel Modules (kernel/*.fd)

The kernel is now modular — `shell.fd` is the entry point that imports
22 modules via `use` declarations. All modules compile under `--boot`
mode with bare-metal primitives (i64, port I/O, memory access).

| File | Status | Purpose |
|------|--------|---------|
| `shell.fd` | **ACTIVE** | Main entry point + shell loop + command dispatch |
| `vga.fd` | **ACTIVE** | VGA text mode output (0xB8000) |
| `serial.fd` | **ACTIVE** | COM1 serial output (0x3F8) |
| `console.fd` | **ACTIVE** | Console output bridge + input buffer + print utils + capture |
| `isr.fd` | **ACTIVE** | Interrupt service routines (exceptions + IRQ0/IRQ12) |
| `keyboard.fd` | **ACTIVE** | Interrupt-driven keyboard + scancode buffer |
| `kalloc.fd` | **ACTIVE** | Page-frame allocator + heap (p_malloc/p_free) |
| `sched.fd` | **ACTIVE** | Process table + scheduler |
| `ata.fd` | **ACTIVE** | ATA/PIO disk driver |
| `vfs.fd` | **ACTIVE** | FAT32 filesystem |
| `initrd.fd` | **ACTIVE** | Initrd ramdisk loading + file access |
| `pci.fd` | **ACTIVE** | PCI bus enumeration |
| `acpi.fd` | **ACTIVE** | ACPI power management |
| `vm.fd` | **ACTIVE** | Virtual memory / page mapping |
| `mouse.fd` | **ACTIVE** | PS/2 mouse driver |
| `apic.fd` | **ACTIVE** | APIC interrupt controller |
| `elf.fd` | **ACTIVE** | ELF executable loader |
| `syscall.fd` | **ACTIVE** | Syscall interface (int 0x80) |
| `net.fd` | **ACTIVE** | E1000 driver + ARP/IPv4/ICMP/UDP/TCP |
| `framebuffer.fd` | **ACTIVE** | VBE framebuffer + 8x16 bitmap font + text rendering |
| `smp.fd` | **ACTIVE** | SMP boot via LAPIC IPIs + AP trampoline |
| `dma.fd` | **ACTIVE** | ATA DMA (bus-master) info |
| `shell_script.fd` | **ACTIVE** | Shell variables, pipes, redirects |

## 7. Repository Boundaries

```
  p-lang/          ── Fides language + compiler (this is NOT the OS)
    compiler/*.fd    Self-hosted compiler
    src/*.rs         Rust bootstrap reference
    release/         fides-c3.exe (self-hosted binary)

  fides-os/        ── The operating system (THIS repo)
    kernel/*.fd      Kernel source
    docs/            Architecture + roadmap
    build/           Output (kernel.bin, .iso)
```

## 8. Known Limitations & Restrictions

### PE Backend Interrupt Handler Code Layout Bug (CRITICAL BLOCKER)

The Fides PE backend (`p-lang/src/pe.rs`) has a code layout sensitivity specific
to **interrupt handlers**: any code change to an `@interrupt` function (or the
`interrupt fn irq1_handler`) triggers an invalid opcode (#UD) or page fault
crash, even when the kernel binary size stays the same (500,400 bytes).

**Key findings:**
- Adding code to **regular functions** (e.g., `cmd_help`) works fine — the kernel
  boots and all commands work at 504,496 bytes.
- Adding even a single `p_mem_write8` to the **timer handler** (`irq0_handler`)
  triggers a #UD crash when `net` is typed.
- All relocations (rel32 calls, RIP-relative refs, IDT `lea_label`) are computed
  correctly — the bug is elsewhere in the PE backend's interrupt handler code
  generation.
- The rdata section is identical between working and crashing binaries, and the
  rdata_rva is the same.

This blocks:
- Preemptive scheduler (quantum-based context switch in the timer handler)
- AHCI/SATA DMA driver (requires interrupt handler modifications)
- Per-CPU GDT/TSS validation (requires interrupt handler modifications)

**Workaround:** The timer handler is frozen at its current code layout. The
cooperative scheduler uses the shell loop to check the tick counter and call
`kthread_yield()` instead of modifying the timer handler.

### SMP AP Startup

The `smp` command no longer crashes (fixed via `#UD` handler), but AP1 startup
still fails:
- BSP APIC ID: 0
- CPU count: 1
- AP1 boot sequence times out
- BSP remains alive

The trampoline writes code to physical 0x8000, sends INIT/SIPI/SIPI via LAPIC
ICR, and waits for the AP count to increase. The root cause of AP startup
failure is unresolved.

### Cooperative Scheduling (Working)

The scheduler is cooperative, not preemptive:
- The shell loop checks `timer_get_ticks()` and calls `kthread_yield()` when
  ticks >= 20
- `kthread_yield()` resets the tick counter
- `kthread_create()` and `kthread_join()` exist for thread management
- Full timer-driven register/context switching is NOT implemented
- The timer ISR cannot be modified (triggers PE backend bug)
- True preemption requires fixing the PE backend's interrupt handler code
  generation bug

### AHCI/SATA

PCI discovery for AHCI exists, but a real DMA-based AHCI/SATA driver does not.
Implementation is blocked by the PE backend interrupt handler code layout bug.

### Per-CPU GDT/TSS

Per-CPU state structures exist at 0x1C0000, but validation depends on
functioning AP startup. Since AP1 still fails, per-CPU GDT/TSS should not be
considered fully verified.
