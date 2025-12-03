# Disk Monitor - PowerShell version
# Collects disk usage statistics

$ErrorActionPreference = "Stop"

function Get-DiskMetrics {
    try {
        $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop | Where-Object { $_.Size -gt 0 }
        
        $diskArray = @()
        foreach ($disk in $disks) {
            $totalGB = [math]::Round($disk.Size / 1GB, 2)
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedGB = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
            $usedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)
            
            $diskArray += @{
                device = $disk.DeviceID
                filesystem = $disk.FileSystem
                total_gb = $totalGB
                used_gb = $usedGB
                used_percent = $usedPercent
            }
        }
        
        $result = @{
            disk = $diskArray
        }
        
        return $result | ConvertTo-Json -Compress -Depth 10
    }
    catch {
        $result = @{
            disk = @{
                status = "error"
                error = $_.Exception.Message
            }
        }
        return $result | ConvertTo-Json -Compress
    }
}

Get-DiskMetrics
exit 0
