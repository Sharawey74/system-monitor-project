# Temperature Monitor - Enhanced Merged Version
# Features: Multi-GPU support, vendor-independent detection, comprehensive metrics
# Fixed: Correct vendor detection order and nvidia-smi GPU indexing

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
        return "Unknown"
    }
}

function Get-AllGpuInfo {
    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        $gpuList = @()
        
        foreach ($gpu in $gpus) {
            $vendor = "Unknown"
            $model = "Unknown"
            $type = "Unknown"
            $vramTotal = 0
            
            # Enhanced vendor detection with CORRECT ORDER (most specific first)
            $gpuName = $gpu.Name
            $gpuCompat = $gpu.AdapterCompatibility
            
            # CRITICAL: Check Intel FIRST (before AMD) to prevent false AMD detection
            # Many Intel integrated GPUs show "AMD Radeon Graphics" in name
            if ($gpuName -match "Intel.*Graphics|Iris|UHD Graphics|HD Graphics" -or $gpuCompat -like "*Intel*") {
                $vendor = "Intel"
                $model = $gpuName -replace "Intel\(R\) ", "" -replace "Graphics ", "" -replace "\(R\)", "" -replace "\(TM\)", ""
                $type = if ($gpuName -match "Arc") { "Dedicated" } else { "Integrated" }
            }
            # NVIDIA Detection (check before AMD due to naming conflicts)
            elseif ($gpuName -match "NVIDIA|GeForce|GTX|RTX|Quadro|Tesla|Titan|MX\d{3}" -or $gpuCompat -like "*NVIDIA*") {
                $vendor = "NVIDIA"
                $model = $gpuName -replace "NVIDIA ", "" -replace "GeForce ", "" -replace "\(R\)", "" -replace "\(TM\)", ""
                $type = if ($gpuName -match "RTX|GTX|Quadro|Tesla|Titan|MX\d{3}") { "Dedicated" } else { "Unknown" }
            }
            # AMD Detection (last, as it can cause false positives)
            elseif ($gpuName -match "AMD.*Radeon|^Radeon|RX \d{4}|Vega|RDNA" -or $gpuCompat -like "*AMD*" -or $gpuCompat -like "*ATI*") {
                # Double-check it's not Intel masquerading as AMD
                if ($gpuName -notmatch "Intel|Iris|UHD|HD Graphics") {
                    $vendor = "AMD"
                    $model = $gpuName -replace "AMD ", "" -replace "Radeon ", "" -replace "\(TM\)", ""
                    $type = if ($gpuName -match "RX \d{4}|Vega|Radeon Pro|FirePro") { "Dedicated" } 
                           elseif ($gpuName -match "Graphics") { "Integrated" } 
                           else { "Unknown" }
                } else {
                    # This is actually Intel, not AMD
                    $vendor = "Intel"
                    $model = $gpuName -replace "Intel\(R\) ", "" -replace "Graphics ", "" -replace "\(R\)", "" -replace "\(TM\)", ""
                    $type = "Integrated"
                }
            }
            
            # Get VRAM from WMI (AdapterRAM is in bytes)
            if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
                $vramTotal = [math]::Round($gpu.AdapterRAM / 1MB, 0)
            }
            
            $gpuList += @{
                vendor = $vendor
                model = $model
                type = $type
                vram_total_mb = $vramTotal
                pnp_device_id = $gpu.PNPDeviceID
                driver_version = $gpu.DriverVersion
                wmi_index = $gpuList.Count
            }
        }
        
        return $gpuList
    } catch {
        return @(@{
            vendor = "Unknown"
            model = "Unknown"
            type = "Unknown"
            vram_total_mb = 0
            pnp_device_id = ""
            driver_version = ""
            wmi_index = 0
        })
    }
}

function Get-NvidiaGpuList {
    # Get list of NVIDIA GPUs from nvidia-smi to map WMI index to nvidia-smi index
    try {
        $nvidiaList = & nvidia-smi --query-gpu=index,name --format=csv,noheader 2>$null
        if ($LASTEXITCODE -eq 0 -and $nvidiaList) {
            $gpus = @()
            foreach ($line in $nvidiaList) {
                if ($line -match "^(\d+),\s*(.+)$") {
                    $gpus += @{
                        nvidia_index = [int]$matches[1]
                        name = $matches[2].Trim()
                    }
                }
            }
            return $gpus
        }
    } catch {
        # nvidia-smi not available
    }
    return @()
}

function Get-NvidiaTemperatureAndVram {
    param (
        [string]$gpuName
    )
    
    $result = @{
        temp = 0
        vram_total = 0
        vram_used = 0
        vram_free = 0
        success = $false
        nvidia_index = -1
    }
    
    try {
        # Get all NVIDIA GPUs
        $nvidiaGpus = Get-NvidiaGpuList
        
        if ($nvidiaGpus.Count -eq 0) {
            return $result
        }
        
        # Find matching GPU by name
        $matchedGpu = $null
        foreach ($nvGpu in $nvidiaGpus) {
            # Flexible name matching (handles NVIDIA prefix variations)
            $nvName = $nvGpu.name -replace "NVIDIA ", "" -replace "GeForce ", ""
            $searchName = $gpuName -replace "NVIDIA ", "" -replace "GeForce ", ""
            
            if ($nvName -like "*$searchName*" -or $searchName -like "*$nvName*") {
                $matchedGpu = $nvGpu
                break
            }
        }
        
        # If no match found and only 1 NVIDIA GPU, use it
        if (-not $matchedGpu -and $nvidiaGpus.Count -eq 1) {
            $matchedGpu = $nvidiaGpus[0]
        }
        
        if ($matchedGpu) {
            $nvidiaIndex = $matchedGpu.nvidia_index
            $result.nvidia_index = $nvidiaIndex
            
            # Query temperature
            $tempOutput = & nvidia-smi --id=$nvidiaIndex --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null
            if ($LASTEXITCODE -eq 0 -and $tempOutput) {
                $result.temp = [int]$tempOutput.Trim()
                $result.success = $true
            }
            
            # Query VRAM
            $memOutput = & nvidia-smi --id=$nvidiaIndex --query-gpu=memory.total,memory.used,memory.free --format=csv,noheader,nounits 2>$null
            if ($LASTEXITCODE -eq 0 -and $memOutput -match "(\d+),\s*(\d+),\s*(\d+)") {
                $result.vram_total = [int]$matches[1]
                $result.vram_used = [int]$matches[2]
                $result.vram_free = [int]$matches[3]
            }
        }
    } catch {
        # nvidia-smi not available or failed
    }
    
    return $result
}

function Get-AmdTemperature {
    try {
        # AMD Radeon Software WMI
        $amdTemp = Get-CimInstance -Namespace root/AMD/AMDPM -ClassName Temperature -ErrorAction SilentlyContinue
        if ($amdTemp) {
            return [int]$amdTemp.CurrentTemperature
        }
    } catch {
        # AMD WMI not available
    }
    
    # Try alternative AMD paths
    try {
        $amdWmi = Get-CimInstance -Namespace root/wmi -ClassName AMDGPU_TemperatureSensor -ErrorAction SilentlyContinue
        if ($amdWmi) {
            return [int]$amdWmi.CurrentTemperature
        }
    } catch {
        # Alternative AMD WMI not available
    }
    
    return 0
}

function Get-IntelTemperature {
    try {
        # Intel Graphics WMI (newer drivers)
        $intelTemp = Get-CimInstance -Namespace root/Intel -ClassName GraphicsTemperature -ErrorAction SilentlyContinue
        if ($intelTemp) {
            return [int]$intelTemp.CurrentTemperature
        }
    } catch {
        # Intel WMI not available
    }
    
    return 0
}

function Get-GenericGpuTemperature {
    try {
        $thermalZones = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        foreach ($zone in $thermalZones) {
            # Look for GPU-related thermal zones
            if ($zone.InstanceName -match "GPU|VGA|Video|Graphics|THRM|TZ0[2-9]") {
                $temp = [math]::Round(($zone.CurrentTemperature / 10) - 273.15, 1)
                if ($temp -gt 0 -and $temp -lt 150) {  # Sanity check
                    return $temp
                }
            }
        }
    } catch {
        # No thermal zones found
    }
    
    return 0
}

function Get-CpuTemperature {
    try {
        $temps = Get-CimInstance -Namespace "root/wmi" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
        
        if ($temps) {
            $tempSum = 0
            $count = 0
            
            foreach ($temp in $temps) {
                $celsius = ($temp.CurrentTemperature / 10) - 273.15
                # Filter out unrealistic values
                if ($celsius -gt 0 -and $celsius -lt 150) {
                    $tempSum += $celsius
                    $count++
                }
            }
            
            if ($count -gt 0) {
                return [math]::Round($tempSum / $count, 1)
            }
        }
    } catch {
        # CPU temperature not available
    }
    
    return 0
}

function Get-TemperatureMetrics {
    $cpuVendor = Get-CpuVendor
    $cpuTemp = Get-CpuTemperature
    $allGpus = Get-AllGpuInfo
    $gpuMetrics = @()
    
    # Process each GPU
    foreach ($gpu in $allGpus) {
        $gpuTemp = 0
        $vramTotal = $gpu.vram_total_mb
        $vramUsed = 0
        $vramFree = 0
        $tempSource = "none"
        $nvidiaIndex = -1
        
        # Try temperature detection based on ACTUAL vendor (now correctly detected)
        
        # 1. NVIDIA GPUs - use nvidia-smi with name matching
        if ($gpu.vendor -eq "NVIDIA") {
            $nvidiaResult = Get-NvidiaTemperatureAndVram -gpuName $gpu.model
            if ($nvidiaResult.success) {
                $gpuTemp = $nvidiaResult.temp
                $tempSource = "nvidia-smi"
                $nvidiaIndex = $nvidiaResult.nvidia_index
                
                # Override VRAM if nvidia-smi provides better data
                if ($nvidiaResult.vram_total -gt 0) {
                    $vramTotal = $nvidiaResult.vram_total
                    $vramUsed = $nvidiaResult.vram_used
                    $vramFree = $nvidiaResult.vram_free
                }
            }
        }
        
        # 2. AMD GPUs - use AMD WMI
        if ($gpu.vendor -eq "AMD" -and $gpuTemp -eq 0) {
            $amdTemp = Get-AmdTemperature
            if ($amdTemp -gt 0) {
                $gpuTemp = $amdTemp
                $tempSource = "amd-wmi"
            }
        }
        
        # 3. Intel GPUs - use Intel WMI
        if ($gpu.vendor -eq "Intel" -and $gpuTemp -eq 0) {
            $intelTemp = Get-IntelTemperature
            if ($intelTemp -gt 0) {
                $gpuTemp = $intelTemp
                $tempSource = "intel-wmi"
            }
        }
        
        # 4. Generic ACPI fallback for any GPU
        if ($gpuTemp -eq 0) {
            $genericTemp = Get-GenericGpuTemperature
            if ($genericTemp -gt 0) {
                $gpuTemp = $genericTemp
                $tempSource = "acpi-thermal"
            }
        }
        
        $metric = @{
            index = $gpu.wmi_index
            vendor = $gpu.vendor
            model = $gpu.model
            type = $gpu.type
            temperature_celsius = $gpuTemp
            temperature_source = $tempSource
            vram_total_mb = $vramTotal
            vram_used_mb = $vramUsed
            vram_free_mb = $vramFree
            driver_version = $gpu.driver_version
        }
        
        # Add nvidia index only if relevant
        if ($nvidiaIndex -ge 0) {
            $metric.nvidia_smi_index = $nvidiaIndex
        }
        
        $gpuMetrics += $metric
    }
    
    # Determine overall status
    $status = "ok"
    if ($cpuTemp -eq 0 -and ($gpuMetrics | Where-Object { $_.temperature_celsius -gt 0 }).Count -eq 0) {
        $status = "unavailable"
    }
    
    # Build final output
    $output = @{
        timestamp = (Get-Date -Format "o")
        cpu = @{
            temperature_celsius = $cpuTemp
            vendor = $cpuVendor
        }
        gpus = $gpuMetrics
        gpu_count = $gpuMetrics.Count
        status = $status
    }
    
    return $output | ConvertTo-Json -Depth 10 -Compress
}

# Execute and return results
try {
    Get-TemperatureMetrics
    exit 0
} catch {
    # Emergency fallback
    @{
        status = "error"
        error_message = $_.Exception.Message
    } | ConvertTo-Json -Compress
    exit 1
}