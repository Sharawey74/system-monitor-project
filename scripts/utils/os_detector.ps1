# OS Detector - PowerShell version
# Detects platform and outputs JSON

$ErrorActionPreference = "Stop"

function Get-OSInfo {
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $platform = "windows"
        $osName = $osInfo.Caption
        
        $result = @{
            platform = $platform
            os_name = $osName
            version = $osInfo.Version
        }
        
        return $result | ConvertTo-Json -Compress
    }
    catch {
        $result = @{
            platform = "windows"
            os_name = "Windows"
            error = $_.Exception.Message
        }
        return $result | ConvertTo-Json -Compress
    }
}

Get-OSInfo
exit 0
