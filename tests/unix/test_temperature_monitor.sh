#!/usr/bin/env bash
# Test for temperature_monitor.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MONITOR_SCRIPT="${PROJECT_ROOT}/scripts/monitors/unix/temperature_monitor.sh"
JSON_OUTPUT_DIR="${SCRIPT_DIR}/json"
JSON_OUTPUT_FILE="${JSON_OUTPUT_DIR}/temperature_output.json"

echo "Temperature Monitor Test - Unix"
echo "================================"

# Create json directory if it doesn't exist
mkdir -p "${JSON_OUTPUT_DIR}"

# Run the monitor
output=$(bash "${MONITOR_SCRIPT}" 2>&1)
exit_code=$?

# Check exit code
if [ $exit_code -ne 0 ]; then
    echo "Validation: FAILED"
    echo "Error: Script exited with code $exit_code"
    exit 1
fi

# Save output to file
echo "$output" > "${JSON_OUTPUT_FILE}"
echo "JSON output saved to: ${JSON_OUTPUT_FILE}"

# Check if output is valid JSON
if ! echo "$output" | python3 -m json.tool &>/dev/null && ! echo "$output" | jq . &>/dev/null 2>&1; then
    if ! echo "$output" | grep -q "^{.*}$"; then
        echo "Validation: FAILED"
        echo "Error: Output is not valid JSON"
        exit 1
    fi
fi

# Parse and display results
if echo "$output" | grep -q '"status".*:.*"unavailable"'; then
    echo "Status: unavailable"
    echo "CPU Temperature: N/A"
    echo "GPU Temperature: N/A"
else
    # Extract temperatures using grep and sed
    cpu_temp=$(echo "$output" | grep -o '"cpu_celsius"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$' || echo "0")
    gpu_temp=$(echo "$output" | grep -o '"gpu_celsius"[[:space:]]*:[[:space:]]*[0-9.]*' | grep -o '[0-9.]*$' || echo "0")
    
    echo "Status: ok"
    echo "CPU Temperature: ${cpu_temp}°C"
    echo "GPU Temperature: ${gpu_temp}°C"
fi

echo "Validation: PASSED"
exit 0
