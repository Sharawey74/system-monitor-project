# Test for temperature_monitor.ps1

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
$monitorScript = Join-Path $projectRoot "scripts\monitors\windows\temperature_monitor.ps1"
$jsonOutputDir = Join-Path $scriptPath "json"
$jsonOutputFile = Join-Path $jsonOutputDir "temperature_output.json"

Write-Host "Temperature Monitor Test - Windows"
Write-Host "==================================="

# Create json directory if it doesn't exist
if (-not (Test-Path $jsonOutputDir)) {
    New-Item -ItemType Directory -Path $jsonOutputDir -Force | Out-Null
}

try {
    # Run the monitor
    $output = & PowerShell -ExecutionPolicy Bypass -File $monitorScript
    
    # Save output to file
    $output | Set-Content -Path $jsonOutputFile -Encoding UTF8
    Write-Host "JSON output saved to: $jsonOutputFile"
    
    # Check if output is valid JSON
    $json = $output | ConvertFrom-Json
    
    # Display results based on status
    if ($json.status -eq "unavailable") {
        Write-Host "Status: unavailable"
        Write-Host "CPU Temperature: N/A"
        Write-Host "GPU Temperature: N/A"
    }
    elseif ($json.status -eq "error") {
        Write-Host "Status: error"
        Write-Host "CPU Temperature: N/A"
        Write-Host "GPU Temperature: N/A"
    }
    else {
        Write-Host "Status: ok"
        
        # Display CPU temperature
        $cpuTemp = $json.cpu.temperature_celsius
        if ($cpuTemp -gt 0) {
            Write-Host "CPU Temperature: $($cpuTemp)°C"
        } else {
            Write-Host "CPU Temperature: N/A"
        }
        
        # Display GPU information
        Write-Host "GPU Count: $($json.gpu_count)"
        
        if ($json.gpus -and $json.gpus.Count -gt 0) {
            foreach ($gpu in $json.gpus) {
                $gpuTemp = $gpu.temperature_celsius
                $gpuVendor = $gpu.vendor
                $gpuModel = $gpu.model
                $gpuType = $gpu.type
                
                Write-Host ""
                Write-Host "GPU [$($gpu.index)] - $gpuVendor $gpuModel ($gpuType):"
                
                if ($gpuTemp -gt 0) {
                    Write-Host "  Temperature: $($gpuTemp)°C (source: $($gpu.temperature_source))"
                } else {
                    Write-Host "  Temperature: N/A"
                }
                
                if ($gpu.vram_total_mb -gt 0) {
                    $vramGB = [math]::Round($gpu.vram_total_mb / 1024, 2)
                    $vramUsedGB = [math]::Round($gpu.vram_used_mb / 1024, 2)
                    Write-Host "  VRAM: $vramUsedGB / $vramGB GB"
                }
            }
        } else {
            Write-Host "GPU Temperature: N/A"
        }
    }
    
    Write-Host "Validation: PASSED"
    exit 0
}
catch {
    Write-Host "Validation: FAILED"
    Write-Host "Error: $_"
    exit 1
}
