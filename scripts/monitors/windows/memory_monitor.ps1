# Memory Monitor - PowerShell version
# Collects memory statistics

$ErrorActionPreference = "Stop"

function Get-MemoryMetrics {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        
        $totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0)
        $freeMB = [math]::Round($os.FreePhysicalMemory / 1024, 0)
        $usedMB = $totalMB - $freeMB
        
        # Get physical RAM modules information
        $ramModules = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
        $modules = @()
        
        if ($ramModules) {
            foreach ($ram in $ramModules) {
                $capacityGB = [math]::Round($ram.Capacity / 1GB, 2)
                $speedMHz = $ram.Speed
                $manufacturer = if ($ram.Manufacturer) { $ram.Manufacturer.Trim() } else { "Unknown" }
                $memoryType = switch ($ram.SMBIOSMemoryType) {
                    20 { "DDR" }
                    21 { "DDR2" }
                    22 { "DDR2 FB-DIMM" }
                    24 { "DDR3" }
                    26 { "DDR4" }
                    34 { "DDR5" }
                    default { "Unknown" }
                }
                $formFactor = switch ($ram.FormFactor) {
                    8 { "DIMM" }
                    12 { "SODIMM" }
                    default { "Unknown" }
                }
                
                $modules += @{
                    manufacturer = $manufacturer
                    capacity_gb = $capacityGB
                    speed_mhz = $speedMHz
                    type = $memoryType
                    form_factor = $formFactor
                }
            }
        }
        
        $result = @{
            memory = @{
                total_mb = $totalMB
                used_mb = $usedMB
                free_mb = $freeMB
                available_mb = $freeMB
            }
        }
        
        if ($modules.Count -gt 0) {
            $result.memory.modules = $modules
        }
        
        return $result | ConvertTo-Json -Compress -Depth 5
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
