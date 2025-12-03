#!/usr/bin/env bash
# Network Monitor - Collects network interface statistics

set -euo pipefail

get_network_stats() {
    local networks="["
    local first=true
    
    if [ -f /proc/net/dev ]; then
        # Linux - read from /proc/net/dev
        while IFS= read -r line; do
            # Skip header lines
            if [[ "$line" =~ ^Inter ]] || [[ "$line" =~ ^face ]]; then
                continue
            fi
            
            # Skip loopback
            if [[ "$line" =~ ^lo: ]]; then
                continue
            fi
            
            # Parse interface name and stats
            local iface=$(echo "$line" | awk -F: '{print $1}' | tr -d ' ')
            local stats=$(echo "$line" | awk -F: '{print $2}')
            local rx_bytes=$(echo "$stats" | awk '{print $1}')
            local tx_bytes=$(echo "$stats" | awk '{print $9}')
            
            # Skip if not numeric
            if ! [[ "$rx_bytes" =~ ^[0-9]+$ ]]; then
                continue
            fi
            
            # Add to JSON array
            if [ "$first" = false ]; then
                networks+=","
            fi
            networks+="{\"iface\":\"$iface\",\"rx_bytes\":$rx_bytes,\"tx_bytes\":$tx_bytes}"
            first=false
        done < /proc/net/dev
    elif command -v netstat &> /dev/null; then
        # macOS and others - use netstat
        while IFS= read -r line; do
            local iface=$(echo "$line" | awk '{print $1}')
            local rx_bytes=$(echo "$line" | awk '{print $7}')
            local tx_bytes=$(echo "$line" | awk '{print $10}')
            
            # Skip header and loopback
            if [[ "$iface" == "Name" ]] || [[ "$iface" == "lo0" ]]; then
                continue
            fi
            
            # Skip if not numeric
            if ! [[ "$rx_bytes" =~ ^[0-9]+$ ]]; then
                continue
            fi
            
            # Add to JSON array
            if [ "$first" = false ]; then
                networks+=","
            fi
            networks+="{\"iface\":\"$iface\",\"rx_bytes\":$rx_bytes,\"tx_bytes\":$tx_bytes}"
            first=false
        done < <(netstat -ibn 2>/dev/null | grep -v "^lo")
    fi
    
    networks+="]"
    echo "$networks"
}

# Get network statistics
network_array=$(get_network_stats)

# Output JSON
echo "${network_array}"

exit 0
