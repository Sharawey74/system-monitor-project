#!/usr/bin/env bash
# Test for smart_monitor.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MONITOR_SCRIPT="${PROJECT_ROOT}/scripts/monitors/unix/smart_monitor.sh"

echo "Testing smart_monitor.sh..."

# Run the monitor
output=$(bash "${MONITOR_SCRIPT}" 2>&1)
exit_code=$?

# Check exit code
if [ $exit_code -ne 0 ]; then
    echo "[FAIL] smart_monitor.sh exited with code $exit_code"
    exit 1
fi

# Check if output is valid JSON
if ! echo "$output" | python3 -m json.tool &>/dev/null && ! echo "$output" | jq . &>/dev/null 2>&1; then
    if ! echo "$output" | grep -q "^{.*}$"; then
        echo "[FAIL] Output is not valid JSON"
        exit 1
    fi
fi

# Check for required fields
if ! echo "$output" | grep -q '"smart"'; then
    echo "[FAIL] Missing 'smart' field"
    exit 1
fi

echo "[PASS] smart_monitor.sh"
exit 0
