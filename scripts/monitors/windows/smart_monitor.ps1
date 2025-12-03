# SMART Monitor - PowerShell version
# Collects disk health data

$ErrorActionPreference = "Stop"

function Get-SmartMetrics {
    try {
        # Try to get disk health from WMI
        $disks = Get-CimInstance -Namespace "root/wmi" -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        
        if ($disks) {
            $smartArray = @()
            
            # Get physical disk info
            $physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
            
            foreach ($disk in $physicalDisks) {
                $health = "UNKNOWN"
                if ($disk.HealthStatus -eq "Healthy") {
                    $health = "PASSED"
                }
                elseif ($disk.HealthStatus -eq "Unhealthy" -or $disk.HealthStatus -eq "Warning") {
                    $health = "FAILED"
                }
                
                $smartArray += @{
                    device = "PhysicalDisk$($disk.DeviceId)"
                    health = $health
                    power_on_hours = 0
                }
            }
            
            if ($smartArray.Count -gt 0) {
                $result = @{
                    smart = $smartArray
                }
                
                return $result | ConvertTo-Json -Compress -Depth 10
            }
        }
        
        # SMART data not available or restricted
        $result = @{
            smart = @{
                status = "restricted"
            }
        }
        
        return $result | ConvertTo-Json -Compress
    }
    catch {
        $result = @{
            smart = @{
                status = "restricted"
            }
        }
        return $result | ConvertTo-Json -Compress
    }
}

Get-SmartMetrics
exit 0
