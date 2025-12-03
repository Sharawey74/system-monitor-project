# Memory Monitor - PowerShell version
# Collects memory statistics

$ErrorActionPreference = "Stop"

function Get-MemoryMetrics {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        
        $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
        $freeMB = [math]::Round($os.FreePhysicalMemory / 1024, 0)
        $usedMB = $totalMB - $freeMB
        
        $result = @{
            memory = @{
                total_mb = $totalMB
                used_mb = $usedMB
                free_mb = $freeMB
                available_mb = $freeMB
            }
        }
        
        return $result | ConvertTo-Json -Compress
    }
    catch {
        $result = @{
            memory = @{
                status = "error"
                error = $_.Exception.Message
            }
        }
        return $result | ConvertTo-Json -Compress
    }
}

Get-MemoryMetrics
exit 0
