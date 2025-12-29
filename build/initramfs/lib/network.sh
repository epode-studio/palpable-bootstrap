#!/bin/sh
#
# Network helpers for Palpable Bootstrap
#

WLAN_IFACE="wlan0"
AP_IP="192.168.4.1"
AP_SUBNET="192.168.4.0/24"
AP_DHCP_START="192.168.4.10"
AP_DHCP_END="192.168.4.100"

# Get current IP address
get_ip_address() {
    ip -4 addr show "$WLAN_IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1
}

# Get MAC address
get_mac_address() {
    cat "/sys/class/net/$WLAN_IFACE/address" 2>/dev/null
}

# Connect to WiFi as client
connect_wifi() {
    local ssid="$1"
    local password="$2"
    local country="$3"

    # Set regulatory domain
    if [ -n "$country" ]; then
        iw reg set "$country" 2>/dev/null
    fi

    # Bring up interface
    ip link set "$WLAN_IFACE" up

    # Create wpa_supplicant config
    local wpa_conf="/tmp/wpa_supplicant.conf"

    if [ -n "$password" ]; then
        cat > "$wpa_conf" << EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=$country

network={
    ssid="$ssid"
    psk="$password"
    key_mgmt=WPA-PSK
}
EOF
    else
        cat > "$wpa_conf" << EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=$country

network={
    ssid="$ssid"
    key_mgmt=NONE
}
EOF
    fi

    # Start wpa_supplicant
    mkdir -p /var/run/wpa_supplicant
    wpa_supplicant -B -i "$WLAN_IFACE" -c "$wpa_conf" -D nl80211

    # Wait for connection (up to 30 seconds)
    local timeout=30
    while [ $timeout -gt 0 ]; do
        if wpa_cli -i "$WLAN_IFACE" status 2>/dev/null | grep -q "wpa_state=COMPLETED"; then
            break
        fi
        sleep 1
        timeout=$((timeout - 1))
    done

    if [ $timeout -eq 0 ]; then
        wpa_cli -i "$WLAN_IFACE" terminate 2>/dev/null
        return 1
    fi

    # Get IP via DHCP
    if [ -n "$IP_ADDRESS" ]; then
        # Static IP
        ip addr add "$IP_ADDRESS/24" dev "$WLAN_IFACE"
        # TODO: Add gateway/DNS from settings
    else
        # DHCP
        udhcpc -i "$WLAN_IFACE" -q -t 10 -n
    fi

    return 0
}

# Start WiFi hotspot
start_hotspot() {
    # Get last 4 chars of MAC for unique SSID
    local mac_suffix=$(get_mac_address | tr -d ':' | tail -c 5 | tr '[:lower:]' '[:upper:]')
    local ap_ssid="Palpable-$mac_suffix"

    log_step "Starting hotspot: $ap_ssid"

    # Stop any existing wpa_supplicant
    killall wpa_supplicant 2>/dev/null

    # Bring up interface
    ip link set "$WLAN_IFACE" up

    # Configure static IP for AP
    ip addr flush dev "$WLAN_IFACE"
    ip addr add "$AP_IP/24" dev "$WLAN_IFACE"

    # Create hostapd config
    cat > /tmp/hostapd.conf << EOF
interface=$WLAN_IFACE
driver=nl80211
ssid=$ap_ssid
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=0
EOF

    # Start hostapd
    hostapd -B /tmp/hostapd.conf

    # Start DHCP server
    cat > /tmp/dnsmasq.conf << EOF
interface=$WLAN_IFACE
dhcp-range=$AP_DHCP_START,$AP_DHCP_END,255.255.255.0,24h
dhcp-option=3,$AP_IP
dhcp-option=6,$AP_IP
address=/#/$AP_IP
EOF

    dnsmasq -C /tmp/dnsmasq.conf

    # Set hostname
    echo "$ap_ssid" > /etc/hostname
    hostname "$ap_ssid"

    log_ok "Hotspot started: $ap_ssid"
}

# Stop hotspot and switch to client mode
stop_hotspot() {
    killall hostapd 2>/dev/null
    killall dnsmasq 2>/dev/null
    ip addr flush dev "$WLAN_IFACE"
}

# Start captive portal web server
start_captive_portal() {
    # httpd from busybox
    mkdir -p /www
    cp -r /portal/* /www/ 2>/dev/null

    # Generate device info JSON for the portal
    get_device_info > /www/api/device-info.json

    # Start web server
    httpd -p 80 -h /www

    # Also listen on common captive portal detection URLs
    # These will redirect to our portal
}

# Start Bluetooth LE beacon for device discovery
start_bluetooth_beacon() {
    local device_id="$1"

    # Check if Bluetooth is available
    if [ ! -d /sys/class/bluetooth ]; then
        log_warning "Bluetooth not available"
        return 1
    fi

    # Bring up Bluetooth
    hciconfig hci0 up 2>/dev/null || return 1

    # Set device name
    hciconfig hci0 name "Palpable-${device_id}" 2>/dev/null

    # Enable LE advertising
    # This creates a beacon that the mobile app can discover
    hciconfig hci0 leadv 3 2>/dev/null

    # Set advertising data (device ID in manufacturer data)
    # Format: Flags(3) + Complete Local Name + Manufacturer Specific Data
    local adv_data="02 01 06 09 09 50 61 6c 70 61 62 6c 65"
    hcitool -i hci0 cmd 0x08 0x0008 $adv_data 2>/dev/null

    log_ok "Bluetooth beacon started"
}

# Check for OTA updates
check_for_updates() {
    local current_version=$(cat /boot/version.txt 2>/dev/null || echo "0.0.0")
    local update_url="https://api.palpable.technology/bootstrap/version"

    log_debug "Checking for updates (current: $current_version)"

    # Download version info
    local latest=$(wget -q -O - "$update_url" 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$latest" ]; then
        log_debug "Could not check for updates"
        return 1
    fi

    if [ "$latest" != "$current_version" ]; then
        log_info "Update available: $latest (current: $current_version)"
        # TODO: Download and apply update
    else
        log_debug "System is up to date"
    fi
}
