#!/usr/bin/env bash
# Main Monitor - Orchestrator for Unix systems

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MONITORS_DIR="${SCRIPT_DIR}/monitors/unix"
UTILS_DIR="${SCRIPT_DIR}/utils"
TEMP_DIR="${PROJECT_ROOT}/data/metrics/temp"

# Source logger
source "${UTILS_DIR}/logger.sh" || true

# Create temp directory for JSON fragments
mkdir -p "${TEMP_DIR}"

# Log start
"${UTILS_DIR}/logger.sh" "INFO" "Starting system monitoring collection"

# Array to store temp file paths
declare -a temp_files=()

# Run each monitor and capture output
monitors=(
    "system_monitor.sh"
    "cpu_monitor.sh"
    "memory_monitor.sh"
    "disk_monitor.sh"
    "network_monitor.sh"
    "temperature_monitor.sh"
    "fan_monitor.sh"
    "smart_monitor.sh"
)

for monitor in "${monitors[@]}"; do
    monitor_path="${MONITORS_DIR}/${monitor}"
    monitor_name="${monitor%.sh}"
    temp_file="${TEMP_DIR}/${monitor_name}.json"
    
    if [ -f "${monitor_path}" ]; then
        "${UTILS_DIR}/logger.sh" "INFO" "Running ${monitor}"
        
        # Run monitor and save output
        if bash "${monitor_path}" > "${temp_file}" 2>/dev/null; then
            temp_files+=("${temp_file}")
            "${UTILS_DIR}/logger.sh" "INFO" "${monitor} completed successfully"
        else
            "${UTILS_DIR}/logger.sh" "ERROR" "${monitor} failed with exit code $?"
            # Create error JSON
            echo "{\"${monitor_name}\": {\"status\": \"error\"}}" > "${temp_file}"
            temp_files+=("${temp_file}")
        fi
    else
        "${UTILS_DIR}/logger.sh" "WARN" "${monitor} not found at ${monitor_path}"
    fi
done

# Merge all JSON files
"${UTILS_DIR}/logger.sh" "INFO" "Merging JSON outputs"
bash "${UTILS_DIR}/json_writer.sh" "${TEMP_DIR}" "${temp_files[@]}"

# Clean up temp files
rm -rf "${TEMP_DIR}"

"${UTILS_DIR}/logger.sh" "INFO" "Monitoring collection completed"

echo "Monitoring data written to ${PROJECT_ROOT}/data/metrics/current.json"

exit 0
