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
    
    local first=true
    for file in "${files[@]}"; do
        if [ -f "${file}" ]; then
            # Read the JSON content and extract key-value pairs
            local content=$(cat "${file}")
            
            # Remove outer braces and add content
            local inner=$(echo "${content}" | sed '1s/^{//; $s/}$//')
            
            if [ -n "${inner}" ] && [ "${inner}" != " " ]; then
                if [ "${first}" = false ]; then
                    echo "," >> "${OUTPUT_FILE}"
                fi
                echo "${inner}" >> "${OUTPUT_FILE}"
                first=false
            fi
        fi
    done
    
    echo "" >> "${OUTPUT_FILE}"
    echo "}" >> "${OUTPUT_FILE}"
}

# If called with arguments (temp directory and file list), merge them
if [ $# -ge 1 ]; then
    merge_json "$@"
else
    # Create empty JSON with timestamp
    echo "{\"timestamp\": \"${TIMESTAMP}\"}" > "${OUTPUT_FILE}"
fi

exit 0
