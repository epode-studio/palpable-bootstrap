#!/bin/bash
#
# Test the captive portal locally without a full QEMU setup
# Serves the portal files on localhost:8080
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PORTAL_DIR="$PROJECT_DIR/initramfs/portal"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo -e "${CYAN}Palpable Captive Portal Test Server${NC}"
echo "====================================="
echo ""

# Check if python3 is available
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found"
    exit 1
fi

# Create mock API responses
mkdir -p "$PORTAL_DIR/api"

# Mock device-info.json
cat > "$PORTAL_DIR/api/device-info.json" << EOF
{
    "deviceId": "test-1234",
    "deviceName": "palpable-test",
    "version": "1.0.0",
    "ip": "192.168.4.1",
    "mac": "00:11:22:33:44:55",
    "wifiMode": "hotspot",
    "wifiSsid": ""
}
EOF

# Mock scan-wifi response (since the CGI scripts won't work with Python's server)
cat > "$PORTAL_DIR/api/scan-wifi.json" << EOF
[
    {"ssid": "MyHomeNetwork", "signal": 85},
    {"ssid": "Neighbor's WiFi", "signal": 60},
    {"ssid": "Coffee Shop", "signal": 45}
]
EOF

echo -e "${GREEN}●${NC} Starting server on http://localhost:8080"
echo -e "${GREEN}●${NC} Portal files: $PORTAL_DIR"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start Python HTTP server
cd "$PORTAL_DIR"
python3 -m http.server 8080
