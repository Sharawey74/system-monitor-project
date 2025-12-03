# JSON Writer - PowerShell version
# Merges JSON fragments into a single file

param(
    [string[]]$JsonFiles
)

$ErrorActionPreference = "Stop"

# Get project root
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptPath)
$outputFile = Join-Path $projectRoot "data\metrics\current.json"

# Ensure output directory exists
$outputDir = Split-Path -Parent $outputFile
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

# Get timestamp in ISO 8601 format
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Initialize merged object
$merged = @{
    timestamp = $timestamp
}

# Merge all JSON files
if ($JsonFiles) {
    foreach ($file in $JsonFiles) {
        if (Test-Path $file) {
            try {
                $content = Get-Content $file -Raw -ErrorAction Stop
                
                # Remove any BOM or whitespace issues
                $content = $content.Trim()
                
                # Parse JSON
                $jsonObj = $content | ConvertFrom-Json -ErrorAction Stop
                
                # Merge properties from this collector into the merged object
                foreach ($prop in $jsonObj.PSObject.Properties) {
                    $merged[$prop.Name] = $prop.Value
                }
            }
            catch {
                # Log error but continue with other files
                $errorMsg = "Failed to parse JSON from ${file}: $($_.Exception.Message)"
                Add-Content -Path (Join-Path $projectRoot "data\logs\system.log") -Value "[$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')] [ERROR] $errorMsg"
            }
        }
    }
}

# Write merged JSON to output file
$merged | ConvertTo-Json -Depth 10 | Set-Content -Path $outputFile -Encoding UTF8

exit 0
