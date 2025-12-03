# Quick Start Guide

## Windows

### Run Monitoring
```powershell
cd c:\Users\DELL\Desktop\wso\system-monitor-project
.\scripts\main_monitor.ps1
```

### View Results
```powershell
Get-Content data\metrics\current.json
```

### Run Tests
```powershell
.\tests\windows\Run-AllTests.ps1
```

## Unix/Linux/macOS

### Install
```bash
cd /path/to/system-monitor-project
bash scripts/install.sh
```

### Run Monitoring
```bash
bash scripts/main_monitor.sh
```

### View Results
```bash
cat data/metrics/current.json | jq .
```

### Run Tests
```bash
bash tests/unix/run_all_tests.sh
```

## Output Location

- **JSON Output:** `data/metrics/current.json`
- **Logs:** `data/logs/system.log`

## Collectors Included

1. **CPU** - Usage percentage and load averages
2. **Memory** - Total, used, free, available
3. **Disk** - Usage for all drives
4. **Network** - RX/TX bytes for all interfaces
5. **System** - OS, hostname, uptime, kernel
6. **Temperature** - CPU/GPU temps (if available)
7. **Fans** - Fan speeds (if available)
8. **SMART** - Disk health (if available)

## Status Fields

- `"status": "unavailable"` - Tool/sensor not available
- `"status": "restricted"` - Requires elevated privileges
- `"status": "error"` - Execution error
