# Temperature Monitor - PowerShell version
# Attempts to collect temperature data with multi-vendor GPU support

$ErrorActionPreference = "Stop"

function Get-CpuVendor {
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu.Manufacturer -like "*Intel*") {
            return "Intel"
        } elseif ($cpu.Manufacturer -like "*AMD*") {
            return "AMD"
        } else {
            return $cpu.Manufacturer
        }
    } catch {
        return "unknown"
    }
}

function Get-GpuVendor {
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gpu.Name -like "*NVIDIA*" -or $gpu.AdapterCompatibility -like "*NVIDIA*") {
            return "NVIDIA"
        } elseif ($gpu.Name -like "*AMD*" -or $gpu.Name -like "*Radeon*" -or $gpu.AdapterCompatibility -like "*AMD*") {
            return "AMD"
        } elseif ($gpu.Name -like "*Intel*" -or $gpu.AdapterCompatibility -like "*Intel*") {
            return "Intel"
        } else {
            return "unknown"
        }
    } catch {
        return "unknown"
    }
}

function Get-TemperatureMetrics {
    $cpuTemp = 0
    $gpuTemp = 0
    $status = "ok"
    $cpuVendor = Get-CpuVendor
    $gpuVendor = Get-GpuVendor
    
    try {
        # Try to get CPU temperature from WMI (not commonly available on standard Windows)
        $temps = Get-CimInstance -Namespace "root/wmi" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        
        if ($temps) {
            $tempSum = 0
            $count = 0
            
            foreach ($temp in $temps) {
                # Convert from tenths of Kelvin to Celsius
                $celsius = ($temp.CurrentTemperature / 10) - 273.15
                $tempSum += $celsius
                $count++
            }
            
            if ($count -gt 0) {
                $cpuTemp = [math]::Round($tempSum / $count, 1)
            }
        }
        
        # GPU Temperature - Multi-vendor detection
        
        # 1. Try NVIDIA (nvidia-smi)
        try {
            $nvidiaSmi = & nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null
            if ($LASTEXITCODE -eq 0 -and $nvidiaSmi) {
                $gpuTemp = [int]$nvidiaSmi.Trim()
            }
        } catch {
            # NVIDIA not available
        }
        
        # 2. Try AMD if NVIDIA not found
        if ($gpuTemp -eq 0) {
            try {
                # AMD Radeon Software creates WMI entries
                $amdTemp = Get-CimInstance -Namespace root/AMD/AMDPM -ClassName Temperature -ErrorAction SilentlyContinue
                if ($amdTemp) {
                    $gpuTemp = [int]$amdTemp.CurrentTemperature
                }
            } catch {
                # AMD WMI not available
            }
        }
        
        # 3. Try Intel if others not found
        if ($gpuTemp -eq 0) {
            try {
                # Intel Graphics WMI (newer drivers)
                $intelTemp = Get-CimInstance -Namespace root/Intel -ClassName GraphicsTemperature -ErrorAction SilentlyContinue
                if ($intelTemp) {
                    $gpuTemp = [int]$intelTemp.CurrentTemperature
                }
            } catch {
                # Intel WMI not available
            }
        }
        
        # 4. Fallback: Try generic ACPI/WMI thermal zones for discrete GPUs
        if ($gpuTemp -eq 0) {
            try {
                $thermalZones = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
                foreach ($zone in $thermalZones) {
                    # Some systems label GPU zones as TZ02, TZ03, etc.
                    if ($zone.InstanceName -like "*GPU*" -or $zone.InstanceName -like "*VGA*" -or $zone.InstanceName -like "*Video*") {
                        $gpuTemp = [math]::Round(($zone.CurrentTemperature / 10) - 273.15, 1)
                        break
                    }
                }
            } catch {
                # No thermal zones found
            }
        }
        
        # Check if we have any temperature data
        if ($cpuTemp -eq 0 -and $gpuTemp -eq 0) {
            $status = "unavailable"
        }
        
    } catch {
        $status = "error"
    }
    
    # Return simple JSON format
    if ($status -eq "unavailable") {
        return @{
            status = "unavailable"
        } | ConvertTo-Json -Compress
    } elseif ($status -eq "error") {
        return @{
            status = "error"
        } | ConvertTo-Json -Compress
    } else {
        return @{
            cpu_celsius = $cpuTemp
            cpu_vendor = $cpuVendor
            gpu_celsius = $gpuTemp
            gpu_vendor = $gpuVendor
            status = $status
        } | ConvertTo-Json -Compress
    }
}

Get-TemperatureMetrics
exit 0
