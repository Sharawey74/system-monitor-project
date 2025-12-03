# Main Monitor - PowerShell orchestrator for Windows

$ErrorActionPreference = "Stop"

# Get script directory and project root
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptPath
$monitorsDir = Join-Path $scriptPath "monitors\windows"
$utilsDir = Join-Path $scriptPath "utils"
$tempDir = Join-Path $projectRoot "data\metrics\temp"
$logFile = Join-Path $projectRoot "data\logs\system.log"

# Ensure directories exist
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $logFile) | Out-Null

# Logging function
function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry
}

Write-Log "INFO" "Starting system monitoring collection"

# List of monitors to run
$monitors = @(
    "system_monitor.ps1",
    "cpu_monitor.ps1",
    "memory_monitor.ps1",
    "disk_monitor.ps1",
    "network_monitor.ps1",
    "temperature_monitor.ps1",
    "fan_monitor.ps1",
    "smart_monitor.ps1"
)

# Array to store temp file paths
$tempFiles = @()

# Run each monitor
foreach ($monitor in $monitors) {
    $monitorPath = Join-Path $monitorsDir $monitor
    $monitorName = [System.IO.Path]::GetFileNameWithoutExtension($monitor)
    $tempFile = Join-Path $tempDir "$monitorName.json"
    
    if (Test-Path $monitorPath) {
        Write-Log "INFO" "Running $monitor"
        
        try {
            # Run monitor and save output
            $output = & PowerShell -ExecutionPolicy Bypass -File $monitorPath
            $output | Set-Content -Path $tempFile -Encoding UTF8
            $tempFiles += $tempFile
            Write-Log "INFO" "$monitor completed successfully"
        }
        catch {
            Write-Log "ERROR" "$monitor failed: $_"
            # Create error JSON
            $errorJson = @{
                $monitorName = @{
                    status = "error"
                    error = $_.Exception.Message
                }
            } | ConvertTo-Json -Compress
            $errorJson | Set-Content -Path $tempFile -Encoding UTF8
            $tempFiles += $tempFile
        }
    }
    else {
        Write-Log "WARN" "$monitor not found at $monitorPath"
    }
}

# Merge all JSON files inline
Write-Log "INFO" "Merging JSON outputs"

$outputFile = Join-Path $projectRoot "data\metrics\current.json"
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Initialize merged object
$merged = @{
    timestamp = $timestamp
}

# Merge all JSON files
foreach ($file in $tempFiles) {
    if (Test-Path $file) {
        try {
            $content = Get-Content $file -Raw -ErrorAction Stop
            $content = $content.Trim()
            $jsonObj = $content | ConvertFrom-Json -ErrorAction Stop
            
            # Merge properties from this collector
            foreach ($prop in $jsonObj.PSObject.Properties) {
                $merged[$prop.Name] = $prop.Value
            }
        }
        catch {
            $errorMsg = "Failed to parse JSON from ${file}: $($_.Exception.Message)"
            Write-Log "ERROR" $errorMsg
        }
    }
}

# Write merged JSON to output file
$merged | ConvertTo-Json -Depth 10 | Set-Content -Path $outputFile -Encoding UTF8

# Clean up temp files
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Log "INFO" "Monitoring collection completed"

$outputFile = Join-Path $projectRoot "data\metrics\current.json"
Write-Host "Monitoring data written to $outputFile"

exit 0
