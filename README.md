# Fides OS

A bare-metal operating system written in [Fides](https://github.com/pledgeandgrow/p-lang).

## What is this?

Fides OS is a separate project from the Fides compiler. It uses the Fides
language to build a kernel that boots on real hardware (or QEMU) via
Multiboot2/GRUB.

```
p-lang/          ← The Fides compiler (language)
  compiler/*.fd    Self-hosted compiler
  stdlib/*.fd       Language standard library (core, vec, string, ...)
  release/fides-c3.exe

fides-os/        ← This project (the OS)
  kernel/*.fd       Kernel source (written in Fides)
  kernel/minimal.fd  Minimal bootable kernel (serial output)
  linker/kernel.ld  Linker script (for future full kernel)
  initrd/mkinitrd.c Ramdisk builder
  Makefile          Build system
  build-iso.sh      ISO builder (no make required)
  run-qemu.bat      QEMU launcher for Windows
```

## Quick Start

### Build the kernel

```bash
# Using the self-hosted Fides compiler:
/home/medzer/pledge/p-lang/release/fides-c3.exe emit kernel/minimal.fd --boot -o build/kernel-raw.bin

# Or using make (handles ELF wrapping + ISO creation):
make iso
```

This produces a multiboot2-compatible kernel binary, wrapped in an ELF
for GRUB compatibility.

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

### Expected output

```
Hello from Fides OS!
```

(Output appears on the serial port, which QEMU redirects to stdout with
`-serial stdio`.)

## How It Works

The Fides compiler's `--boot` mode:

1. Generates a **Multiboot2 header** (magic `0xE85250D6`) at the start of the binary
2. Generates a **32-bit → 64-bit trampoline** that:
   - Sets up a temporary stack at `0x90000`
   - Loads a GDT with a 64-bit code segment (L=1, D=0)
   - Enables PAE (CR4.PAE)
   - Sets up identity-mapped page tables (PML4 at 0x70000, PDPT at 0x71000)
   - Enables long mode (EFER.LME)
   - Enables paging (CR0.PG)
   - Far jumps to 64-bit code (selector 0x08)
3. In 64-bit mode: sets up a 64-bit stack, calls your `main()` function
4. Halts in an infinite loop after `main()` returns

The flat binary is wrapped in a minimal ELF (load segment at `0x100000`,
entry point `0x100018`) because GRUB's `multiboot2` command expects an
ELF image.

## Architecture

### Minimal kernel (working now)

```
kernel/minimal.fd    Serial output via COM1 (4.5 KB binary)
```

### Full kernel (planned — modules exist but not yet linked)

```
boot.fd              Entry point (_start), stack setup
multiboot_header.fd  Multiboot2 header for GRUB
main.fd              kernel_main — initializes subsystems, starts shell
multiboot.fd         Parse Multiboot2 info (memory map, framebuffer, modules)
isr.fd               IDT, ISR stubs, PIC remap, handler dispatch
framebuffer.fd       Linear framebuffer, text rendering, scrolling
keyboard.fd          PS/2 keyboard, scancode → ASCII
rtc.fd               CMOS/RTC time
sched.fd             Thread scheduler (round-robin)
syscall.fd           Ring 0→3, syscall/sysret
elf_loader.fd        ELF64 user program loader
pci.fd               PCI bus enumeration
ata.fd               ATA/IDE disk driver (PIO, LBA28)
vfs.fd               Virtual filesystem, ramdisk
acpi.fd              ACPI (power off, reboot)
kernel.fd            Low-level primitives (GDT, paging, port I/O)
apic.fd              LAPIC/IOAPIC
timer.fd             PIT/HPET/LAPIC timer
kalloc.fd            Kernel allocator
uefi.fd              UEFI boot services
```

### Planned boot path

```
GRUB → _start (boot.fd)
         → set up stack
         → save multiboot ptr
         → call kernel_main (main.fd)
              → parse multiboot info
              → init serial
              → init framebuffer
              → init IDT/PIC
              → init keyboard
              → init RTC
              → init scheduler
              → mount ramdisk
              → init ACPI
              → start shell
                   → read keyboard
                   → parse command
                   → execute
                   → repeat
```

### Shell commands (planned)

```
help       Show available commands
mem        Show memory info
time       Show current time
ls         List ramdisk files
clear      Clear screen
reboot     Reboot system
poweroff   Power off
```

## Status

### What works

- **Minimal kernel boots in QEMU and prints to serial** — `kernel/minimal.fd`
  compiles with both the Rust bootstrap compiler (`fidesc emit --boot`) and
  the self-hosted Fides compiler (`fides-c3.exe emit --boot`), producing a
  valid multiboot2 binary that boots via GRUB and prints `Hello from Fides OS!`
  on the COM1 serial port.
- **32-bit → 64-bit trampoline** — The compiler generates a trampoline that
  switches from GRUB's 32-bit protected mode to 64-bit long mode (GDT, PAE,
  page tables, EFER.LME, paging) before calling `main()`.
- **Bare-metal port I/O** — `p_inb`/`p_outb` stubs are generated for
  bare-metal mode, enabling serial port communication.
- All 20 kernel modules type-check with the Fides compiler.
- Module APIs are defined and type-checked.
- Boot stub, ELF wrapper, linker script, and Makefile are in place.
- ISO build and QEMU launch scripts are ready.

### What doesn't work yet

- The full kernel (all 20 modules linked) needs multi-module `--boot` support
  in the compiler (currently `--boot` compiles a single file without stdlib).
- Framebuffer output needs the framebuffer module linked.
- Keyboard input needs ISR/IDT setup.
- No real hardware testing has been done.

## License

Same as Fides (see p-lang repo).
