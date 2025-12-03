# Network Monitor - PowerShell version
# Collects network interface statistics

$ErrorActionPreference = "Stop"

function Get-NetworkMetrics {
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        
        $networkArray = @()
        foreach ($adapter in $adapters) {
            try {
                $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
                
                if ($stats) {
                    $networkArray += @{
                        iface = $adapter.Name
                        rx_bytes = $stats.ReceivedBytes
                        tx_bytes = $stats.SentBytes
                    }
                }
            }
            catch {
                # Skip adapters that don't support statistics
                continue
            }
        }
        
        $result = @{
            network = $networkArray
        }
        
        return $result | ConvertTo-Json -Compress -Depth 10
    }
    catch {
        $result = @{
            network = @{
                status = "error"
                error = $_.Exception.Message
            }
        }
        return $result | ConvertTo-Json -Compress
    }
}

Get-NetworkMetrics
exit 0
