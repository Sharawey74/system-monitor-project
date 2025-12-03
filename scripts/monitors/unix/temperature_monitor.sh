#!/usr/bin/env bash
# Temperature Monitor - Collects temperature data

set -euo pipefail

get_temperature_stats() {
    local cpu_temp=0
    local gpu_temp=0
    local status="ok"
    
    if command -v sensors &> /dev/null; then
        # Use lm-sensors if available
        local sensors_output=$(sensors 2>/dev/null)
        
        # Try to find CPU temperature
        cpu_temp=$(echo "$sensors_output" | grep -i "core 0\|cpu" | grep -oP '\+\K[0-9.]+' | head -1)
        cpu_temp=${cpu_temp:-0}
        
        # Try to find GPU temperature
        gpu_temp=$(echo "$sensors_output" | grep -i "gpu\|radeon\|nvidia" | grep -oP '\+\K[0-9.]+' | head -1)
        gpu_temp=${gpu_temp:-0}
        
    elif [ -d /sys/class/thermal ]; then
        # Use thermal zones (Linux)
        local thermal_zone="/sys/class/thermal/thermal_zone0/temp"
        if [ -f "$thermal_zone" ]; then
            local temp_millidegrees=$(cat "$thermal_zone" 2>/dev/null || echo "0")
            cpu_temp=$(awk "BEGIN {printf \"%.1f\", $temp_millidegrees / 1000}")
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS - sensors not typically available without additional tools
        status="unavailable"
    else
        status="unavailable"
    fi
    
    # If no temperature data found, mark as unavailable
    if (( $(echo "$cpu_temp == 0" | bc -l 2>/dev/null || echo "1") )) && [ "$status" != "unavailable" ]; then
        status="unavailable"
    fi
    
    echo "$cpu_temp" "$gpu_temp" "$status"
}

# Get temperature statistics
read cpu_temp gpu_temp status <<< $(get_temperature_stats)

# Output JSON
if [ "$status" = "unavailable" ]; then
    cat <<EOF
{
  "status": "unavailable"
}
EOF
else
    cat <<EOF
{
  "cpu_celsius": ${cpu_temp},
  "gpu_celsius": ${gpu_temp}
}
EOF
fi

exit 0
