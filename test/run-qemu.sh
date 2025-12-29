#!/bin/bash
#
# Run Palpable Bootstrap in QEMU for testing
# Simulates a Raspberry Pi Zero 2 W environment (BCM2710 / Cortex-A53)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${CYAN}●${NC} $1"; }
print_ok() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }

# Check for required files
check_files() {
    local missing=()

    # Pi Zero 2 W uses the same kernel as Pi 3 (64-bit)
    if [ ! -f "$DIST_DIR/kernel8.img" ]; then
        missing+=("kernel8.img")
    fi

    if [ ! -f "$DIST_DIR/initramfs.cpio.gz" ]; then
        missing+=("initramfs.cpio.gz")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required files in dist/: ${missing[*]}"
        echo ""
        echo "Run ./build.sh first to create the boot image."
        exit 1
    fi
}

# Check for QEMU
check_qemu() {
    if ! command -v qemu-system-aarch64 &>/dev/null; then
        print_error "QEMU not found"
        echo ""
        echo "Install with:"
        echo "  macOS: brew install qemu"
        echo "  Ubuntu: sudo apt install qemu-system-arm"
        exit 1
    fi
}

# Run QEMU
run_qemu() {
    print_info "Starting QEMU emulation (Pi Zero 2 W / Cortex-A53)..."
    echo ""
    echo "Note: Pi Zero 2 W has 512MB RAM and Cortex-A53 quad-core"
    echo "Press Ctrl+A then X to exit"
    echo ""

    # Create a temporary FAT image for the boot partition
    BOOT_IMG=$(mktemp).img
    dd if=/dev/zero of="$BOOT_IMG" bs=1M count=64 2>/dev/null
    mkfs.vfat "$BOOT_IMG" 2>/dev/null

    # Copy boot files
    mcopy -i "$BOOT_IMG" "$DIST_DIR/kernel8.img" ::/kernel8.img 2>/dev/null || true
    mcopy -i "$BOOT_IMG" "$PROJECT_DIR/user-files/settings.txt" ::/settings.txt 2>/dev/null || true
    mcopy -i "$BOOT_IMG" "$PROJECT_DIR/user-files/version.txt" ::/version.txt 2>/dev/null || true

    # Run QEMU - simulating Pi Zero 2 W (Cortex-A53, 512MB RAM)
    # Note: QEMU doesn't have a specific Pi Zero 2 W machine type,
    # so we use 'virt' with Cortex-A53 and 512MB RAM to approximate
    qemu-system-aarch64 \
        -machine virt \
        -cpu cortex-a53 \
        -smp 4 \
        -m 512 \
        -kernel "$DIST_DIR/kernel8.img" \
        -initrd "$DIST_DIR/initramfs.cpio.gz" \
        -drive file="$BOOT_IMG",format=raw,if=virtio \
        -append "console=ttyAMA0 root=/dev/ram0 boot=/dev/vda" \
        -netdev user,id=net0,hostfwd=tcp::8080-:80,hostfwd=tcp::2222-:22 \
        -device virtio-net-pci,netdev=net0 \
        -nographic

    # Cleanup
    rm -f "$BOOT_IMG"
}

# Main
main() {
    echo ""
    echo "Palpable Bootstrap QEMU Test"
    echo "============================"
    echo ""

    check_qemu
    check_files
    run_qemu
}

main "$@"
