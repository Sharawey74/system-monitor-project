#!/usr/bin/env bash
# SMART Monitor - Collects disk health data using smartctl

set -euo pipefail

get_smart_stats() {
    local smart_data="["
    local first=true
    local status="ok"
    
    if ! command -v smartctl &> /dev/null; then
        status="unavailable"
        echo "$smart_data]" "$status"
        return
    fi
    
    # Find all disk devices
    local devices=()
    if [ -d /dev ]; then
        # Linux - look for sd* and nvme* devices
        for dev in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
            if [ -b "$dev" ]; then
                devices+=("$dev")
            fi
        done
    fi
    
    # If no devices found, try common ones
    if [ ${#devices[@]} -eq 0 ]; then
        for dev in /dev/sda /dev/nvme0n1; do
            if [ -b "$dev" ]; then
                devices+=("$dev")
            fi
        done
    fi
    
    # Check each device
    for device in "${devices[@]}"; do
        # Try to get SMART data (may require sudo)
        local smart_output=$(smartctl -H "$device" 2>/dev/null)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            # Successfully got SMART data
            local health="UNKNOWN"
            if echo "$smart_output" | grep -q "PASSED"; then
                health="PASSED"
            elif echo "$smart_output" | grep -q "FAILED"; then
                health="FAILED"
            fi
            
            # Try to get power-on hours
            local power_on_hours=0
            local info_output=$(smartctl -a "$device" 2>/dev/null)
            if [ $? -eq 0 ]; then
                power_on_hours=$(echo "$info_output" | grep "Power_On_Hours" | awk '{print $10}')
                power_on_hours=${power_on_hours:-0}
            fi
            
            # Add to JSON array
            if [ "$first" = false ]; then
                smart_data+=","
            fi
            smart_data+="{\"device\":\"$device\",\"health\":\"$health\",\"power_on_hours\":$power_on_hours}"
            first=false
        elif [ $exit_code -eq 1 ] || [ $exit_code -eq 2 ]; then
            # Permission denied or device doesn't support SMART
            if [ "$first" = true ]; then
                status="restricted"
            fi
        fi
    done
    
    # If no data collected, mark as restricted or unavailable
    if [ "$first" = true ]; then
        if [ "$status" != "restricted" ]; then
            status="unavailable"
        fi
    fi
    
    smart_data+="]"
    echo "$smart_data" "$status"
}

# Get SMART statistics
read smart_data status <<< $(get_smart_stats)

# Output JSON
if [ "$status" = "restricted" ]; then
    cat <<EOF
{
  "status": "restricted"
}
EOF
elif [ "$status" = "unavailable" ]; then
    cat <<EOF
{
  "status": "unavailable"
}
EOF
else
    echo "${smart_data}"
fi

exit 0
