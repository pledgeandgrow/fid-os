# Makefile — Fides OS kernel build with incremental caching
#
# Build pipeline:
#   .fd source → kernel-raw.bin → kernel.elf → kernel.bin → patched ISO
#
# Caching strategy (like Rust's incremental compilation):
#   - Base ISO is built once with grub-mkrescue and cached as fides-os-base.iso
#   - Kernel is only recompiled if any .fd source file changed
#   - On each rebuild, the kernel is patched into the cached base ISO
#   - Full ISO rebuild only needed when GRUB config changes or kernel grows
#
# Requirements:
#   - Fides compiler (fidesc or fides-c3.exe)
#   - Node.js (for ELF wrapping + ISO patching — no gcc/ld needed)
#   - qemu-system-x86_64 (for testing)
#   - grub-mkrescue + xorriso (only for `base-iso` and `iso` targets)
#
# Usage:
#   make            # build kernel + patch into cached ISO (fast, default)
#   make patch      # same as above, explicit
#   make base-iso   # build base ISO with grub-mkrescue (run once first time)
#   make iso        # full rebuild with grub-mkrescue (slow, no caching)
#   make run        # build + run in QEMU
#   make minimal    # build minimal kernel (serial output only)
#   make clean      # remove kernel + patched ISO (keeps base ISO cache)
#   make distclean  # remove everything including base ISO cache

# ─── Tools ────────────────────────────────────────────────────────────────
FIDES_SELFHOST = ../p-lang/release/fides-c3.exe
FIDES_RUST     = ../p-lang/target/release/fidesc.exe
FIDES = $(shell if [ -x "$(FIDES_SELFHOST)" ]; then echo "$(FIDES_SELFHOST)"; else echo "$(FIDES_RUST)"; fi)
QEMU      = qemu-system-x86_64
GRUB_MKRESCUE = grub-mkrescue
NODE      = node

# ─── Paths ────────────────────────────────────────────────────────────────
KERNEL_DIR   = kernel
BUILD_DIR    = build
ISO_DIR      = iso

KERNEL_RAW   = $(BUILD_DIR)/kernel-raw.bin
KERNEL_ELF   = $(BUILD_DIR)/kernel.elf
KERNEL       = $(BUILD_DIR)/kernel.bin
MINIMAL      = $(BUILD_DIR)/minimal.bin
BASE_ISO     = $(BUILD_DIR)/fides-os-base.iso
ISO          = $(BUILD_DIR)/fides-os.iso

# ─── Source dependencies (all .fd files) ──────────────────────────────────
# Any .fd file change triggers a kernel recompile — like Rust tracking deps
KERNEL_SRCS = $(wildcard $(KERNEL_DIR)/*.fd)

# ─── QEMU flags ───────────────────────────────────────────────────────────
QEMU_FLAGS = -cdrom $(ISO) -m 256 -serial stdio -no-reboot

.PHONY: all patch base-iso iso run minimal clean distclean

all: patch

# ─── Fast build: compile + patch into cached base ISO ─────────────────────
# This is the default. Only recompiles if .fd files changed.
# Requires a base ISO — run `make base-iso` first if missing.

patch: $(ISO)

$(ISO): $(BASE_ISO) $(KERNEL)
	@echo "[patch] Patching kernel into base ISO..."
	@$(NODE) swap-kernel.js $(BASE_ISO) $(KERNEL) $(ISO) || \
		(echo "[patch] Kernel too large for base ISO. Run: make base-iso" && exit 1)
	@echo "[patch] ISO ready: $(ISO) ($$(wc -c < $(ISO)) bytes)"

# ─── Compile kernel (only if .fd sources changed) ────────────────────────

$(KERNEL_RAW): $(KERNEL_SRCS) | $(BUILD_DIR)
	@echo "[build] Compiling kernel (Fides --boot mode)..."
	@$(FIDES) emit $(KERNEL_DIR)/shell.fd --boot -o $(KERNEL_RAW)
	@echo "[build] Raw kernel: $(KERNEL_RAW) ($$(wc -c < $(KERNEL_RAW)) bytes)"

# Wrap raw binary in ELF using make-elf.js (cross-platform, no gcc/ld needed)
$(KERNEL_ELF): $(KERNEL_RAW)
	@$(NODE) make-elf.js $(KERNEL_RAW) $(KERNEL_ELF) 0x100000 0x100018

$(KERNEL): $(KERNEL_ELF)
	@cp $(KERNEL_ELF) $(KERNEL)
	@echo "[build] Kernel ELF: $(KERNEL) ($$(wc -c < $(KERNEL)) bytes)"

# ─── Base ISO: built once with grub-mkrescue, then cached ─────────────────
# Only needs grub-mkrescue. Uses current kernel so ISO is large enough.
# Rebuild when: first time, GRUB config changes, or kernel outgrows ISO.

# Order-only prereq: kernel must EXIST to build base ISO, but kernel
# changes do NOT trigger a base ISO rebuild (that's the caching).
$(BASE_ISO): | $(KERNEL) $(BUILD_DIR)
	@echo "[base-iso] Building base ISO with grub-mkrescue..."
	@rm -rf $(ISO_DIR)
	@mkdir -p $(ISO_DIR)/boot/grub
	@echo 'set timeout=0' > $(ISO_DIR)/boot/grub/grub.cfg
	@echo 'set default=0' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo 'menuentry "Fides OS" {' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '    multiboot2 /boot/kernel.bin' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '    boot' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '}' >> $(ISO_DIR)/boot/grub/grub.cfg
	@cp $(KERNEL) $(ISO_DIR)/boot/kernel.bin
	$(GRUB_MKRESCUE) -o $(BASE_ISO) $(ISO_DIR) 2>/dev/null || \
		(echo "[base-iso] grub-mkrescue failed. Install grub-common + xorriso." && exit 1)
	@echo "[base-iso] Base ISO cached: $(BASE_ISO) ($$(wc -c < $(BASE_ISO)) bytes)"
	@echo "[base-iso] Future builds will patch into this — run: make"

base-iso: $(BASE_ISO)

# ─── Full ISO rebuild (grub-mkrescue, no caching) ─────────────────────────
# Use when GRUB config changes or base ISO is stale.

iso: $(KERNEL) | $(BUILD_DIR)
	@echo "[iso] Full ISO rebuild with grub-mkrescue..."
	@rm -rf $(ISO_DIR)
	@mkdir -p $(ISO_DIR)/boot/grub
	@echo 'set timeout=0' > $(ISO_DIR)/boot/grub/grub.cfg
	@echo 'set default=0' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo 'menuentry "Fides OS" {' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '    multiboot2 /boot/kernel.bin' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '    boot' >> $(ISO_DIR)/boot/grub/grub.cfg
	@echo '}' >> $(ISO_DIR)/boot/grub/grub.cfg
	@cp $(KERNEL) $(ISO_DIR)/boot/kernel.bin
	$(GRUB_MKRESCUE) -o $(ISO) $(ISO_DIR) 2>/dev/null || \
		(echo "[iso] grub-mkrescue failed. Install grub-common + xorriso." && exit 1)
	@echo "[iso] ISO: $(ISO) ($$(wc -c < $(ISO)) bytes)"

# ─── Run in QEMU ───────────────────────────────────────────────────────────

run: patch
	@echo "[qemu] Launching Fides OS..."
	$(QEMU) $(QEMU_FLAGS)

# ─── Minimal kernel (serial output only) ──────────────────────────────────

$(MINIMAL): $(KERNEL_DIR)/minimal.fd | $(BUILD_DIR)
	@echo "[build] Compiling minimal kernel..."
	@$(FIDES) emit $(KERNEL_DIR)/minimal.fd --boot -o $(MINIMAL)
	@echo "[build] Minimal kernel: $(MINIMAL) ($$(wc -c < $(MINIMAL)) bytes)"

minimal: $(MINIMAL)

# ─── Build directory ───────────────────────────────────────────────────────

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# ─── Clean (keep base ISO cache for fast rebuilds) ───────────────────────

clean:
	@rm -f $(KERNEL_RAW) $(KERNEL_ELF) $(KERNEL) $(MINIMAL) $(ISO)
	@rm -rf $(ISO_DIR)
	@echo "[clean] Build artifacts removed (base ISO cache kept)"

# ─── Distclean (remove everything including cache) ───────────────────────

distclean:
	@rm -rf $(BUILD_DIR) $(ISO_DIR)
	@echo "[distclean] All build artifacts removed (including base ISO cache)"
