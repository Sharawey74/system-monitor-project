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

$platformOutputFile = Join-Path $projectRoot "data\metrics\windows_current.json"
$latestOutputFile = Join-Path $projectRoot "data\metrics\current.json"
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Initialize merged object with metadata
$merged = [ordered]@{
    timestamp = $timestamp
    platform = "windows"
}

# Merge all JSON files with validation and proper structure
foreach ($file in $tempFiles) {
    if (Test-Path $file) {
        try {
            $content = Get-Content $file -Raw -ErrorAction Stop
            $content = $content.Trim()
            
            # Validate JSON syntax
            $jsonObj = $content | ConvertFrom-Json -ErrorAction Stop
            
            # Get monitor name from filename
            $monitorName = [System.IO.Path]::GetFileNameWithoutExtension($file)
            
            # Determine the key name based on monitor type
            $keyName = switch ($monitorName) {
                "system_monitor" { "system" }
                "cpu_monitor" { "cpu" }
                "memory_monitor" { "memory" }
                "disk_monitor" { "disk" }
                "network_monitor" { "network" }
                "temperature_monitor" { "temperature" }
                "fan_monitor" { "fans" }
                "smart_monitor" { "smart" }
                default { $monitorName }
            }
            
            # Merge properties from this collector
            foreach ($prop in $jsonObj.PSObject.Properties) {
                if ($prop.Name -eq $keyName) {
                    # Already has the correct key
                    $merged[$keyName] = $prop.Value
                } else {
                    # Add under the determined key
                    $merged[$keyName] = $jsonObj
                    break
                }
            }
            
            Write-Log "INFO" "Successfully merged: $(Split-Path -Leaf $file)"
        }
        catch {
            $errorMsg = "Failed to parse JSON from ${file}: $($_.Exception.Message)"
            Write-Log "ERROR" $errorMsg
        }
    }
}

# Write merged JSON to platform-specific file
$merged | ConvertTo-Json -Depth 10 | Set-Content -Path $platformOutputFile -Encoding UTF8
Write-Log "INFO" "Windows data written to windows_current.json"

# Also write to current.json as the latest run
$merged | ConvertTo-Json -Depth 10 | Set-Content -Path $latestOutputFile -Encoding UTF8
Write-Log "INFO" "Latest data written to current.json"

# Clean up temp files
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Log "INFO" "Monitoring collection completed"

Write-Host "Monitoring data written to:"
Write-Host "  - Platform-specific: $platformOutputFile"
Write-Host "  - Latest run: $latestOutputFile"

exit 0
