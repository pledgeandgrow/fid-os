#!/bin/bash
# tests/qemu-integration.sh — QEMU integration test for Fides OS
#
# Boots the OS in QEMU and checks serial output for expected strings.
# Returns 0 if all checks pass, 1 if any fail.
#
# Usage: ./tests/qemu-integration.sh

set -e

OS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
QEMU_TIMEOUT=30
PASS=0
FAIL=0

# Build the OS if needed
if [ ! -f "$OS_DIR/build/fides-os.iso" ]; then
    echo "[BUILD] Building Fides OS..."
    cd "$OS_DIR"
    FIDES="${FIDES:-/home/medzer/pledge/p-lang/target/release/fidesc}"
    "$FIDES" emit kernel/shell.fd --boot -o build/kernel-raw.bin 2>/dev/null
    echo '.section .text' > build/kernel_wrap.S
    echo '.global _start' >> build/kernel_wrap.S
    echo '_start:' >> build/kernel_wrap.S
    echo '    .incbin "build/kernel-raw.bin"' >> build/kernel_wrap.S
    echo 'PHDRS { text PT_LOAD; }' > build/kernel_wrap.ld
    echo 'SECTIONS { . = 0x100000; .text : { *(.text) } :text }' >> build/kernel_wrap.ld
    gcc -c -o build/kernel_wrap.o build/kernel_wrap.S
    ld -T build/kernel_wrap.ld -e 0x100018 -N -o build/kernel.elf build/kernel_wrap.o 2>/dev/null
    cp build/kernel.elf iso/boot/kernel.bin
    grub-mkrescue -o build/fides-os.iso iso 2>/dev/null
fi

# Run QEMU and capture output
echo "[TEST] Booting Fides OS in QEMU..."
OUTPUT=$(timeout $QEMU_TIMEOUT qemu-system-x86_64 \
    -cdrom "$OS_DIR/build/fides-os.iso" \
    -hda "$OS_DIR/build/testdisk.img" \
    -boot d -m 256 -serial stdio -no-reboot -display none 2>/dev/null || true)

# Check functions
check() {
    local name="$1"
    local pattern="$2"
    if echo "$OUTPUT" | grep -q "$pattern"; then
        echo "  [PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $name (expected: $pattern)"
        FAIL=$((FAIL + 1))
    fi
}

echo "[TEST] Checking output..."

# Boot and banner
check "OS boots" "Fides OS"
check "Auto-test runs" "AUTO TEST"

# Memory
check "Memory info" "kernel at 0x100000"
check "VGA buffer" "0xb8000"

# Timer
check "Timer ticks" "Timer ticks"

# RTC
check "RTC time" "Time:"
check "RTC date" "Date:"

# User mode
check "User program" "Hello from user!"
check "User exit" "Exit(0x0)"

# ELF loading
check "ELF loading" "Hello from ELF!"
check "ELF entry" "Entry: 0x10078"

# Initrd
check "Initrd files" "HELLO.TXT"
check "Initrd size" "18 B"

# PCI
check "PCI enumeration" "PCI Devices"
check "PCI E1000" "0x100e"

# VM
check "VM mapping" "0xdeadbeef"

# Heap
check "Heap alloc" "p3:0x300000"

# Summary
echo ""
echo "[RESULT] $PASS passed, $FAIL failed"
if [ $FAIL -eq 0 ]; then
    echo "[RESULT] ALL TESTS PASSED"
    exit 0
else
    echo "[RESULT] SOME TESTS FAILED"
    exit 1
fi
