# CPU Monitor - PowerShell version
# Collects CPU usage and load averages

$ErrorActionPreference = "Stop"

function Get-CpuMetrics {
    try {
        # Get CPU usage percentage
        $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
        $cpuUsage = [math]::Round($cpuCounter.CounterSamples[0].CookedValue, 1)
        
        # Get processor info for load calculation
        $processors = Get-CimInstance Win32_Processor -ErrorAction Stop
        $logicalProcessors = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        
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
