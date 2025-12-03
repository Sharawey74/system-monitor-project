#!/usr/bin/env bash
# Temperature Monitor - Collects temperature data with multi-method detection

set -euo pipefail

get_cpu_vendor() {
    local vendor="unknown"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        vendor=$(sysctl -n machdep.cpu.brand_string 2>/dev/null | awk '{print $1}')
    elif [ -f /proc/cpuinfo ]; then
        local vendor_id=$(grep -m1 "vendor_id" /proc/cpuinfo | cut -d: -f2 | xargs)
        case "$vendor_id" in
            GenuineIntel) vendor="Intel" ;;
            AuthenticAMD) vendor="AMD" ;;
            *) vendor="${vendor_id:-unknown}" ;;
        esac
    fi
    
    echo "${vendor}"
}

get_gpu_vendor() {
    local vendor="unknown"
    
    # Try nvidia-smi first
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -qi "nvidia"; then
            vendor="NVIDIA"
        fi
    fi
    
    # Try lspci for GPU detection
    if [ "$vendor" = "unknown" ] && command -v lspci &> /dev/null; then
        if lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -qi "nvidia"; then
            vendor="NVIDIA"
        elif lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -qi "amd\|radeon"; then
            vendor="AMD"
        elif lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -qi "intel"; then
            vendor="Intel"
        fi
    fi
    
    echo "${vendor}"
}

get_temperature_stats() {
    local cpu_temp=0
    local gpu_temp=0
    local status="ok"
    
    # PRIMARY METHOD: NVIDIA GPU detection
    if command -v nvidia-smi &> /dev/null; then
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
        gpu_temp=${gpu_temp:-0}
    fi
    
    # METHOD 2: lm-sensors (KEEP EXISTING)
    if command -v sensors &> /dev/null; then
        local sensors_output=$(sensors 2>/dev/null)
        
        # Try to find CPU temperature (only if not already found)
        if [ "$cpu_temp" = "0" ]; then
            cpu_temp=$(echo "$sensors_output" | grep -i "core 0\|cpu" | grep -oP '\+\K[0-9.]+' | head -1)
            cpu_temp=${cpu_temp:-0}
        fi
        
        # Try to find GPU temperature (only if not already found)
        if [ "$gpu_temp" = "0" ]; then
            gpu_temp=$(echo "$sensors_output" | grep -i "gpu\|radeon\|nvidia" | grep -oP '\+\K[0-9.]+' | head -1)
            gpu_temp=${gpu_temp:-0}
        fi
    fi
    
    # METHOD 3: /sys/class/hwmon detection (NEW from Workspace 1)
    if [ "$cpu_temp" = "0" ] || [ "$gpu_temp" = "0" ]; then
        for hwmon in /sys/class/hwmon/hwmon*/temp*_input; do
            if [ -f "$hwmon" ]; then
                local temp_millidegrees=$(cat "$hwmon" 2>/dev/null || echo "0")
                if [ "$temp_millidegrees" != "0" ]; then
                    local temp=$(awk "BEGIN {printf \"%.1f\", $temp_millidegrees / 1000}")
                    
                    # Try to determine if CPU or GPU based on hwmon name
                    local hwmon_name=$(cat "$(dirname "$hwmon")/name" 2>/dev/null || echo "")
                    
                    if [[ "$hwmon_name" =~ coretemp|k10temp|cpu|zenpower ]] && [ "$cpu_temp" = "0" ]; then
                        cpu_temp=$temp
                    elif [[ "$hwmon_name" =~ amdgpu|radeon|nouveau|nvidia ]] && [ "$gpu_temp" = "0" ]; then
                        gpu_temp=$temp
                    elif [ "$cpu_temp" = "0" ]; then
                        # If we can't determine type, assume first temp is CPU
                        cpu_temp=$temp
                    fi
                fi
            fi
        done
    fi
    
    # METHOD 4: Thermal zones (KEEP EXISTING)
    if [ -d /sys/class/thermal ] && [ "$cpu_temp" = "0" ]; then
        local thermal_zone="/sys/class/thermal/thermal_zone0/temp"
        if [ -f "$thermal_zone" ]; then
            local temp_millidegrees=$(cat "$thermal_zone" 2>/dev/null || echo "0")
            if [ "$temp_millidegrees" != "0" ]; then
                cpu_temp=$(awk "BEGIN {printf \"%.1f\", $temp_millidegrees / 1000}")
            fi
        fi
    fi
    
    # METHOD 5: macOS detection (KEEP EXISTING)
    if [[ "$OSTYPE" == "darwin"* ]] && [ "$cpu_temp" = "0" ]; then
        status="unavailable"
    fi
    
    # If no temperature data found for BOTH CPU and GPU, mark as unavailable
    if (( $(echo "$cpu_temp == 0" | bc -l 2>/dev/null || echo "1") )) && (( $(echo "$gpu_temp == 0" | bc -l 2>/dev/null || echo "1") )) && [ "$status" != "unavailable" ]; then
        status="unavailable"
    fi
    
    echo "$cpu_temp" "$gpu_temp" "$status"
}

# Get temperature statistics and vendor info
read cpu_temp gpu_temp status <<< $(get_temperature_stats)
cpu_vendor=$(get_cpu_vendor)
gpu_vendor=$(get_gpu_vendor)

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
  "cpu_vendor": "${cpu_vendor}",
  "gpu_celsius": ${gpu_temp},
  "gpu_vendor": "${gpu_vendor}",
  "status": "ok"
}
EOF
fi

exit 0
