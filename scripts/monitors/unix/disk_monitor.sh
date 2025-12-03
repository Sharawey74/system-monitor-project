#!/usr/bin/env bash
# Disk Monitor - Collects disk usage statistics

set -euo pipefail

get_disk_stats() {
    local disks="["
    local first=true
    
    if command -v df &> /dev/null; then
        # Use df command
        while IFS= read -r line; do
            # Skip header and special filesystems
            if [[ "$line" =~ ^Filesystem ]] || [[ "$line" =~ ^tmpfs ]] || [[ "$line" =~ ^devtmpfs ]] || [[ "$line" =~ ^udev ]]; then
                continue
            fi
            
            # Parse df output
            local device=$(echo "$line" | awk '{print $1}')
            local total_kb=$(echo "$line" | awk '{print $2}')
            local used_kb=$(echo "$line" | awk '{print $3}')
            local mount=$(echo "$line" | awk '{print $NF}')
            
            # Skip if values are not numeric
            if ! [[ "$total_kb" =~ ^[0-9]+$ ]]; then
                continue
            fi
            
            # Convert to GB
            local total_gb=$(awk "BEGIN {printf \"%.2f\", $total_kb / 1024 / 1024}")
            local used_gb=$(awk "BEGIN {printf \"%.2f\", $used_kb / 1024 / 1024}")
            local used_percent=$(awk "BEGIN {printf \"%.1f\", ($used_kb / $total_kb) * 100}")
            
            # Escape backslashes in device and mount paths for JSON
            device_escaped=$(echo "$device" | sed 's/\\/\\\\/g')
            mount_escaped=$(echo "$mount" | sed 's/\\/\\\\/g')
            
            # Add to JSON array
            if [ "$first" = false ]; then
                disks+=","
            fi
            disks+="{\"device\":\"$mount_escaped\",\"filesystem\":\"$device_escaped\",\"total_gb\":$total_gb,\"used_gb\":$used_gb,\"used_percent\":$used_percent}"
            first=false
        done < <(df -k 2>/dev/null)
    fi
    
    disks+="]"
    echo "$disks"
}

# Get disk statistics
disk_array=$(get_disk_stats)

# Output JSON
echo "${disk_array}"

exit 0
