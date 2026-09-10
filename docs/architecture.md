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
/home/medzer/pledge/p-lang/target/release/fidesc emit kernel/shell.fd --boot -o build/kernel-raw.bin

# Using self-hosted compiler (when fixed):
/home/medzer/pledge/p-lang/release/fides-c3.exe emit kernel/shell.fd --boot -o build/kernel-raw.bin
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

## 6. Planned Modules (kernel/*.fd)

| File | Status | Purpose |
|------|--------|---------|
| `shell.fd` | **ACTIVE** | Main kernel + shell (monolithic) |
| `boot.fd` | Stub | Boot trampoline (currently in PE backend) |
| `multiboot.fd` | Stub | Multiboot2 info parsing |
| `framebuffer.fd` | Stub | Graphical framebuffer |
| `keyboard.fd` | Stub | Interrupt-driven keyboard |
| `isr.fd` | Stub | Interrupt service routines |
| `kalloc.fd` | Stub | Page-frame allocator + heap |
| `vfs.fd` | Stub | Virtual filesystem |
| `ata.fd` | Stub | ATA/PIO disk driver |
| `rtc.fd` | Stub | RTC clock |
| `acpi.fd` | Stub | ACPI power management |
| `sched.fd` | Stub | Task scheduler |
| `syscall.fd` | Stub | Syscall interface |
| `elf_loader.fd` | Stub | ELF executable loader |
| `pci.fd` | Stub | PCI bus enumeration |
| `apic.fd` | Stub | APIC interrupt controller |
| `timer.fd` | Stub | Programmable timer |
| `uefi.fd` | Stub | UEFI boot services |

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
