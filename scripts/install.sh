#!/usr/bin/env bash
# Install Script - Sets up the monitoring environment

set -euo pipefail

echo "=== System Monitor Installation ==="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Create required directories
echo "Creating directory structure..."
mkdir -p "${PROJECT_ROOT}/data/metrics"
mkdir -p "${PROJECT_ROOT}/data/logs"
mkdir -p "${PROJECT_ROOT}/tests/unix"
mkdir -p "${PROJECT_ROOT}/tests/windows"

# Set executable permissions for Unix scripts
echo "Setting executable permissions..."
find "${SCRIPT_DIR}" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
find "${PROJECT_ROOT}/tests/unix" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true

# Check for required tools
echo ""
echo "Checking for optional tools..."

check_tool() {
    local tool="$1"
    local description="$2"
    
    if command -v "$tool" &> /dev/null; then
        echo "  ✓ $tool - $description"
        return 0
    else
        echo "  ✗ $tool - $description (not found)"
        return 1
    fi
}

# Core tools (usually available)
check_tool "bash" "Shell interpreter"
check_tool "awk" "Text processing"
check_tool "grep" "Pattern matching"
check_tool "sed" "Stream editor"

# Optional but useful tools
echo ""
echo "Optional monitoring tools:"
check_tool "jq" "JSON processor (useful for validation)" || echo "    Install: apt-get install jq / brew install jq"
check_tool "sensors" "Hardware monitoring (lm-sensors)" || echo "    Install: apt-get install lm-sensors / brew install lm-sensors"
check_tool "smartctl" "Disk health monitoring (smartmontools)" || echo "    Install: apt-get install smartmontools / brew install smartmontools"
check_tool "mpstat" "CPU statistics (sysstat)" || echo "    Install: apt-get install sysstat / brew install sysstat"

# Detect platform
echo ""
echo "Detecting platform..."
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "  Platform: Linux"
    echo "  To run monitoring: bash ${SCRIPT_DIR}/main_monitor.sh"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  Platform: macOS"
    echo "  To run monitoring: bash ${SCRIPT_DIR}/main_monitor.sh"
elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    echo "  Platform: Windows"
    echo "  For native Windows monitoring, use PowerShell:"
    echo "  PowerShell -ExecutionPolicy Bypass -File ${SCRIPT_DIR}/main_monitor.ps1"
else
    echo "  Platform: Unknown ($OSTYPE)"
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run monitoring: bash ${SCRIPT_DIR}/main_monitor.sh (Unix)"
echo "                 or: PowerShell ${SCRIPT_DIR}/main_monitor.ps1 (Windows)"
echo "  2. View results: cat ${PROJECT_ROOT}/data/metrics/current.json"
echo "  3. Run tests: bash ${PROJECT_ROOT}/tests/unix/run_all_tests.sh (Unix)"
echo "            or: PowerShell ${PROJECT_ROOT}/tests/windows/Run-AllTests.ps1 (Windows)"
echo ""

exit 0
