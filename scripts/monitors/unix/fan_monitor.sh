#!/usr/bin/env bash
# Fan Monitor - Collects fan speed data

set -euo pipefail

get_fan_stats() {
    local fans="["
    local first=true
    local status="ok"
    
    if command -v sensors &> /dev/null; then
        # Use lm-sensors if available
        local sensors_output=$(sensors 2>/dev/null)
        
        # Extract fan speeds
        while IFS= read -r line; do
            local label=$(echo "$line" | awk -F: '{print $1}' | tr -d ' ')
            local rpm=$(echo "$line" | awk '{print $2}' | grep -oP '^[0-9]+')
            
            if [ -n "$rpm" ] && [ "$rpm" -gt 0 ]; then
                if [ "$first" = false ]; then
                    fans+=","
                fi
                fans+="{\"label\":\"$label\",\"rpm\":$rpm}"
                first=false
            fi
        done < <(echo "$sensors_output" | grep -i "fan")
        
        # If no fans found, mark as unavailable
        if [ "$first" = true ]; then
            status="unavailable"
        fi
    else
        status="unavailable"
    fi
    
    fans+="]"
    echo "$fans" "$status"
}

# Get fan statistics
read fans status <<< $(get_fan_stats)

# Output JSON
if [ "$status" = "unavailable" ]; then
    cat <<EOF
{
  "status": "unavailable"
}
EOF
else
    echo "${fans}"
fi

exit 0
