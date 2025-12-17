#!/usr/bin/env bash
# Test for main_monitor.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MONITOR_SCRIPT="${PROJECT_ROOT}/scripts/main_monitor.sh"
OUTPUT_FILE="${PROJECT_ROOT}/data/metrics/current.json"

OUTPUT_DIR="/tmp/test_monitor_$$"
mkdir -p "${OUTPUT_DIR}"
export LATEST_OUTPUT="${OUTPUT_DIR}/current.json"
export PLATFORM_OUTPUT="${OUTPUT_DIR}/unix_current.json"

echo "Testing main_monitor.sh..."

OUTPUT_FILE="${LATEST_OUTPUT}"

# Run the main monitor
bash "${MONITOR_SCRIPT}" &>/dev/null
exit_code=$?

# Check exit code
if [ $exit_code -ne 0 ]; then
    echo "[FAIL] main_monitor.sh exited with code $exit_code"
    rm -rf "${OUTPUT_DIR}"
    exit 1
fi

# Check if output file exists
if [ ! -f "${OUTPUT_FILE}" ]; then
    echo "[FAIL] Output file not created: ${OUTPUT_FILE}"
    rm -rf "${OUTPUT_DIR}"
    exit 1
fi

# Check if output file contains valid JSON
if ! cat "${OUTPUT_FILE}" | python3 -m json.tool &>/dev/null && ! cat "${OUTPUT_FILE}" | jq . &>/dev/null 2>&1; then
    if ! cat "${OUTPUT_FILE}" | grep -q "^{.*}$"; then
        echo "[FAIL] Output file is not valid JSON"
        rm -rf "${OUTPUT_DIR}"
        exit 1
    fi
fi

# Check for timestamp
if ! cat "${OUTPUT_FILE}" | grep -q '"timestamp"'; then
    echo "[FAIL] Missing 'timestamp' field in output"
    rm -rf "${OUTPUT_DIR}"
    exit 1
fi

# Check for platform
if ! cat "${OUTPUT_FILE}" | grep -q '"platform"'; then
    echo "[FAIL] Missing 'platform' field in output"
    rm -rf "${OUTPUT_DIR}"
    exit 1
fi

echo "[PASS] main_monitor.sh"
rm -rf "${OUTPUT_DIR}"
exit 0
