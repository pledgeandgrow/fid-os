# Makefile — Fides OS kernel build
#
# Builds the kernel using the Fides compiler's --boot mode
# and packages it into a bootable ISO with GRUB.
#
# Requirements:
#   - Fides compiler (fidesc or fides-c3.exe)
#   - qemu-system-x86_64 (for testing)
#   - grub-mkrescue + xorriso (for ISO creation)
#   - gcc + ld (for ELF wrapper)
#
# Usage:
#   make            # build kernel.bin
#   make iso        # build fides-os.iso
#   make run        # build + run in QEMU
#   make minimal    # build minimal kernel (serial output only)
#   make clean      # remove build artifacts

# Use the self-hosted Fides compiler (fides-c3.exe) by default.
# Fall back to the Rust bootstrap compiler (fidesc) if not available.
FIDES_SELFHOST = ../p-lang/release/fides-c3.exe
FIDES_RUST     = ../p-lang/target/release/fidesc.exe
FIDES = $(shell if [ -x "$(FIDES_SELFHOST)" ]; then echo "$(FIDES_SELFHOST)"; else echo "$(FIDES_RUST)"; fi)
QEMU      = qemu-system-x86_64
GRUB_MKRESCUE = grub-mkrescue
CC        = gcc
LD        = ld

KERNEL_DIR   = kernel
BUILD_DIR    = build
ISO_DIR      = iso

KERNEL_RAW   = $(BUILD_DIR)/kernel-raw.bin
KERNEL_ELF   = $(BUILD_DIR)/kernel.elf
KERNEL       = $(BUILD_DIR)/kernel.bin
MINIMAL      = $(BUILD_DIR)/minimal.bin
ISO          = $(BUILD_DIR)/fides-os.iso

# ELF wrapper source and linker script
WRAP_SRC     = $(BUILD_DIR)/kernel_wrap.S
WRAP_OBJ     = $(BUILD_DIR)/kernel_wrap.o
WRAP_LD      = $(BUILD_DIR)/kernel_wrap.ld

# QEMU flags: boot from CD, 256MB RAM, serial to stdout
QEMU_FLAGS = -cdrom $(ISO) -m 256 -serial stdio -no-reboot

.PHONY: all minimal iso run clean

all: $(KERNEL)

# ─── Minimal kernel (serial output only) ──────────────────────────────────
# This is the simplest bootable kernel — just prints to COM1

$(MINIMAL): $(KERNEL_DIR)/minimal.fd | $(BUILD_DIR)
	@echo "[build] Compiling minimal kernel..."
	$(FIDES) emit $(KERNEL_DIR)/minimal.fd --boot -o $(MINIMAL)
	@echo "[build] Minimal kernel: $(MINIMAL) ($(shell wc -c < $(MINIMAL)) bytes)"

# ─── Full kernel ───────────────────────────────────────────────────────────
# The Fides compiler emits a flat binary with a Multiboot2 header.
# GRUB's multiboot2 command expects an ELF image, so we wrap the flat
# binary in a minimal ELF with a load segment at 0x100000 and entry
# point 0x100018 (0x100000 + 24-byte MB2 header).

$(KERNEL_RAW): $(KERNEL_DIR)/shell.fd | $(BUILD_DIR)
	@echo "[build] Compiling kernel (Fides --boot mode)..."
	$(FIDES) emit $(KERNEL_DIR)/shell.fd --boot -o $(KERNEL_RAW)
	@echo "[build] Raw kernel: $(KERNEL_RAW) ($$(wc -c < $(KERNEL_RAW)) bytes)"

# Generate the ELF wrapper source (just includes the raw binary)
$(WRAP_SRC): | $(BUILD_DIR)
	@echo '.section .text' > $(WRAP_SRC)
	@echo '.global _start' >> $(WRAP_SRC)
	@echo '_start:' >> $(WRAP_SRC)
	@echo '    .incbin "$(KERNEL_RAW)"' >> $(WRAP_SRC)

# Generate the linker script for the ELF wrapper
$(WRAP_LD): | $(BUILD_DIR)
	@echo 'PHDRS { text PT_LOAD; }' > $(WRAP_LD)
	@echo 'SECTIONS { . = 0x100000; .text : { *(.text) } :text }' >> $(WRAP_LD)

$(WRAP_OBJ): $(WRAP_SRC) $(KERNEL_RAW)
	$(CC) -c -o $(WRAP_OBJ) $(WRAP_SRC)

$(KERNEL_ELF): $(WRAP_OBJ) $(WRAP_LD)
	$(LD) -T $(WRAP_LD) -e 0x100018 -N -o $(KERNEL_ELF) $(WRAP_OBJ) 2>/dev/null

$(KERNEL): $(KERNEL_ELF)
	@cp $(KERNEL_ELF) $(KERNEL)
	@echo "[build] Kernel ELF: $(KERNEL) ($$(wc -c < $(KERNEL)) bytes)"

# ─── Build bootable ISO ───────────────────────────────────────────────────

iso: $(KERNEL) | $(BUILD_DIR)
	@echo "[iso] Building ISO..."
	@rm -rf $(ISO_DIR)
	@mkdir -p $(ISO_DIR)/boot/grub
	@cp $(KERNEL) $(ISO_DIR)/boot/kernel.bin
	@echo 'set timeout=0' > $(ISO_DIR)/boot/grub/grub.cfg
	@echo 'set default=0' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo 'menuentry "Fides OS" {' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '    multiboot2 /boot/kernel.bin' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '    boot' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '}' >> $(ISO_DIR)/boot/grub/grub.cfg
	$(GRUB_MKRESCUE) -o $(ISO) $(ISO_DIR) 2>/dev/null || \
		(echo "[iso] grub-mkrescue failed. Install grub-common + xorriso." && exit 1)
	@echo "[iso] ISO: $(ISO)"

# ─── Run in QEMU ───────────────────────────────────────────────────────────

run: iso
	@echo "[qemu] Launching Fides OS..."
	$(QEMU) $(QEMU_FLAGS)

# ─── Build directories ────────────────────────────────────────────────────

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# ─── Clean ────────────────────────────────────────────────────────────────

clean:
	@rm -rf $(BUILD_DIR) $(ISO_DIR)
	@echo "[clean] Build artifacts removed"
