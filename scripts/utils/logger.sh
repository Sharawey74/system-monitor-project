#!/usr/bin/env bash
# Logger utility - Logs messages with timestamps

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE="${PROJECT_ROOT}/data/logs/system.log"

# Ensure log directory exists
mkdir -p "$(dirname "${LOG_FILE}")"

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
    
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Only execute if run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -ge 2 ]; then
        log_message "$1" "$2"
    else
        echo "Usage: $0 <level> <message>" >&2
        exit 1
    fi
fi
