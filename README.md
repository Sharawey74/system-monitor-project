# Hybrid System Monitoring Platform - Stage 1

A cross-platform system monitoring solution with native collectors for both Unix (Linux/macOS) and Windows platforms.

## Features

- **Cross-Platform Support**: Native implementations for Unix (Bash) and Windows (PowerShell)
- **Comprehensive Metrics**: CPU, memory, disk, network, temperature, fan speed, SMART disk health, and system info
- **Production-Ready**: Error handling, logging, graceful degradation for unavailable metrics
- **Fully Tested**: Complete test suites for both platforms
- **JSON Output**: Standardized JSON format with timestamps

## Directory Structure

```
system-monitor-project/
├── scripts/
│   ├── main_monitor.sh              # Unix orchestrator
│   ├── main_monitor.ps1             # Windows orchestrator
│   ├── install.sh                   # Installation script
│   ├── monitors/
│   │   ├── unix/                    # 8 Unix collectors (Bash)
│   │   └── windows/                 # 8 Windows collectors (PowerShell)
│   └── utils/                       # Utility scripts (OS detection, JSON merging, logging)
├── data/
│   ├── metrics/
│   │   └── current.json             # Output file
│   └── logs/
│       └── system.log               # Log file
└── tests/
    ├── unix/                        # Unix test suite (9 tests + runner)
    └── windows/                     # Windows test suite (8 tests + runner)
```

## Installation

### Windows (PowerShell)

```powershell
cd c:\Users\DELL\Desktop\wso\system-monitor-project
# No installation needed - PowerShell scripts run directly
```

### Unix (Linux/macOS)

```bash
cd /path/to/system-monitor-project
bash scripts/install.sh
```

The install script will:
- Create required directories
- Set executable permissions
- Check for optional tools (sensors, smartctl, jq)

## Usage

### Windows

Run the monitoring system:
```powershell
.\scripts\main_monitor.ps1
```

View results:
```powershell
Get-Content data\metrics\current.json
```

Run tests:
```powershell
.\tests\windows\Run-AllTests.ps1
```

### Unix (Linux/macOS)

Run the monitoring system:
```bash
bash scripts/main_monitor.sh
```

View results:
```bash
cat data/metrics/current.json
```

Run tests:
```bash
bash tests/unix/run_all_tests.sh
```

## Collectors

### Core Collectors (Available on all platforms)

1. **CPU Monitor**: Usage percentage and load averages
2. **Memory Monitor**: Total, used, free, and available memory
3. **Disk Monitor**: Usage statistics for all mounted drives
4. **Network Monitor**: RX/TX bytes for all network interfaces
5. **System Monitor**: OS info, hostname, uptime, kernel version

### Optional Collectors (May return "unavailable" or "restricted")

6. **Temperature Monitor**: CPU/GPU temperatures (requires sensors on Unix, WMI on Windows)
7. **Fan Monitor**: Fan speeds (requires sensors on Unix, WMI on Windows)
8. **SMART Monitor**: Disk health data (requires smartctl/admin privileges)

## JSON Output Format

```json
{
  "timestamp": "2025-12-02T15:20:00Z",
  "system": {
    "os": "Windows 10 Pro",
    "hostname": "DESKTOP-ABC123",
    "uptime_seconds": 123456,
    "kernel": "10.0.19045"
  },
  "cpu": {
    "usage_percent": 25.3,
    "load_1": 0.15,
    "load_5": 0.12,
    "load_15": 0.10
  },
  "memory": {
    "total_mb": 16384,
    "used_mb": 8192,
    "free_mb": 8192,
    "available_mb": 8192
  },
  "disk": [
    {
      "device": "C:",
      "filesystem": "NTFS",
      "total_gb": 256.00,
      "used_gb": 120.50,
      "used_percent": 47.1
    }
  ],
  "network": [
    {
      "iface": "Ethernet",
      "rx_bytes": 1234567890,
      "tx_bytes": 987654321
    }
  ],
  "temperature": {
    "status": "unavailable"
  },
  "fans": {
    "status": "unavailable"
  },
  "smart": {
    "status": "restricted"
  }
}
```

## Error Handling

All collectors handle errors gracefully:

- **Missing Tools**: Returns `"status": "unavailable"` if required tools aren't installed
- **Permission Issues**: Returns `"status": "restricted"` if elevated privileges are needed
- **Execution Errors**: Returns `"status": "error"` with error message
- **Exit Codes**: 0 for success, non-zero for failure

## Testing

### Windows Tests

Each PowerShell test validates:
- Script executes successfully
- Output is valid JSON
- Required fields are present

Run individual test:
```powershell
.\tests\windows\Test-CpuMonitor.ps1
```

Run all tests:
```powershell
.\tests\windows\Run-AllTests.ps1
```

### Unix Tests

Each Bash test validates:
- Exit code is 0
- Output is valid JSON (using jq or python if available)
- Required fields exist

Run individual test:
```bash
bash tests/unix/test_cpu_monitor.sh
```

Run all tests:
```bash
bash tests/unix/run_all_tests.sh
```

## Logging

All operations are logged to `data/logs/system.log` with timestamps:

```
[2025-12-02T15:20:00Z] [INFO] Starting system monitoring collection
[2025-12-02T15:20:01Z] [INFO] Running cpu_monitor.ps1
[2025-12-02T15:20:01Z] [INFO] cpu_monitor.ps1 completed successfully
...
```

## Optional Dependencies

### Unix/Linux

- **jq**: JSON processor (for test validation)
- **lm-sensors**: Temperature and fan monitoring
- **smartmontools**: Disk health monitoring
- **sysstat**: Enhanced CPU statistics

Install on Ubuntu/Debian:
```bash
sudo apt-get install jq lm-sensors smartmontools sysstat
```

Install on macOS:
```bash
brew install jq smartmontools sysstat
```

### Windows

- **PowerShell 5.1+**: Included with Windows 10/11
- **WMI**: Built-in (for temperature/fan monitoring)
- **Admin privileges**: Optional (for SMART data)

## Troubleshooting

### "Permission Denied" errors on Unix

Make scripts executable:
```bash
chmod +x scripts/*.sh scripts/monitors/unix/*.sh tests/unix/*.sh
```

Or run the install script:
```bash
bash scripts/install.sh
```

### Temperature/Fan data shows "unavailable"

- **Unix**: Install lm-sensors: `sudo apt-get install lm-sensors && sudo sensors-detect`
- **Windows**: Some systems don't expose WMI thermal data - this is normal

### SMART data shows "restricted"

- **Unix**: Run with sudo or add user to disk group
- **Windows**: Run PowerShell as Administrator

## License

This is a student project for educational purposes.

## Next Steps (Future Stages)

- Stage 2: Docker containerization
- Stage 3: Web dashboard
- Stage 4: Alerting and notifications
- Stage 5: Historical data and trends
