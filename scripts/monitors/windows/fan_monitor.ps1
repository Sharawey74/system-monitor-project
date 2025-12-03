# Fan Monitor - PowerShell version
# Attempts to collect fan speed data

$ErrorActionPreference = "Stop"

function Get-FanMetrics {
    try {
        # Try to get fan data from WMI (not commonly available on standard Windows)
        $fans = Get-CimInstance -Namespace "root/wmi" -ClassName MSAcpi_FanSpeed -ErrorAction SilentlyContinue
        
        if ($fans) {
            $fanArray = @()
            $index = 1
            
            foreach ($fan in $fans) {
                if ($fan.CurrentSpeed -gt 0) {
                    $fanArray += @{
                        label = "fan$index"
                        rpm = $fan.CurrentSpeed
                    }
                    $index++
                }
            }
            
            if ($fanArray.Count -gt 0) {
                $result = @{
                    fans = $fanArray
                }
                
                return $result | ConvertTo-Json -Compress -Depth 10
            }
        }
        
        # Fan data not available
        $result = @{
            fans = @{
                status = "unavailable"
            }
        }
        
        return $result | ConvertTo-Json -Compress
    }
    catch {
        $result = @{
            fans = @{
                status = "unavailable"
            }
        }
        return $result | ConvertTo-Json -Compress
    }
}

Get-FanMetrics
exit 0
