#!/usr/bin/env bash
# JSON Writer - Merges JSON fragments into a single file

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT_FILE="${PROJECT_ROOT}/data/metrics/current.json"

# Ensure output directory exists
mkdir -p "$(dirname "${OUTPUT_FILE}")"

# Get timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

# Function to merge JSON files
merge_json() {
    local temp_dir="$1"
    shift
    local files=("$@")
    
    # Start building JSON
    echo "{" > "${OUTPUT_FILE}"
    echo "  \"timestamp\": \"${TIMESTAMP}\"," >> "${OUTPUT_FILE}"
    
    # Process each temp file
    for temp_file in "${files[@]}"; do
        if [ -f "${temp_file}" ] && [ -s "${temp_file}" ]; then
            # Extract monitor name from filename (remove .json extension and _monitor suffix)
            local monitor_name=$(basename "${temp_file}" .json | sed 's/_monitor$//')
            
            # Add the section
            echo "  \"${monitor_name}\": $(cat "${temp_file}")," >> "${OUTPUT_FILE}"
        fi
    done
    
    # Remove trailing comma from last entry
    sed -i '$ s/,$//' "${OUTPUT_FILE}" 2>/dev/null || sed -i '' '$ s/,$//' "${OUTPUT_FILE}"
    
    # Close JSON
    echo "}" >> "${OUTPUT_FILE}"
    
    # Validate and pretty-print JSON if jq is available
    if command -v jq &> /dev/null; then
        if jq empty "${OUTPUT_FILE}" 2>/dev/null; then
            # Pretty print the JSON in place
            jq . "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"
        else
            echo "Warning: Generated JSON is invalid" >&2
        fi
    fi
}

# If called with arguments (temp directory and file list), merge them
if [ $# -ge 1 ]; then
    merge_json "$@"
else
    # Create empty JSON with timestamp
    echo "{\"timestamp\": \"${TIMESTAMP}\"}" > "${OUTPUT_FILE}"
fi

exit 0
