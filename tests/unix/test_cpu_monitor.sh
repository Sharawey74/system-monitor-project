#!/usr/bin/env bash
# Test for cpu_monitor.sh - Enhanced with value validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MONITOR_SCRIPT="${PROJECT_ROOT}/scripts/monitors/unix/cpu_monitor.sh"

echo "Testing cpu_monitor.sh..."

# Run the monitor
output=$(bash "${MONITOR_SCRIPT}" 2>&1)
exit_code=$?

# Check exit code
if [ $exit_code -ne 0 ]; then
    echo "[FAIL] cpu_monitor.sh exited with code $exit_code"
    exit 1
fi

# Check if output is valid JSON
if ! echo "$output" | python3 -m json.tool &>/dev/null && ! echo "$output" | jq . &>/dev/null 2>&1; then
    # Try basic JSON validation
    if ! echo "$output" | grep -q "^{.*}$"; then
        echo "[FAIL] Output is not valid JSON"
        echo "Output: $output"
        exit 1
    fi
fi

# Check for required fields
# Note: Individual monitor output is flat, so we don't look for "cpu" key here
if ! echo "$output" | grep -q '"usage_percent"'; then
    echo "[FAIL] Missing 'usage_percent' field"
    exit 1
fi

# Validate CPU usage is within valid range (0-100%)
if command -v jq &>/dev/null; then
    cpu_usage=$(echo "$output" | jq -r '.usage_percent // .cpu.usage_percent // 0' 2>/dev/null || echo "0")
    
    # Check if value is numeric
    if [[ "$cpu_usage" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        # Check range
        if (( $(echo "$cpu_usage < 0" | bc -l 2>/dev/null || echo "0") )) || (( $(echo "$cpu_usage > 100" | bc -l 2>/dev/null || echo "0") )); then
            echo "[FAIL] CPU usage out of range (0-100%): $cpu_usage"
            exit 1
        fi
        echo "[INFO] CPU usage: ${cpu_usage}%"
    fi
fi

# Check for logical_processors field
if echo "$output" | grep -q '"logical_processors"'; then
    echo "[INFO] Logical processors field present"
fi

# Check for model/vendor field
if echo "$output" | grep -q '"model"' || echo "$output" | grep -q '"vendor"'; then
    echo "[INFO] CPU model/vendor information present"
fi

echo "[PASS] cpu_monitor.sh - All validations passed"
exit 0

