#!/usr/bin/env bash
# Run all Unix tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Running All Unix Tests ==="
echo ""

# Set executable permissions
chmod +x "${SCRIPT_DIR}"/*.sh 2>/dev/null || true

# Array of test scripts
tests=(
    "test_cpu_monitor.sh"
    "test_memory_monitor.sh"
    "test_disk_monitor.sh"
    "test_network_monitor.sh"
    "test_temperature_monitor.sh"
    "test_fan_monitor.sh"
    "test_smart_monitor.sh"
    "test_system_monitor.sh"
    "test_main_monitor.sh"
)

# Track results
passed=0
failed=0
failed_tests=()

# Run each test
for test in "${tests[@]}"; do
    test_path="${SCRIPT_DIR}/${test}"
    
    if [ -f "${test_path}" ]; then
        if bash "${test_path}"; then
            ((passed++))
        else
            ((failed++))
            failed_tests+=("${test}")
        fi
    else
        echo "[WARN] Test not found: ${test}"
    fi
done

# Print summary
echo ""
echo "=== Test Summary ==="
echo "Passed: ${passed}"
echo "Failed: ${failed}"

if [ ${failed} -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    for test in "${failed_tests[@]}"; do
        echo "  - ${test}"
    done
    exit 1
fi

echo ""
echo "All tests passed!"
exit 0
