# Temperature Monitor - PowerShell version
# Attempts to collect temperature data

$ErrorActionPreference = "Stop"

function Get-TemperatureMetrics {
    try {
        # Try to get temperature from WMI (not commonly available on standard Windows)
        $temps = Get-CimInstance -Namespace "root/wmi" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        
        if ($temps) {
            $cpuTemp = 0
            $count = 0
            
            foreach ($temp in $temps) {
                # Convert from tenths of Kelvin to Celsius
                $celsius = ($temp.CurrentTemperature / 10) - 273.15
                $cpuTemp += $celsius
                $count++
            }
            
            if ($count -gt 0) {
                $cpuTemp = [math]::Round($cpuTemp / $count, 1)
                
                $result = @{
                    temperature = @{
                        cpu_celsius = $cpuTemp
                        gpu_celsius = 0
                    }
                }
                
                return $result | ConvertTo-Json -Compress
            }
        }
        
        # Temperature not available
        $result = @{
            temperature = @{
                status = "unavailable"
            }
        }
        
        return $result | ConvertTo-Json -Compress
    }
    catch {
        $result = @{
            temperature = @{
                status = "unavailable"
            }
        }
        return $result | ConvertTo-Json -Compress
    }
}

Get-TemperatureMetrics
exit 0
