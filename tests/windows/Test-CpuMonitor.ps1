# Test for cpu_monitor.ps1

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
$monitorScript = Join-Path $projectRoot "scripts\monitors\windows\cpu_monitor.ps1"

Write-Host "Testing cpu_monitor.ps1..."

try {
    # Run the monitor
    $output = & PowerShell -ExecutionPolicy Bypass -File $monitorScript
    
    # Check if output is valid JSON
    $json = $output | ConvertFrom-Json
    
    # Check for required fields
    if (-not $json.cpu) {
        Write-Host "[FAIL] Missing 'cpu' field"
        exit 1
    }
    
    if (-not ($json.cpu.PSObject.Properties.Name -contains 'usage_percent')) {
        Write-Host "[FAIL] Missing 'usage_percent' field"
        exit 1
    }
    
    Write-Host "[PASS] cpu_monitor.ps1"
    exit 0
}
catch {
    Write-Host "[FAIL] cpu_monitor.ps1: $_"
    exit 1
}
