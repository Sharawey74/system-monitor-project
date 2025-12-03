#!/usr/bin/env bash
# CPU Monitor - Collects CPU usage and load averages

set -euo pipefail

get_cpu_usage() {
    local usage=0
    
    # Try different methods to get CPU usage
    if command -v mpstat &> /dev/null; then
        # Use mpstat if available (more accurate)
        usage=$(mpstat 1 1 | awk '/Average:/ {print 100 - $NF}')
    elif command -v top &> /dev/null; then
        # Use top as fallback
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS top format
            usage=$(top -l 2 -n 0 -F -R | grep "CPU usage" | tail -1 | awk '{print $3}' | sed 's/%//')
        else
            # Linux top format
            usage=$(top -bn2 | grep "Cpu(s)" | tail -1 | awk '{print $2}' | sed 's/%us,//')
        fi
    elif [ -f /proc/stat ]; then
        # Calculate from /proc/stat (Linux)
        read cpu user nice system idle iowait irq softirq steal guest < <(head -1 /proc/stat)
        sleep 0.5
        read cpu user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 guest2 < <(head -1 /proc/stat)
        
        total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
        total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
        idle_delta=$((idle2 - idle))
        total_delta=$((total2 - total1))
        
        if [ $total_delta -gt 0 ]; then
            usage=$(awk "BEGIN {printf \"%.1f\", 100 * (1 - $idle_delta / $total_delta)}")
        fi
    fi
    
    # Default to 0 if we couldn't get usage
    usage=${usage:-0}
    
    echo "$usage"
}

get_load_averages() {
    local load_1=0
    local load_5=0
    local load_15=0
    
    if [ -f /proc/loadavg ]; then
        # Linux
        read load_1 load_5 load_15 _ < /proc/loadavg
    elif command -v uptime &> /dev/null; then
        # macOS and others
        local loads=$(uptime | awk -F'load averages?: ' '{print $2}' | sed 's/,//g')
        read load_1 load_5 load_15 <<< "$loads"
    fi
    
    echo "$load_1" "$load_5" "$load_15"
}

# Get CPU metrics
cpu_usage=$(get_cpu_usage)
read load_1 load_5 load_15 <<< $(get_load_averages)

# Output JSON
cat <<EOF
{
  "usage_percent": ${cpu_usage},
  "load_1": ${load_1:-0},
  "load_5": ${load_5:-0},
  "load_15": ${load_15:-0}
}
EOF

exit 0
