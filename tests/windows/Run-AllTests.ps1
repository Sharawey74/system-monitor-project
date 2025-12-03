# Run all Windows tests

$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== Running All Windows Tests ==="
Write-Host ""

# Array of test scripts
$tests = @(
    "Test-CpuMonitor.ps1",
    "Test-MemoryMonitor.ps1",
    "Test-DiskMonitor.ps1",
    "Test-NetworkMonitor.ps1",
    "Test-TemperatureMonitor.ps1",
    "Test-FanMonitor.ps1",
    "Test-SmartMonitor.ps1",
    "Test-MainMonitor.ps1"
)

# Track results
$passed = 0
$failed = 0
$failedTests = @()

# Run each test
foreach ($test in $tests) {
    $testPath = Join-Path $scriptPath $test
    
    if (Test-Path $testPath) {
        try {
            & PowerShell -ExecutionPolicy Bypass -File $testPath
            if ($LASTEXITCODE -eq 0) {
                $passed++
            }
            else {
                $failed++
                $failedTests += $test
            }
        }
        catch {
            $failed++
            $failedTests += $test
            Write-Host "[FAIL] $test threw exception: $_"
        }
    }
    else {
        Write-Host "[WARN] Test not found: $test"
    }
}

# Print summary
Write-Host ""
Write-Host "=== Test Summary ==="
Write-Host "Passed: $passed"
Write-Host "Failed: $failed"

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:"
    foreach ($test in $failedTests) {
        Write-Host "  - $test"
    }
    exit 1
}

Write-Host ""
Write-Host "All tests passed!"
exit 0
