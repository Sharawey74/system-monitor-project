# Test for disk_monitor.ps1

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
$monitorScript = Join-Path $projectRoot "scripts\monitors\windows\disk_monitor.ps1"

Write-Host "Testing disk_monitor.ps1..."

try {
    # Run the monitor
    $output = & PowerShell -ExecutionPolicy Bypass -File $monitorScript
    
    # Check if output is valid JSON
    $json = $output | ConvertFrom-Json
    
    # Check for required fields
    if (-not $json.disk) {
        Write-Host "[FAIL] Missing 'disk' field"
        exit 1
    }
    
    Write-Host "[PASS] disk_monitor.ps1"
    exit 0
}
catch {
    Write-Host "[FAIL] disk_monitor.ps1: $_"
    exit 1
}
