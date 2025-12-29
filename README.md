# Palpable Bootstrap

A single downloadable zip file that boots a Raspberry Pi Zero 2 W into Palpable OS without requiring any flashing tools.

## How It Works

1. **User downloads a zip** from palpable.technology/download
2. **User copies contents to SD card** (FAT32 formatted)
3. **Pi boots into Alpine Linux initramfs** with captive portal
4. **User configures WiFi** via hotspot captive portal or Bluetooth
5. **Device claims itself** to user's Palpable account
6. **OTA updates** keep the system current

## For Users

### Quick Start

1. Download the zip from [palpable.technology/download](https://palpable.technology/download)
2. Format an SD card as FAT32
3. Extract the zip and copy the `boot` folder contents to the SD card root
4. (Optional) Edit `settings.txt` with your WiFi credentials
5. Insert SD card into Pi Zero 2 W and power on
6. Connect to `Palpable-XXXX` WiFi network
7. Follow the setup wizard at http://192.168.4.1

### Files in the Zip

```
START HERE.txt    # Quick start instructions
settings.txt      # WiFi and device configuration
boot/             # Boot files to copy to SD card
```

## For Developers

### Project Structure

```
palpable-bootstrap/
├── build.sh              # Main build script
├── docker/               # Docker build environment
│   ├── Dockerfile
│   └── docker-compose.yml
├── test/                 # Testing utilities
│   ├── run-qemu.sh       # QEMU Pi Zero 2 W simulation
│   └── test-portal.sh    # Local captive portal testing
├── initramfs/            # Boot system files
│   ├── init              # Main init script (PID 1)
│   ├── lib/              # Shell helper libraries
│   ├── init.d/           # Service scripts
│   └── portal/           # Captive portal web UI
├── user-files/           # Files included in zip
│   ├── START HERE.txt
│   ├── settings.txt
│   └── version.txt
├── build/                # Build output (gitignored)
└── dist/                 # Distribution files (gitignored)
```

### Building

#### With Docker (recommended)

```bash
docker compose -f docker/docker-compose.yml run builder ./build.sh
```

#### Locally (requires Alpine Linux or equivalent tools)

```bash
./build.sh
```

#### Build Options

```bash
./build.sh              # Full build
./build.sh --initramfs  # Build initramfs only
./build.sh --zip        # Create distribution zip
```

### Testing

#### Local Captive Portal

```bash
./test/test-portal.sh
# Open http://localhost:8080
```

#### QEMU Emulation

```bash
./test/run-qemu.sh
# Simulates Pi Zero 2 W (Cortex-A53, 512MB RAM)
```

### Key Components

#### Init Script (`initramfs/init`)

The init script runs as PID 1 and:
- Mounts essential filesystems
- Loads user settings from `settings.txt`
- Attempts WiFi connection or starts hotspot
- Starts captive portal for configuration
- Enables Bluetooth beacon for app discovery
- Manages the Palpable agent service

#### Captive Portal (`initramfs/portal/`)

A lightweight web interface served by busybox httpd:
- Scans and connects to WiFi networks
- Device claiming with 6-digit codes
- Mobile-first responsive design

#### Network Helpers (`initramfs/lib/network.sh`)

Handles:
- WiFi client connection (wpa_supplicant)
- Hotspot mode (hostapd + dnsmasq)
- Captive portal DNS hijacking
- Bluetooth LE advertising

### Backend API

The device claiming system requires these API endpoints in the main Palpable app:

- `POST /api/devices/claim-code` - Generate 6-digit code (auth required)
- `POST /api/devices/claim` - Claim device with code (public)
- `GET /api/bootstrap/version` - Check for OTA updates

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    User's Computer                          │
│  ┌─────────────┐    ┌─────────────┐    ┌───────────────┐   │
│  │ Download    │ -> │ Extract zip │ -> │ Copy to SD    │   │
│  │ zip file    │    │             │    │ card          │   │
│  └─────────────┘    └─────────────┘    └───────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Raspberry Pi Zero 2 W                    │
│  ┌─────────────┐    ┌─────────────┐    ┌───────────────┐   │
│  │ Boot from   │ -> │ Load        │ -> │ Start hotspot │   │
│  │ SD card     │    │ initramfs   │    │ or WiFi       │   │
│  └─────────────┘    └─────────────┘    └───────────────┘   │
│                              │                              │
│                              ▼                              │
│  ┌─────────────┐    ┌─────────────┐    ┌───────────────┐   │
│  │ Captive     │ <- │ User        │ -> │ Claim device  │   │
│  │ portal      │    │ configures  │    │ to account    │   │
│  └─────────────┘    └─────────────┘    └───────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Palpable Cloud                           │
│  ┌─────────────┐    ┌─────────────┐    ┌───────────────┐   │
│  │ Device      │    │ Real-time   │    │ OTA updates   │   │
│  │ registry    │    │ connection  │    │               │   │
│  └─────────────┘    └─────────────┘    └───────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## License

MIT License - see LICENSE file for details.
