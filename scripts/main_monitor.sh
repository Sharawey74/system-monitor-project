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

PLATFORM_OUTPUT="${PROJECT_ROOT}/data/metrics/unix_current.json"
LATEST_OUTPUT="${PROJECT_ROOT}/data/metrics/current.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

# Build merged JSON with metadata and proper structure
sections_added=0

{
    echo "{"
    echo "  \"timestamp\": \"${TIMESTAMP}\","
    echo "  \"platform\": \"unix\","
    echo ""
    
    # Process each monitor
    for file in "${temp_files[@]}"; do
        if [ -f "${file}" ]; then
            monitor_name=$(basename "${file}" .json)
            
            if content=$(cat "${file}" 2>/dev/null); then
                # Skip empty content
                if [ -z "${content}" ]; then
                    continue
                fi
                
                # Add comma and spacing after previous section
                if [ ${sections_added} -gt 0 ]; then
                    echo ","
                    echo ""
                fi
                
                # Determine content type and format accordingly
                case "${monitor_name}" in
                    system_monitor|cpu_monitor|memory_monitor|temperature_monitor|fan_monitor|smart_monitor)
                        # Object types - extract inner content without leading/trailing braces
                        inner=$(echo "${content}" | sed '1s/^{//; $s/}$//')
                        
                        # Determine key name
                        key_name="${monitor_name%_monitor}"
                        [ "${key_name}" = "fan" ] && key_name="fans"
                        
                        echo "  \"${key_name}\": {"
                        echo "${inner}" | sed 's/^/    /'
                        echo -n "  }"
                        ;;
                    disk_monitor|network_monitor)
                        # Array types - use content as-is
                        key_name="${monitor_name%_monitor}"
                        echo -n "  \"${key_name}\": ${content}"
                        ;;
                    *)
                        # Unknown type - wrap as object
                        inner=$(echo "${content}" | sed '1s/^{//; $s/}$//')
                        echo "  \"${monitor_name}\": {"
                        echo "${inner}" | sed 's/^/    /'
                        echo -n "  }"
                        ;;
                esac
                
                sections_added=$((sections_added + 1))
                "${UTILS_DIR}/logger.sh" "INFO" "Successfully merged: $(basename "${file}")"
            else
                "${UTILS_DIR}/logger.sh" "ERROR" "Failed to read: $(basename "${file}")"
            fi
        fi
    done
    
    echo ""
    echo "}"
} > "${LATEST_OUTPUT}"

# Copy to platform-specific file
cp "${LATEST_OUTPUT}" "${PLATFORM_OUTPUT}"
"${UTILS_DIR}/logger.sh" "INFO" "Unix data written to unix_current.json"
"${UTILS_DIR}/logger.sh" "INFO" "Latest data written to current.json"

# Clean up temp files
rm -rf "${TEMP_DIR}"

"${UTILS_DIR}/logger.sh" "INFO" "Monitoring collection completed"

echo "Monitoring data written to:"
echo "  - Platform-specific: ${PLATFORM_OUTPUT}"
echo "  - Latest run: ${LATEST_OUTPUT}"

exit 0
