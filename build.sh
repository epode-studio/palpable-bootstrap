#!/bin/bash
#
# Palpable Bootstrap Build Script
# Creates a bootable SD card image for Raspberry Pi
#
# Usage:
#   ./build.sh              # Full build
#   ./build.sh --initramfs  # Build initramfs only
#   ./build.sh --zip        # Create distribution zip
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist"
INITRAMFS_DIR="$SCRIPT_DIR/initramfs"
USER_FILES_DIR="$SCRIPT_DIR/user-files"

# Alpine Linux version for base system
ALPINE_VERSION="3.19"
ALPINE_ARCH="aarch64"

# Raspberry Pi kernel (from official repo)
RPI_KERNEL_REPO="https://github.com/raspberrypi/firmware/raw/master/boot"

# Output names
OUTPUT_ZIP="palpable-bootstrap-v$(cat $USER_FILES_DIR/version.txt).zip"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo " ___      _           _    _"
    echo "| _ \\__ _| |_ __  __ _| |__| |___"
    echo "|  _/ _\` | | '_ \\/ _\` | '_ \\ / -_)"
    echo "|_| \\__,_|_| .__/\\__,_|_.__/_\\___|"
    echo "           |_|"
    echo -e "${NC}"
    echo -e "${BOLD}Bootstrap Build Script${NC}"
    echo ""
}

print_step() { echo -e "${CYAN}▸${NC} $1"; }
print_ok() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; exit 1; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }

# Check if running in Docker or has required tools
check_requirements() {
    print_step "Checking build requirements..."

    local missing=()

    for cmd in cpio gzip curl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        print_warning "Missing tools: ${missing[*]}"
        echo ""
        echo "You can build using Docker instead:"
        echo "  docker compose -f docker/docker-compose.yml run builder ./build.sh"
        echo ""

        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    print_ok "Requirements satisfied"
}

# Create directory structure
setup_dirs() {
    print_step "Setting up build directories..."

    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"/{initramfs,boot}
    mkdir -p "$DIST_DIR"

    print_ok "Build directories ready"
}

# Download Raspberry Pi kernel and firmware
download_kernel() {
    print_step "Downloading Raspberry Pi kernel (Pi Zero 2 W / Pi 3)..."

    local boot_dir="$BUILD_DIR/boot"

    # Download kernel for Pi Zero 2 W / Pi 3 (64-bit, Cortex-A53)
    # Pi Zero 2 W uses the same kernel as Pi 3 (bcm2710)
    curl -fsSL -o "$boot_dir/kernel8.img" "$RPI_KERNEL_REPO/kernel8.img"

    # Download device tree blob for Pi Zero 2 W
    curl -fsSL -o "$boot_dir/bcm2710-rpi-zero-2-w.dtb" "$RPI_KERNEL_REPO/bcm2710-rpi-zero-2-w.dtb"

    # Also download Pi 3 DTB for compatibility testing
    curl -fsSL -o "$boot_dir/bcm2710-rpi-3-b.dtb" "$RPI_KERNEL_REPO/bcm2710-rpi-3-b.dtb"

    # Download bootloader files (Pi Zero 2 W uses start.elf, not start4.elf)
    curl -fsSL -o "$boot_dir/start.elf" "$RPI_KERNEL_REPO/start.elf"
    curl -fsSL -o "$boot_dir/fixup.dat" "$RPI_KERNEL_REPO/fixup.dat"
    curl -fsSL -o "$boot_dir/bootcode.bin" "$RPI_KERNEL_REPO/bootcode.bin"

    # Create config.txt for Pi Zero 2 W
    cat > "$boot_dir/config.txt" << EOF
# Palpable Bootstrap Configuration
# Optimized for Raspberry Pi Zero 2 W

# Enable 64-bit mode
arm_64bit=1

# Kernel and initramfs
kernel=kernel8.img
initramfs initramfs.cpio.gz followkernel

# Enable UART for debugging (uses mini UART on GPIO 14/15)
enable_uart=1

# GPU memory (minimal for headless operation)
gpu_mem=16

# Disable splash screen for faster boot
disable_splash=1

# Faster boot
boot_delay=0
initial_turbo=30

# Over-clocking for Pi Zero 2 W (optional, conservative values)
# arm_freq=1200
# over_voltage=2
EOF

    # Create cmdline.txt
    cat > "$boot_dir/cmdline.txt" << EOF
console=serial0,115200 console=tty1 root=/dev/ram0 rootfstype=ramfs rw init=/init
EOF

    print_ok "Kernel and firmware downloaded (Pi Zero 2 W)"
}

# Build Alpine Linux base initramfs
build_initramfs_base() {
    print_step "Building initramfs base (Alpine Linux)..."

    local rootfs="$BUILD_DIR/initramfs"

    # Download Alpine minirootfs
    local alpine_url="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ALPINE_ARCH}/alpine-minirootfs-${ALPINE_VERSION}.0-${ALPINE_ARCH}.tar.gz"

    print_step "  Downloading Alpine minirootfs..."
    curl -fsSL "$alpine_url" | tar -xzf - -C "$rootfs"

    # Install additional packages using apk (if running on Alpine/Docker)
    if command -v apk &>/dev/null && [ -f /etc/alpine-release ]; then
        print_step "  Installing packages..."

        # Mount required filesystems
        mount --bind /dev "$rootfs/dev" 2>/dev/null || true
        mount -t proc proc "$rootfs/proc" 2>/dev/null || true

        # Install packages
        chroot "$rootfs" apk add --no-cache \
            busybox \
            wpa_supplicant \
            hostapd \
            dnsmasq \
            wireless-tools \
            iw \
            bluez \
            bluez-deprecated \
            dropbear \
            2>/dev/null || print_warning "Could not install packages (may need Docker)"

        # Unmount
        umount "$rootfs/proc" 2>/dev/null || true
        umount "$rootfs/dev" 2>/dev/null || true
    else
        print_warning "Cannot install packages outside Docker - base system only"
    fi

    print_ok "Initramfs base ready"
}

# Add Palpable bootstrap files
add_palpable_files() {
    print_step "Adding Palpable bootstrap files..."

    local rootfs="$BUILD_DIR/initramfs"

    # Copy init script
    cp "$INITRAMFS_DIR/init" "$rootfs/init"
    chmod +x "$rootfs/init"

    # Copy library files
    mkdir -p "$rootfs/lib"
    cp "$INITRAMFS_DIR/lib/"*.sh "$rootfs/lib/"
    chmod +x "$rootfs/lib/"*.sh

    # Copy init.d scripts
    mkdir -p "$rootfs/init.d"
    cp "$INITRAMFS_DIR/init.d/"* "$rootfs/init.d/"
    chmod +x "$rootfs/init.d/"*

    # Copy captive portal
    mkdir -p "$rootfs/portal"
    cp -r "$INITRAMFS_DIR/portal/"* "$rootfs/portal/"
    chmod +x "$rootfs/portal/api/"* 2>/dev/null || true

    # Create required directories
    mkdir -p "$rootfs"/{proc,sys,dev,tmp,var/log,var/run,boot,opt/palpable}

    # Create /etc files
    mkdir -p "$rootfs/etc"
    echo "palpable" > "$rootfs/etc/hostname"

    print_ok "Palpable files added"
}

# Create cpio archive
create_initramfs() {
    print_step "Creating initramfs archive..."

    local rootfs="$BUILD_DIR/initramfs"

    # Create cpio archive
    cd "$rootfs"
    find . | cpio -o -H newc 2>/dev/null | gzip > "$DIST_DIR/initramfs.cpio.gz"

    print_ok "Initramfs created: $(du -h "$DIST_DIR/initramfs.cpio.gz" | cut -f1)"
}

# Download latest Palpable OS release for offline install
download_palpable_os() {
    print_step "Downloading latest Palpable OS release..."

    local palpable_dir="$BUILD_DIR/palpable-os"
    mkdir -p "$palpable_dir"

    # Try to get latest release from GitHub
    local release_url="https://api.github.com/repos/epode-studio/palpable-os/releases/latest"
    local release_json=$(curl -fsSL "$release_url" 2>/dev/null)

    if [ -n "$release_json" ]; then
        local tag=$(echo "$release_json" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
        local download_url=$(echo "$release_json" | grep '"browser_download_url"' | grep -E '\.(tar\.gz|zip)"' | head -1 | cut -d'"' -f4)

        if [ -n "$download_url" ]; then
            print_info "Downloading $tag from release..."
            curl -fsSL -o "$palpable_dir/palpable-os.tar.gz" "$download_url"
        else
            # Fallback to source tarball
            download_url="https://github.com/epode-studio/palpable-os/archive/refs/tags/${tag}.tar.gz"
            print_info "Downloading $tag source tarball..."
            curl -fsSL -o "$palpable_dir/palpable-os.tar.gz" "$download_url"
        fi
        echo "$tag" > "$palpable_dir/version.txt"
        print_ok "Downloaded Palpable OS $tag"
    else
        # Fallback to main branch
        print_warning "No release found, downloading main branch..."
        curl -fsSL -o "$palpable_dir/palpable-os.tar.gz" \
            "https://github.com/epode-studio/palpable-os/archive/refs/heads/main.tar.gz"
        echo "main" > "$palpable_dir/version.txt"
        print_ok "Downloaded Palpable OS (main branch)"
    fi
}

# Assemble boot files
assemble_boot() {
    print_step "Assembling boot files..."

    local boot_dir="$BUILD_DIR/boot"

    # Copy kernel and firmware to dist
    cp "$boot_dir/"*.img "$DIST_DIR/" 2>/dev/null || true
    cp "$boot_dir/"*.dtb "$DIST_DIR/" 2>/dev/null || true
    cp "$boot_dir/"*.elf "$DIST_DIR/" 2>/dev/null || true
    cp "$boot_dir/"*.dat "$DIST_DIR/" 2>/dev/null || true
    cp "$boot_dir/config.txt" "$DIST_DIR/"
    cp "$boot_dir/cmdline.txt" "$DIST_DIR/"

    # Copy initramfs
    # (already in dist from create_initramfs)

    # Copy user files
    cp "$USER_FILES_DIR/settings.txt" "$DIST_DIR/"
    cp "$USER_FILES_DIR/version.txt" "$DIST_DIR/"

    # Copy bundled Palpable OS (for offline install)
    if [ -f "$BUILD_DIR/palpable-os/palpable-os.tar.gz" ]; then
        cp "$BUILD_DIR/palpable-os/palpable-os.tar.gz" "$DIST_DIR/"
        cp "$BUILD_DIR/palpable-os/version.txt" "$DIST_DIR/palpable-os-version.txt"
        print_ok "Bundled Palpable OS included"
    fi

    print_ok "Boot files assembled"
}

# Create distribution zip
create_zip() {
    print_step "Creating distribution zip..."

    cd "$DIST_DIR"

    # Create boot folder for user
    mkdir -p boot
    cp *.img *.dtb *.elf *.dat *.txt *.gz boot/ 2>/dev/null || true

    # Add README
    cat > boot/README.txt << EOF
PALPABLE OS BOOT FILES
======================

Copy ALL files from this folder to a FAT32-formatted SD card.

Quick setup:
1. Edit settings.txt to add your WiFi
2. Copy all files to SD card root
3. Insert in Raspberry Pi and power on

For help: https://palpable.technology/download
EOF

    # Copy START HERE
    cp "$USER_FILES_DIR/START HERE.txt" ./

    # Create zip
    cd "$SCRIPT_DIR"
    zip -r "$DIST_DIR/$OUTPUT_ZIP" \
        -j "$DIST_DIR/boot/" \
        "$USER_FILES_DIR/START HERE.txt" \
        "$USER_FILES_DIR/settings.txt"

    # Cleanup
    rm -rf "$DIST_DIR/boot"

    print_ok "Distribution zip created: $OUTPUT_ZIP"
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}Build complete!${NC}"
    echo ""
    echo "Output files in dist/:"
    ls -lh "$DIST_DIR" 2>/dev/null | tail -n +2
    echo ""
    echo "To test with QEMU:"
    echo "  ./test/run-qemu.sh"
    echo ""
    echo "To create distribution zip:"
    echo "  ./build.sh --zip"
    echo ""
}

# Main
main() {
    print_header

    case "${1:-}" in
        --initramfs)
            check_requirements
            setup_dirs
            build_initramfs_base
            add_palpable_files
            create_initramfs
            ;;
        --zip)
            create_zip
            ;;
        *)
            check_requirements
            setup_dirs
            download_kernel
            download_palpable_os
            build_initramfs_base
            add_palpable_files
            create_initramfs
            assemble_boot
            print_summary
            ;;
    esac
}

main "$@"
