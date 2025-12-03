# Test for memory_monitor.ps1

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
$monitorScript = Join-Path $projectRoot "scripts\monitors\windows\memory_monitor.ps1"

Write-Host "Testing memory_monitor.ps1..."

try {
    # Run the monitor
    $output = & PowerShell -ExecutionPolicy Bypass -File $monitorScript
    
    # Check if output is valid JSON
    $json = $output | ConvertFrom-Json
    
    # Check for required fields
    if (-not $json.memory) {
        Write-Host "[FAIL] Missing 'memory' field"
        exit 1
    }
    
    if (-not ($json.memory.PSObject.Properties.Name -contains 'total_mb')) {
        Write-Host "[FAIL] Missing 'total_mb' field"
        exit 1
    }
    
    Write-Host "[PASS] memory_monitor.ps1"
    exit 0
}
catch {
    Write-Host "[FAIL] memory_monitor.ps1: $_"
    exit 1
}
