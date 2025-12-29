#!/bin/sh
#
# Palpable OS Installer
# Downloads and installs Palpable OS from GitHub releases
#

PALPABLE_REPO="epode-studio/palpable-os"
PALPABLE_DIR="/opt/palpable"
DOWNLOAD_DIR="/tmp/palpable-download"

# Download and install Palpable OS from GitHub
install_palpable_os() {
    log_step "Installing Palpable OS..."

    mkdir -p "$DOWNLOAD_DIR"
    mkdir -p "$PALPABLE_DIR"

    local tarball=""
    local version="unknown"

    # First, check for bundled Palpable OS on boot partition (offline install)
    if [ -f /boot/palpable-os.tar.gz ]; then
        log_info "Using bundled Palpable OS (offline install)"
        tarball="/boot/palpable-os.tar.gz"
        version=$(cat /boot/palpable-os-version.txt 2>/dev/null || echo "bundled")
    else
        # Download from GitHub
        log_info "Fetching latest release info..."
        local release_url="https://api.github.com/repos/${PALPABLE_REPO}/releases/latest"
        local release_json=$(wget -q -O - "$release_url" 2>/dev/null)

        if [ -z "$release_json" ]; then
            log_warning "Could not fetch release info, using main branch..."
            install_from_main_branch
            return $?
        fi

        # Extract download URL for tarball
        local tag=$(echo "$release_json" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
        local download_url=$(echo "$release_json" | grep '"browser_download_url"' | grep 'palpable-runtime' | head -1 | cut -d'"' -f4)

        if [ -z "$download_url" ]; then
            # Fallback to tarball
            download_url="https://github.com/${PALPABLE_REPO}/archive/refs/tags/${tag}.tar.gz"
        fi

        log_info "Downloading Palpable OS $tag..."
        log_debug "URL: $download_url"

        if wget -q -O "$DOWNLOAD_DIR/palpable.tar.gz" "$download_url"; then
            tarball="$DOWNLOAD_DIR/palpable.tar.gz"
            version="$tag"
            log_ok "Download complete"
        else
            log_warning "Download failed, trying main branch..."
            install_from_main_branch
            return $?
        fi
    fi

    # Extract
    log_step "Extracting Palpable OS $version..."
    cd "$PALPABLE_DIR"
    tar xzf "$tarball" --strip-components=1 2>/dev/null || \
    tar xzf "$tarball" --strip-components=2 -C . 2>/dev/null

    # Cleanup downloaded file (but not bundled)
    [ -d "$DOWNLOAD_DIR" ] && rm -rf "$DOWNLOAD_DIR"

    log_ok "Palpable OS installed (version: $version)"
    return 0
}

# Fallback: Install from main branch
install_from_main_branch() {
    log_step "Downloading from main branch..."

    local url="https://github.com/${PALPABLE_REPO}/archive/refs/heads/main.tar.gz"

    if wget -q -O "$DOWNLOAD_DIR/palpable.tar.gz" "$url"; then
        cd "$PALPABLE_DIR"
        tar xzf "$DOWNLOAD_DIR/palpable.tar.gz" --strip-components=1
        rm -rf "$DOWNLOAD_DIR"
        log_ok "Installed from main branch"
        return 0
    else
        log_error "Failed to download Palpable OS"
        return 1
    fi
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

# Full installation sequence
run_full_install() {
    log_info "Starting Palpable OS installation..."
    echo ""

    install_nodejs || true
    install_palpable_os || return 1
    setup_palpable_service

    echo ""
    log_ok "Palpable OS installation complete!"

    # Save installation status
    echo "installed" > /boot/palpable-status.txt
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /boot/palpable-status.txt
    sync
}
