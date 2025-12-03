# Test for main_monitor.ps1

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
$monitorScript = Join-Path $projectRoot "scripts\main_monitor.ps1"
$outputFile = Join-Path $projectRoot "data\metrics\current.json"

Write-Host "Testing main_monitor.ps1..."

try {
    # Run the main monitor
    & PowerShell -ExecutionPolicy Bypass -File $monitorScript | Out-Null
    
    # Check if output file exists
    if (-not (Test-Path $outputFile)) {
        Write-Host "[FAIL] Output file not created: $outputFile"
        exit 1
    }
    
    # Check if output file contains valid JSON
    $content = Get-Content $outputFile -Raw
    $json = $content | ConvertFrom-Json
    
    # Check for timestamp
    if (-not ($json.PSObject.Properties.Name -contains 'timestamp')) {
        Write-Host "[FAIL] Missing 'timestamp' field in output"
        exit 1
    }
    
    Write-Host "[PASS] main_monitor.ps1"
    exit 0
}
catch {
    Write-Host "[FAIL] main_monitor.ps1: $_"
    exit 1
}
