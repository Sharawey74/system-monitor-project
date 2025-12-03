# Test for smart_monitor.ps1

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
$monitorScript = Join-Path $projectRoot "scripts\monitors\windows\smart_monitor.ps1"

Write-Host "Testing smart_monitor.ps1..."

try {
    # Run the monitor
    $output = & PowerShell -ExecutionPolicy Bypass -File $monitorScript
    
    # Check if output is valid JSON
    $json = $output | ConvertFrom-Json
    
    # Check for required fields
    if (-not $json.smart) {
        Write-Host "[FAIL] Missing 'smart' field"
        exit 1
    }
    
    Write-Host "[PASS] smart_monitor.ps1"
    exit 0
}
catch {
    Write-Host "[FAIL] smart_monitor.ps1: $_"
    exit 1
}
