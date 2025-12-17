#!/usr/bin/env bash
# Run all Unix tests - Enhanced with timing and detailed reporting

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Running All Unix Monitor Tests ===${NC}"
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
skipped=0
failed_tests=()
start_time=$(date +%s)

# Run each test
for test in "${tests[@]}"; do
    test_path="${SCRIPT_DIR}/${test}"
    
    if [ -f "${test_path}" ]; then
        echo -n "Running ${test}... "
        test_start=$(date +%s)
        
        if bash "${test_path}" > /tmp/test_output_$$.log 2>&1; then
            test_end=$(date +%s)
            duration=$((test_end - test_start))
            echo -e "${GREEN}PASS${NC} (${duration}s)"
            ((passed++))
        else
            test_end=$(date +%s)
            duration=$((test_end - test_start))
            echo -e "${RED}FAIL${NC} (${duration}s)"
            ((failed++))
            failed_tests+=("${test}")
            
            # Show last few lines of error
            echo -e "${YELLOW}  Error output:${NC}"
            tail -n 5 /tmp/test_output_$$.log | sed 's/^/    /'
        fi
        
        rm -f /tmp/test_output_$$.log
    else
        echo -e "${YELLOW}[SKIP]${NC} Test not found: ${test}"
        ((skipped++))
    fi
done

end_time=$(date +%s)
total_duration=$((end_time - start_time))

# Print summary
echo ""
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "${GREEN}Passed:${NC}  ${passed}"
echo -e "${RED}Failed:${NC}  ${failed}"
echo -e "${YELLOW}Skipped:${NC} ${skipped}"
echo "Total time: ${total_duration}s"

if [ ${failed} -gt 0 ]; then
    echo ""
    echo -e "${RED}Failed tests:${NC}"
    for test in "${failed_tests[@]}"; do
        echo "  - ${test}"
    done
    exit 1
fi

echo ""
echo -e "${GREEN}✓ All tests passed!${NC}"
exit 0

