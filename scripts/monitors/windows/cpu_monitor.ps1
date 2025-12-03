# CPU Monitor - PowerShell version
# Collects CPU usage and load averages

$ErrorActionPreference = "Stop"

function Get-CpuMetrics {
    try {
        # Get CPU usage percentage with averaging over 5 samples
        $cpuSamples = @()
        for ($i = 0; $i -lt 5; $i++) {
            $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
            $cpuSamples += $cpuCounter.CounterSamples[0].CookedValue
            if ($i -lt 4) { Start-Sleep -Milliseconds 200 }
        }
        $cpuUsage = [math]::Round(($cpuSamples | Measure-Object -Average).Average, 1)
        
        # Get processor info for load calculation
        $processors = Get-CimInstance Win32_Processor -ErrorAction Stop
        $logicalProcessors = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        
        # Get CPU vendor and model
        $firstProcessor = $processors | Select-Object -First 1
        $cpuVendor = switch ($firstProcessor.Manufacturer) {
            "GenuineIntel" { "Intel" }
            "AuthenticAMD" { "AMD" }
            default { $firstProcessor.Manufacturer }
        }
        $cpuModel = $firstProcessor.Name.Trim()
        
        # Windows doesn't have load averages like Unix, so we'll use queue length as approximation
        $queueLength = (Get-Counter '\System\Processor Queue Length' -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
        
        # Approximate load averages (normalized by CPU count)
        $load = if ($logicalProcessors -gt 0) { [math]::Round($queueLength / $logicalProcessors, 2) } else { 0 }
        
        $result = @{
            cpu = @{
                usage_percent = $cpuUsage
                load_1 = $load
                load_5 = $load
                load_15 = $load
                logical_processors = $logicalProcessors
                vendor = $cpuVendor
                model = $cpuModel
            }
        }
        
        return $result | ConvertTo-Json -Compress
    }
    catch {
        $result = @{
            cpu = @{
                status = "error"
                error = $_.Exception.Message
            }
        }
        return $result | ConvertTo-Json -Compress
    }
}

Get-CpuMetrics
exit 0
