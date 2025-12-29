#!/bin/sh
#
# Logging helpers for Palpable Bootstrap
#

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Log to console and file
LOG_FILE="/var/log/palpable-bootstrap.log"
mkdir -p /var/log 2>/dev/null

_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null
}

log_info() {
    echo -e "${CYAN}●${NC} $1"
    _log "INFO" "$1"
}

log_step() {
    echo -e "${BLUE}▸${NC} $1"
    _log "STEP" "$1"
}

log_ok() {
    echo -e "${GREEN}✓${NC} $1"
    _log "OK" "$1"
}

log_warning() {
    echo -e "${YELLOW}!${NC} $1"
    _log "WARN" "$1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    _log "ERROR" "$1"
}

log_debug() {
    if [ -n "$DEBUG" ]; then
        echo -e "${DIM}  $1${NC}"
    fi
    _log "DEBUG" "$1"
}
