#!/bin/sh
#
# Palpable OS/Runtime Installer
# Downloads and installs Palpable OS or agent from GitHub
#
# Supports two installation modes:
# 1. Full OS image (Alpine-based) - for initial setup
# 2. Agent-only update - for OTA updates
#

# Repositories
PALPABLE_REPO="epode-studio/palpable"
PALPABLE_OS_REPO="epode-studio/palpable-os"
PALPABLE_DIR="/opt/palpable"
DOWNLOAD_DIR="/tmp/palpable-download"

# Palpable OS image settings
OS_IMAGE_NAME="palpable-os"
DATA_PARTITION="/dev/mmcblk0p4"
DATA_MOUNT="/data"

# Download and install Palpable runtime from GitHub
install_palpable_os() {
    log_step "Installing Palpable runtime..."

    mkdir -p "$DOWNLOAD_DIR"
    mkdir -p "$PALPABLE_DIR"

    local tarball=""
    local version="unknown"

    # First, check for bundled runtime on boot partition (offline install)
    if [ -f /boot/palpable-runtime.tar.gz ]; then
        log_info "Using bundled Palpable runtime (offline install)"
        tarball="/boot/palpable-runtime.tar.gz"
        version=$(cat /boot/palpable-runtime-version.txt 2>/dev/null || echo "bundled")

        # Extract bundled runtime directly
        cd "$PALPABLE_DIR"
        tar xzf "$tarball" --strip-components=1 2>/dev/null || \
        tar xzf "$tarball" -C . 2>/dev/null
        log_ok "Palpable runtime installed (version: $version)"
        return 0
    fi

    # Download from GitHub - get the main repo and extract palpable-runtime
    log_info "Fetching latest release info..."
    local release_url="https://api.github.com/repos/${PALPABLE_REPO}/releases/latest"
    local release_json=$(wget -q -O - "$release_url" 2>/dev/null)

    local tag=""
    local download_url=""

    if [ -n "$release_json" ]; then
        tag=$(echo "$release_json" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
        # Check for a palpable-runtime release asset
        download_url=$(echo "$release_json" | grep '"browser_download_url"' | grep 'palpable-runtime' | head -1 | cut -d'"' -f4)
    fi

    if [ -z "$download_url" ]; then
        # Fallback to main branch source tarball
        log_info "Downloading from main branch..."
        download_url="https://github.com/${PALPABLE_REPO}/archive/refs/heads/main.tar.gz"
        tag="main"
    fi

    log_info "Downloading Palpable runtime ($tag)..."

    if wget -q -O "$DOWNLOAD_DIR/palpable.tar.gz" "$download_url"; then
        tarball="$DOWNLOAD_DIR/palpable.tar.gz"
        version="$tag"
        log_ok "Download complete"
    else
        log_error "Failed to download Palpable runtime"
        return 1
    fi

    # Extract palpable-runtime subfolder from the main repo archive
    log_step "Extracting Palpable runtime $version..."
    cd "$DOWNLOAD_DIR"
    tar xzf "$tarball"

    # Find and copy the palpable-runtime directory
    local runtime_src=$(find . -type d -name "palpable-runtime" | head -1)
    if [ -n "$runtime_src" ] && [ -d "$runtime_src" ]; then
        cp -r "$runtime_src"/* "$PALPABLE_DIR/"
        log_ok "Palpable runtime installed (version: $version)"
    else
        # If no palpable-runtime folder, assume root is the runtime
        tar xzf "$tarball" --strip-components=1 -C "$PALPABLE_DIR" 2>/dev/null
        log_ok "Palpable installed (version: $version)"
    fi

    # Cleanup
    rm -rf "$DOWNLOAD_DIR"
    return 0
}

# Fallback: Install from main branch (deprecated, use install_palpable_os)
install_from_main_branch() {
    log_step "Downloading from main branch..."
    install_palpable_os
    return $?
}

# Install Node.js runtime (for Alpine Linux)
install_nodejs() {
    log_step "Installing Node.js runtime..."

    if command -v node &>/dev/null; then
        log_ok "Node.js already installed: $(node --version)"
        return 0
    fi

    # Install from Alpine packages
    if command -v apk &>/dev/null; then
        apk add --no-cache nodejs npm
    else
        log_warning "Cannot install Node.js - apk not available"
        return 1
    fi

    log_ok "Node.js installed: $(node --version)"
}

# Install dependencies and start service
setup_palpable_service() {
    log_step "Setting up Palpable service..."

    cd "$PALPABLE_DIR"

    # Install npm dependencies if package.json exists
    if [ -f "package.json" ]; then
        log_info "Installing Node.js dependencies..."
        npm install --production --silent 2>/dev/null || true
    fi

    # Copy device configuration from boot partition
    if [ -f /boot/claim.json ]; then
        mkdir -p "$PALPABLE_DIR/config"
        cp /boot/claim.json "$PALPABLE_DIR/config/claim.json"
        log_ok "Device claim configuration copied"
    fi

    if [ -f /boot/palpable-device.json ]; then
        mkdir -p "$PALPABLE_DIR/config"
        cp /boot/palpable-device.json "$PALPABLE_DIR/config/device.json"
        log_ok "Device configuration copied"
    fi

    # Create config from settings.txt
    if [ -f /boot/settings.txt ]; then
        cat > "$PALPABLE_DIR/config/bootstrap.json" << EOF
{
    "deviceId": "$DEVICE_ID",
    "deviceName": "$DEVICE_NAME",
    "wifiSsid": "$WIFI_SSID",
    "timezone": "$TIMEZONE",
    "bootstrapVersion": "$(cat /boot/version.txt 2>/dev/null || echo '1.0.0')",
    "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    fi

    log_ok "Palpable service configured"
}

# Download and install the Go-based palpable-agent
install_palpable_agent() {
    log_step "Installing Palpable agent (Go binary)..."

    mkdir -p "$DOWNLOAD_DIR"
    mkdir -p /usr/bin

    # Check for bundled agent first
    if [ -f /boot/palpable-agent ]; then
        log_info "Using bundled Palpable agent"
        cp /boot/palpable-agent /usr/bin/palpable-agent
        chmod +x /usr/bin/palpable-agent
        log_ok "Palpable agent installed from boot partition"
        return 0
    fi

    # Download from GitHub releases
    log_info "Fetching latest agent release..."
    local release_url="https://api.github.com/repos/${PALPABLE_OS_REPO}/releases/latest"
    local release_json=$(wget -q -O - "$release_url" 2>/dev/null)

    local download_url=""
    local version="unknown"

    if [ -n "$release_json" ]; then
        version=$(echo "$release_json" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
        download_url=$(echo "$release_json" | grep '"browser_download_url"' | grep 'palpable-agent.*arm64' | head -1 | cut -d'"' -f4)
    fi

    if [ -z "$download_url" ]; then
        # Fallback to main palpable repo
        log_info "Trying main palpable repo..."
        release_url="https://api.github.com/repos/${PALPABLE_REPO}/releases/latest"
        release_json=$(wget -q -O - "$release_url" 2>/dev/null)
        if [ -n "$release_json" ]; then
            version=$(echo "$release_json" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
            download_url=$(echo "$release_json" | grep '"browser_download_url"' | grep 'palpable-agent.*arm64' | head -1 | cut -d'"' -f4)
        fi
    fi

    if [ -n "$download_url" ]; then
        log_info "Downloading palpable-agent ($version)..."
        if wget -q -O /usr/bin/palpable-agent "$download_url"; then
            chmod +x /usr/bin/palpable-agent
            log_ok "Palpable agent installed ($version)"
            return 0
        fi
    fi

    log_error "Failed to download Palpable agent"
    return 1
}

# Setup data partition and config
setup_data_partition() {
    log_step "Setting up data partition..."

    # Check if data partition exists
    if [ ! -b "$DATA_PARTITION" ]; then
        log_warning "Data partition $DATA_PARTITION not found"
        # Use tmpfs fallback
        mkdir -p "$DATA_MOUNT"
        mount -t tmpfs tmpfs "$DATA_MOUNT" -o size=64m
    else
        mkdir -p "$DATA_MOUNT"
        mount "$DATA_PARTITION" "$DATA_MOUNT" 2>/dev/null || {
            log_info "Formatting data partition..."
            mkfs.ext4 -L palpable-data "$DATA_PARTITION" 2>/dev/null
            mount "$DATA_PARTITION" "$DATA_MOUNT"
        }
    fi

    # Create directory structure
    mkdir -p "$DATA_MOUNT/palpable"/{config,cache,logs}

    log_ok "Data partition ready"
}

# Copy configuration from boot partition to data
migrate_config() {
    log_step "Migrating configuration..."

    local config_dir="$DATA_MOUNT/palpable/config"
    mkdir -p "$config_dir"

    # Copy claim.json (device registration)
    if [ -f /boot/claim.json ]; then
        cp /boot/claim.json "$config_dir/claim.json"
        log_ok "Device claim migrated"
    fi

    # Copy bootstrap.json (WiFi, device name, etc.)
    if [ -f /boot/palpable-device.json ]; then
        cp /boot/palpable-device.json "$config_dir/bootstrap.json"
        log_ok "Device config migrated"
    fi

    # Create config from settings.txt if present
    if [ -f /boot/settings.txt ]; then
        . /boot/settings.txt 2>/dev/null || true

        cat > "$config_dir/bootstrap.json" << EOF
{
    "deviceId": "${DEVICE_ID:-}",
    "deviceName": "${DEVICE_NAME:-Palpable Device}",
    "wifiSsid": "${WIFI_SSID:-}",
    "timezone": "${TIMEZONE:-UTC}",
    "bootstrapVersion": "$(cat /boot/version.txt 2>/dev/null || echo '2.0.0')",
    "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        log_ok "Settings migrated to config"
    fi

    sync
}

# Full installation sequence (new Go-based agent)
run_full_install() {
    log_info "Starting Palpable installation..."
    echo ""

    # Setup data partition first
    setup_data_partition

    # Install the Go agent (no Node.js needed!)
    install_palpable_agent || {
        log_warning "Agent install failed, trying legacy runtime..."
        install_nodejs || true
        install_palpable_os || return 1
    }

    # Migrate config
    migrate_config

    echo ""
    log_ok "Palpable installation complete!"

    # Save installation status
    echo "installed" > /boot/palpable-status.txt
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /boot/palpable-status.txt
    sync
}

# Legacy installation (Node.js runtime) - for backwards compatibility
run_legacy_install() {
    log_info "Starting legacy Palpable runtime installation..."
    echo ""

    install_nodejs || true
    install_palpable_os || return 1
    setup_palpable_service

    echo ""
    log_ok "Palpable runtime installation complete!"

    echo "installed" > /boot/palpable-status.txt
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /boot/palpable-status.txt
    sync
}
