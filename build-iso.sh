#!/bin/bash
# build-iso.sh — Build a bootable Fides OS ISO without requiring make
#
# This script builds the kernel binary and creates a bootable ISO.
# It requires:
#   - The Fides compiler (fidesc or fides-c3.exe)
#   - grub-mkrescue + xorriso (for ISO creation)
#
# Usage:
#   ./build-iso.sh              # Build kernel + ISO
#   ./build-iso.sh --kernel-only # Build just the kernel binary

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Use self-hosted compiler by default, fall back to Rust bootstrap
FIDES_SELFHOST="/home/medzer/pledge/p-lang/release/fides-c3.exe"
FIDES_RUST="/home/medzer/pledge/p-lang/target/release/fidesc"
if [ -z "${FIDES:-}" ]; then
    if [ -x "$FIDES_SELFHOST" ]; then
        FIDES="$FIDES_SELFHOST"
    else
        FIDES="$FIDES_RUST"
    fi
fi
BUILD_DIR="$SCRIPT_DIR/build"
ISO_DIR="$SCRIPT_DIR/iso"
KERNEL="$BUILD_DIR/kernel.bin"
ISO="$BUILD_DIR/fides-os.iso"
KERNEL_SRC="$SCRIPT_DIR/kernel/minimal.fd"

# Check prerequisites
if [ ! -f "$FIDES" ]; then
    echo "Error: Fides compiler not found at $FIDES"
    echo "Set FIDES env var to point to the compiler."
    exit 1
fi

if ! command -v grub-mkrescue &>/dev/null; then
    echo "Error: grub-mkrescue not found. Install: sudo apt install grub-common xorriso"
    exit 1
fi

mkdir -p "$BUILD_DIR"

# 1. Build kernel
echo "[build] Compiling kernel..."
"$FIDES" emit "$KERNEL_SRC" --boot -o "$KERNEL"
echo "[build] Kernel: $KERNEL ($(wc -c < "$KERNEL") bytes)"

if [ "$1" = "--kernel-only" ]; then
    echo "[build] Kernel-only mode. Done."
    exit 0
fi

# 2. Build ISO
echo "[iso] Building ISO..."
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR/boot/grub"
cp "$KERNEL" "$ISO_DIR/boot/kernel.bin"

cat > "$ISO_DIR/boot/grub/grub.cfg" << 'GRUBCFG'
set timeout=0
set default=0

menuentry "Fides OS" {
    multiboot2 /boot/kernel.bin
    boot
}
GRUBCFG

grub-mkrescue -o "$ISO" "$ISO_DIR" 2>/dev/null
echo "[iso] ISO: $ISO ($(wc -c < "$ISO") bytes)"

# 3. Print run instructions
echo ""
echo "To boot in QEMU:"
echo "  qemu-system-x86_64 -cdrom $ISO -m 256 -serial stdio -no-reboot"
echo ""
echo "Expected output on serial:"
echo "  Hello from Fides OS!"
