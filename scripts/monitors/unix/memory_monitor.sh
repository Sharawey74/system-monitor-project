#!/usr/bin/env bash
# Memory Monitor - Collects memory statistics

set -euo pipefail

get_memory_stats() {
    local total_mb=0
    local used_mb=0
    local free_mb=0
    local available_mb=0
    
    if command -v free &> /dev/null; then
        # Linux with 'free' command
        local mem_line=$(free -m | grep "^Mem:")
        total_mb=$(echo "$mem_line" | awk '{print $2}')
        used_mb=$(echo "$mem_line" | awk '{print $3}')
        free_mb=$(echo "$mem_line" | awk '{print $4}')
        available_mb=$(echo "$mem_line" | awk '{print $7}')
        available_mb=${available_mb:-$free_mb}
    elif [ -f /proc/meminfo ]; then
        # Linux via /proc/meminfo
        total_kb=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}')
        free_kb=$(grep "^MemFree:" /proc/meminfo | awk '{print $2}')
        available_kb=$(grep "^MemAvailable:" /proc/meminfo | awk '{print $2}')
        available_kb=${available_kb:-$free_kb}
        
        total_mb=$((total_kb / 1024))
        free_mb=$((free_kb / 1024))
        available_mb=$((available_kb / 1024))
        used_mb=$((total_mb - available_mb))
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        total_bytes=$(sysctl -n hw.memsize)
        total_mb=$((total_bytes / 1024 / 1024))
        
        # Get page statistics
        vm_stat_output=$(vm_stat)
        pages_free=$(echo "$vm_stat_output" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        pages_active=$(echo "$vm_stat_output" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        pages_inactive=$(echo "$vm_stat_output" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        pages_wired=$(echo "$vm_stat_output" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
        
        page_size=4096
        free_mb=$(((pages_free * page_size) / 1024 / 1024))
        used_mb=$(((pages_active + pages_wired) * page_size / 1024 / 1024))
        available_mb=$(((pages_free + pages_inactive) * page_size / 1024 / 1024))
    fi
    
    echo "$total_mb" "$used_mb" "$free_mb" "$available_mb"
}

get_ram_modules() {
    local modules=""
    
    if command -v dmidecode &> /dev/null && [ -r /dev/mem ]; then
        # Linux with dmidecode (requires root)
        modules=$(sudo dmidecode -t memory 2>/dev/null | awk '
            /Memory Device$/,/^$/ {
                if ($1 == "Size:" && $2 != "No" && $2 ~ /^[0-9]+/) {
                    size = $2
                    if ($3 == "GB") size = $2
                    else if ($3 == "MB") size = $2 / 1024
                }
                if ($1 == "Manufacturer:") manufacturer = substr($0, index($0,$2))
                if ($1 == "Speed:") speed = $2
                if ($1 == "Type:") mem_type = $2
                if ($1 == "Form" && $2 == "Factor:") form_factor = $3
            }
            /^$/ {
                if (size > 0) {
                    if (modules != "") modules = modules ","
                    modules = modules sprintf("{\"manufacturer\":\"%s\",\"capacity_gb\":%.2f,\"speed_mhz\":%s,\"type\":\"%s\",\"form_factor\":\"%s\"}", 
                        manufacturer, size, speed, mem_type, form_factor)
                    size = 0
                }
            }
            END { print modules }
        ')
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        local mem_info=$(system_profiler SPMemoryDataType 2>/dev/null)
        if [ -n "$mem_info" ]; then
            modules=$(echo "$mem_info" | awk '
                /Size:/ { size = $2; gsub(/GB/, "", size) }
                /Type:/ { mem_type = $2 }
                /Speed:/ { speed = $2; gsub(/MHz/, "", speed) }
                /Manufacturer:/ { 
                    manufacturer = substr($0, index($0,$2))
                    if (size > 0) {
                        if (modules != "") modules = modules ","
                        modules = modules sprintf("{\"manufacturer\":\"%s\",\"capacity_gb\":%.2f,\"speed_mhz\":%s,\"type\":\"%s\",\"form_factor\":\"SODIMM\"}", 
                            manufacturer, size, speed, mem_type)
                        size = 0
                    }
                }
                END { print modules }
            ')
        fi
    fi
    
    echo "$modules"
}

# Get memory statistics
read total_mb used_mb free_mb available_mb <<< $(get_memory_stats)
ram_modules=$(get_ram_modules)

# Output JSON
if [ -n "$ram_modules" ]; then
cat <<EOF
{
  "total_mb": ${total_mb:-0},
  "used_mb": ${used_mb:-0},
  "free_mb": ${free_mb:-0},
  "available_mb": ${available_mb:-0},
  "modules": [${ram_modules}]
}
EOF
else
cat <<EOF
{
  "total_mb": ${total_mb:-0},
  "used_mb": ${used_mb:-0},
  "free_mb": ${free_mb:-0},
  "available_mb": ${available_mb:-0}
}
EOF
fi

exit 0
