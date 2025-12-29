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
print_info() { echo -e "${CYAN}  ${NC} $1"; }

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
    curl -fsSL "$alpine_url" | tar --no-same-owner --no-same-permissions -xzf - -C "$rootfs" 2>/dev/null || \
    curl -fsSL "$alpine_url" | tar -xzf - -C "$rootfs"

    # Install additional packages using apk --root (works in Docker)
    if command -v apk &>/dev/null; then
        print_step "  Installing packages to initramfs..."

        # Initialize apk in the rootfs
        mkdir -p "$rootfs/etc/apk"
        cp /etc/apk/repositories "$rootfs/etc/apk/" 2>/dev/null || \
            echo "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main" > "$rootfs/etc/apk/repositories"

        # Install packages directly to rootfs
        apk --root "$rootfs" --initdb add --no-cache \
            busybox \
            wpa_supplicant \
            hostapd \
            dnsmasq \
            wireless-tools \
            iw \
            libnl3 \
            openssl \
            2>/dev/null && print_ok "Packages installed" || print_warning "Some packages may have failed"
    else
        print_warning "Cannot install packages outside Alpine/Docker"
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

# Download latest Palpable runtime for offline install
download_palpable_os() {
    print_step "Downloading Palpable runtime for offline install..."

    local palpable_dir="$BUILD_DIR/palpable-runtime"
    mkdir -p "$palpable_dir"

    # Download main palpable repo and extract palpable-runtime
    local repo="epode-studio/palpable"
    local release_url="https://api.github.com/repos/${repo}/releases/latest"
    local release_json=$(curl -fsSL "$release_url" 2>/dev/null)

    local tag=""
    local download_url=""

    if [ -n "$release_json" ]; then
        tag=$(echo "$release_json" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
        # Check for palpable-runtime specific release asset
        download_url=$(echo "$release_json" | grep '"browser_download_url"' | grep 'palpable-runtime' | head -1 | cut -d'"' -f4)
    fi

    # Fallback to main branch source tarball
    if [ -z "$download_url" ]; then
        download_url="https://github.com/${repo}/archive/refs/heads/main.tar.gz"
        tag="main"
    fi

    print_info "Downloading from $tag..."
    local tmp_dir="$BUILD_DIR/tmp-download"
    mkdir -p "$tmp_dir"

    if curl -fsSL -o "$tmp_dir/palpable.tar.gz" "$download_url"; then
        # Extract and find palpable-runtime folder
        cd "$tmp_dir"
        tar xzf palpable.tar.gz

        local runtime_src=$(find . -type d -name "palpable-runtime" | head -1)
        if [ -n "$runtime_src" ] && [ -d "$runtime_src" ]; then
            # Create tarball of just the runtime
            cd "$runtime_src"
            tar czf "$palpable_dir/palpable-runtime.tar.gz" .
            print_ok "Extracted palpable-runtime"
        else
            print_warning "palpable-runtime folder not found, bundling full archive"
            cp "$tmp_dir/palpable.tar.gz" "$palpable_dir/palpable-runtime.tar.gz"
        fi

        echo "$tag" > "$palpable_dir/version.txt"
        rm -rf "$tmp_dir"
        print_ok "Downloaded Palpable runtime ($tag)"
    else
        print_warning "Could not download Palpable runtime - will download at boot"
        rm -rf "$tmp_dir"
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
    cp "$boot_dir/"*.bin "$DIST_DIR/" 2>/dev/null || true
    cp "$boot_dir/config.txt" "$DIST_DIR/"
    cp "$boot_dir/cmdline.txt" "$DIST_DIR/"

    # Copy initramfs
    # (already in dist from create_initramfs)

    # Copy user files
    cp "$USER_FILES_DIR/settings.txt" "$DIST_DIR/"
    cp "$USER_FILES_DIR/version.txt" "$DIST_DIR/"

    # Copy bundled Palpable runtime (for offline install)
    if [ -f "$BUILD_DIR/palpable-runtime/palpable-runtime.tar.gz" ]; then
        cp "$BUILD_DIR/palpable-runtime/palpable-runtime.tar.gz" "$DIST_DIR/"
        cp "$BUILD_DIR/palpable-runtime/version.txt" "$DIST_DIR/palpable-runtime-version.txt"
        print_ok "Bundled Palpable runtime included"
    fi

    print_ok "Boot files assembled"
}

# Create distribution zip
create_zip() {
    print_step "Creating distribution zip..."

    local version=$(cat "$USER_FILES_DIR/version.txt" 2>/dev/null | head -1 || echo "1.0.0")
    local output="palpable-bootstrap.zip"

    cd "$DIST_DIR"

    # Create the zip with all boot files at root level
    # Users will drag all files directly to SD card
    zip -j "$output" \
        bootcode.bin \
        start.elf \
        fixup.dat \
        kernel8.img \
        bcm2710-rpi-zero-2-w.dtb \
        config.txt \
        cmdline.txt \
        initramfs.cpio.gz \
        settings.txt \
        "START HERE.txt" \
        version.txt \
        2>/dev/null || true

    # Add bundled runtime for offline install (if available)
    if [ -f palpable-runtime.tar.gz ]; then
        zip -j "$output" palpable-runtime.tar.gz palpable-runtime-version.txt 2>/dev/null || true
        print_info "Bundled offline runtime included"
    fi

    # Add README inside zip
    cat > /tmp/README.txt << 'EOF'
PALPABLE BOOTSTRAP
==================

Copy ALL files to your SD card (FAT32 formatted).

Quick setup:
1. (Optional) Edit settings.txt to add your WiFi
2. Copy all files to SD card root
3. Insert SD card in Raspberry Pi Zero 2 W
4. Power on and wait ~60 seconds
5. Connect to "Palpable-XXXX" WiFi network
6. Follow the setup wizard

For help: https://palpable.technology/download
EOF
    zip -j "$output" /tmp/README.txt 2>/dev/null || true

    cd "$SCRIPT_DIR"

    print_ok "Distribution zip created: $DIST_DIR/$output ($(du -h "$DIST_DIR/$output" | cut -f1))"
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
            # Copy user files to dist
            cp "$USER_FILES_DIR/settings.txt" "$DIST_DIR/"
            cp "$USER_FILES_DIR/START HERE.txt" "$DIST_DIR/"
            cp "$USER_FILES_DIR/version.txt" "$DIST_DIR/"
            create_zip
            print_summary
            ;;
    esac
}

main "$@"
