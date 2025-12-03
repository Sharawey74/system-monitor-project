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
        Write-Host "CPU Temperature: $($json.cpu_celsius)°C"
        Write-Host "GPU Temperature: $($json.gpu_celsius)°C"
    }
    
    Write-Host "Validation: PASSED"
    exit 0
}
catch {
    Write-Host "Validation: FAILED"
    Write-Host "Error: $_"
    exit 1
}
