#!/usr/bin/env bash
# OS Detector - Detects platform and outputs JSON

set -euo pipefail

detect_os() {
    local os_type=""
    local os_name=""
    
    # Detect OS type
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_type="linux"
        if [ -f /etc/os-release ]; then
            os_name=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d'"' -f2)
        else
            os_name="Linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macos"
        os_name="macOS $(sw_vers -productVersion 2>/dev/null || echo 'Unknown')"
    elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
        os_type="windows"
        os_name="Windows"
    else
        os_type="unknown"
        os_name="Unknown OS"
    fi
    
    # Output JSON
    cat <<EOF
{
  "platform": "${os_type}",
  "os_name": "${os_name}",
  "ostype": "${OSTYPE}"
}
EOF
}

detect_os
exit 0
