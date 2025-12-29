#!/bin/sh
#
# Configuration loading for Palpable Bootstrap
#

# Default values
WIFI_SSID=""
WIFI_PASSWORD=""
WIFI_COUNTRY="US"
DEVICE_NAME="palpable"
TIMEZONE="UTC"
IP_ADDRESS=""

# Load settings from boot partition
load_settings() {
    local settings_file="/boot/settings.txt"

    if [ ! -f "$settings_file" ]; then
        log_debug "No settings.txt found, using defaults"
        return
    fi

    log_step "Loading settings from settings.txt"

    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        case "$line" in
            \#*|"") continue ;;
        esac

        # Extract key=value
        key=$(echo "$line" | cut -d'=' -f1 | tr -d ' ')
        value=$(echo "$line" | cut -d'=' -f2-)

        # Trim whitespace
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        case "$key" in
            WIFI_SSID) WIFI_SSID="$value" ;;
            WIFI_PASSWORD) WIFI_PASSWORD="$value" ;;
            WIFI_COUNTRY) WIFI_COUNTRY="$value" ;;
            DEVICE_NAME) DEVICE_NAME="$value" ;;
            TIMEZONE) TIMEZONE="$value" ;;
            IP_ADDRESS) IP_ADDRESS="$value" ;;
        esac
    done < "$settings_file"

    # Sanitize device name (alphanumeric and hyphens only)
    DEVICE_NAME=$(echo "$DEVICE_NAME" | tr -cd 'a-zA-Z0-9-' | cut -c1-63)
    [ -z "$DEVICE_NAME" ] && DEVICE_NAME="palpable"

    log_ok "Settings loaded"
    log_debug "WIFI_SSID=$WIFI_SSID"
    log_debug "DEVICE_NAME=$DEVICE_NAME"
    log_debug "WIFI_COUNTRY=$WIFI_COUNTRY"
}

# Save current settings back to boot partition
save_settings() {
    cat > /boot/settings.txt << EOF
# Palpable Device Settings
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)

WIFI_SSID=$WIFI_SSID
WIFI_PASSWORD=$WIFI_PASSWORD
WIFI_COUNTRY=$WIFI_COUNTRY
DEVICE_NAME=$DEVICE_NAME
TIMEZONE=$TIMEZONE
IP_ADDRESS=$IP_ADDRESS
EOF
    sync
    log_ok "Settings saved"
}

# Get device info as JSON
get_device_info() {
    local ip=$(get_ip_address)
    local mac=$(get_mac_address)
    local version=$(cat /boot/version.txt 2>/dev/null || echo "unknown")

    cat << EOF
{
    "deviceId": "$DEVICE_ID",
    "deviceName": "$DEVICE_NAME",
    "version": "$version",
    "ip": "$ip",
    "mac": "$mac",
    "wifiMode": "$WIFI_MODE",
    "wifiSsid": "$WIFI_SSID"
}
EOF
}
