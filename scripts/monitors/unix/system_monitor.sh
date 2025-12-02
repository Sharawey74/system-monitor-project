#!/usr/bin/env bash
# System Monitor - Collects system information

set -euo pipefail

get_system_info() {
    local os_name="Unknown"
    local hostname="unknown"
    local uptime_seconds=0
    local kernel=""
    
    # Get OS name
    if [ -f /etc/os-release ]; then
        os_name=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_name="macOS $(sw_vers -productVersion 2>/dev/null || echo 'Unknown')"
    else
        os_name=$(uname -s 2>/dev/null || echo "Unknown")
    fi
    
    # Get hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    
    # Get uptime in seconds
    if [ -f /proc/uptime ]; then
        # Linux
        uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    elif command -v sysctl &> /dev/null; then
        # macOS
        local boot_time=$(sysctl -n kern.boottime | awk '{print $4}' | sed 's/,//')
        local current_time=$(date +%s)
        uptime_seconds=$((current_time - boot_time))
    elif command -v uptime &> /dev/null; then
        # Fallback - parse uptime command
        local uptime_str=$(uptime | awk '{print $3}')
        uptime_seconds=$((uptime_str * 60)) # Rough estimate
    fi
    
    # Get kernel version
    kernel=$(uname -r 2>/dev/null || echo "unknown")
    
    echo "$os_name" "$hostname" "$uptime_seconds" "$kernel"
}

# Get system information
read -r os_name hostname uptime_seconds kernel <<< "$(get_system_info)"

# Output JSON
cat <<EOF
{
  "system": {
    "os": "$os_name",
    "hostname": "$hostname",
    "uptime_seconds": $uptime_seconds,
    "kernel": "$kernel"
  }
}
EOF

exit 0
