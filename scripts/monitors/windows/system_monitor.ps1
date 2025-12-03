# System Monitor - PowerShell version
# Collects system information

$ErrorActionPreference = "Stop"

function Get-SystemMetrics {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        
        $osName = $os.Caption
        $hostname = $cs.Name
        
        # Get uptime in seconds
        $lastBoot = $os.LastBootUpTime
        $uptime = (Get-Date) - $lastBoot
        $uptimeSeconds = [math]::Floor($uptime.TotalSeconds)
        
        # Get OS version
        $version = $os.Version
        
        $result = @{
            system = @{
                os = $osName
                hostname = $hostname
                uptime_seconds = $uptimeSeconds
                kernel = $version
                manufacturer = $cs.Manufacturer
                model = $cs.Model
            }
        }
        
        return $result | ConvertTo-Json -Compress
    }
    catch {
        $result = @{
            system = @{
                status = "error"
                error = $_.Exception.Message
            }
        }
        return $result | ConvertTo-Json -Compress
    }
}

Get-SystemMetrics
exit 0
