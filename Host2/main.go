package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/disk"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"github.com/shirou/gopsutil/v3/net"
)

const (
	PORT            = "8889"
	OUTPUT_FILE     = "go_latest.json"
	UPDATE_INTERVAL = 60 * time.Second
)

// SystemMetrics matches the existing JSON schema
type SystemMetrics struct {
	Timestamp   string          `json:"timestamp"`
	Platform    string          `json:"platform"`
	System      SystemInfo      `json:"system"`
	CPU         CPUInfo         `json:"cpu"`
	Memory      MemoryInfo      `json:"memory"`
	Disk        []DiskInfo      `json:"disk"`
	Network     []NetworkInfo   `json:"network"`
	Temperature TemperatureInfo `json:"temperature"`
	GPU         GPUInfo         `json:"gpu"`
	Source      string          `json:"source"`
}

type SystemInfo struct {
	OS            string `json:"os"`
	Hostname      string `json:"hostname"`
	UptimeSeconds uint64 `json:"uptime_seconds"`
	Kernel        string `json:"kernel"`
}

type CPUInfo struct {
	UsagePercent      float64 `json:"usage_percent"`
	LogicalProcessors int     `json:"logical_processors"`
	Load1             float64 `json:"load_1"`
	Load5             float64 `json:"load_5"`
	Load15            float64 `json:"load_15"`
	Vendor            string  `json:"vendor"`
	Model             string  `json:"model"`
	Status            string  `json:"status"`
}

type MemoryInfo struct {
	TotalMB      uint64  `json:"total_mb"`
	UsedMB       uint64  `json:"used_mb"`
	FreeMB       uint64  `json:"free_mb"`
	AvailableMB  uint64  `json:"available_mb"`
	UsagePercent float64 `json:"usage_percent"`
	Status       string  `json:"status"`
}

type DiskInfo struct {
	Device      string  `json:"device"`
	Filesystem  string  `json:"filesystem"`
	TotalGB     float64 `json:"total_gb"`
	UsedGB      float64 `json:"used_gb"`
	UsedPercent float64 `json:"used_percent"`
}

type NetworkInfo struct {
	Iface   string `json:"iface"`
	RxBytes uint64 `json:"rx_bytes"`
	TxBytes uint64 `json:"tx_bytes"`
}

type TemperatureInfo struct {
	CPUCelsius int    `json:"cpu_celsius"`
	CPUVendor  string `json:"cpu_vendor"`
	GPUCelsius int    `json:"gpu_celsius"`
	GPUVendor  string `json:"gpu_vendor"`
	Status     string `json:"status"`
}

type GPUInfo struct {
	Status  string      `json:"status"`
	Count   int         `json:"count"`
	Devices []GPUDevice `json:"devices"`
}

type GPUDevice struct {
	Vendor             string `json:"vendor"`
	Model              string `json:"model"`
	UtilizationPercent int    `json:"utilization_percent"`
	MemoryUsedMB       int    `json:"memory_used_mb"`
	MemoryTotalMB      int    `json:"memory_total_mb"`
	TemperatureCelsius int    `json:"temperature_celsius"`
	Status             string `json:"status"`
}

func collectMetrics() (*SystemMetrics, error) {
	metrics := &SystemMetrics{
		Timestamp: time.Now().UTC().Format("2006-01-02T15:04:05Z"),
		Platform:  runtime.GOOS,
		Source:    "native-go-agent",
	}

	// System Info
	hostInfo, err := host.Info()
	if err != nil {
		log.Printf("Error getting host info: %v", err)
	} else {
		metrics.System = SystemInfo{
			OS:            hostInfo.OS,
			Hostname:      hostInfo.Hostname,
			UptimeSeconds: hostInfo.Uptime,
			Kernel:        hostInfo.KernelVersion,
		}
	}

	// CPU Info
	cpuPercent, err := cpu.Percent(time.Second, false)
	if err != nil {
		log.Printf("Error getting CPU usage: %v", err)
	}

	cpuCount, _ := cpu.Counts(true)
	cpuInfoList, _ := cpu.Info()

	cpuUsage := 0.0
	if len(cpuPercent) > 0 {
		cpuUsage = cpuPercent[0]
	}

	vendor := ""
	model := ""
	if len(cpuInfoList) > 0 {
		vendor = cpuInfoList[0].VendorID
		model = cpuInfoList[0].ModelName
	}

	metrics.CPU = CPUInfo{
		UsagePercent:      cpuUsage,
		LogicalProcessors: cpuCount,
		Vendor:            vendor,
		Model:             model,
		Status:            "ok",
	}

	// Memory Info
	memInfo, err := mem.VirtualMemory()
	if err != nil {
		log.Printf("Error getting memory info: %v", err)
	} else {
		metrics.Memory = MemoryInfo{
			TotalMB:      memInfo.Total / 1024 / 1024,
			UsedMB:       memInfo.Used / 1024 / 1024,
			FreeMB:       memInfo.Free / 1024 / 1024,
			AvailableMB:  memInfo.Available / 1024 / 1024,
			UsagePercent: memInfo.UsedPercent,
			Status:       "ok",
		}
	}

	// Disk Info
	partitions, err := disk.Partitions(false)
	if err != nil {
		log.Printf("Error getting disk partitions: %v", err)
	} else {
		for _, partition := range partitions {
			usage, err := disk.Usage(partition.Mountpoint)
			if err != nil {
				continue
			}

			metrics.Disk = append(metrics.Disk, DiskInfo{
				Device:      partition.Mountpoint,
				Filesystem:  partition.Fstype,
				TotalGB:     float64(usage.Total) / 1024 / 1024 / 1024,
				UsedGB:      float64(usage.Used) / 1024 / 1024 / 1024,
				UsedPercent: usage.UsedPercent,
			})
		}
	}

	// Network Info
	netStats, err := net.IOCounters(true)
	if err != nil {
		log.Printf("Error getting network stats: %v", err)
	} else {
		for _, stat := range netStats {
			metrics.Network = append(metrics.Network, NetworkInfo{
				Iface:   stat.Name,
				RxBytes: stat.BytesRecv,
				TxBytes: stat.BytesSent,
			})
		}
	}

	// Temperature (multi-method collection)
	metrics.Temperature = collectTemperatureInfo(vendor)

	// GPU Info (using nvidia-smi if available)
	metrics.GPU = collectGPUInfo()

	return metrics, nil
}

// collectTemperatureInfo tries multiple methods to get CPU temperature
func collectTemperatureInfo(cpuVendor string) TemperatureInfo {
	tempInfo := TemperatureInfo{
		CPUCelsius: 0,
		CPUVendor:  cpuVendor,
		GPUCelsius: 0,
		GPUVendor:  "",
		Status:     "unavailable",
	}

	// Method 1: Try gopsutil sensors (works on Linux/macOS)
	if temp := getTempFromGopsutil(); temp > 0 {
		tempInfo.CPUCelsius = temp
		tempInfo.Status = "ok"
		return tempInfo
	}

	// Method 2: Try Windows WMI
	if runtime.GOOS == "windows" {
		if temp := getTempFromWMI(); temp > 0 {
			tempInfo.CPUCelsius = temp
			tempInfo.Status = "ok"
			return tempInfo
		}
	}

	// Method 3: Try external tools
	if temp := getTempFromExternalTools(); temp > 0 {
		tempInfo.CPUCelsius = temp
		tempInfo.Status = "ok"
		return tempInfo
	}

	return tempInfo
}

// getTempFromGopsutil uses gopsutil sensors (Linux/macOS)
func getTempFromGopsutil() int {
	// Note: gopsutil v3 doesn't have sensors package by default
	// This would require github.com/shirou/gopsutil/v3/sensors
	// For now, return 0 (not implemented)
	return 0
}

// getTempFromWMI queries Windows WMI for temperature - ENHANCED with multiple methods
func getTempFromWMI() int {
	if runtime.GOOS != "windows" {
		return 0
	}

	// METHOD 1: Try MSAcpi_ThermalZoneTemperature (most reliable)
	cmd := exec.Command("wmic", "/namespace:\\\\root\\wmi", "PATH", "MSAcpi_ThermalZoneTemperature", "GET", "CurrentTemperature")
	output, err := cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line == "" || strings.Contains(line, "CurrentTemperature") {
				continue
			}
			if temp, err := strconv.Atoi(line); err == nil {
				// WMI returns temperature in tenths of Kelvin
				// Convert to Celsius: (temp / 10) - 273.15
				celsius := (temp / 10) - 273
				if celsius > 0 && celsius < 150 {
					return celsius
				}
			}
		}
	}

	// METHOD 2: Try Win32_TemperatureProbe
	cmd = exec.Command("wmic", "path", "Win32_TemperatureProbe", "get", "CurrentReading")
	output, err = cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line == "" || strings.Contains(line, "CurrentReading") {
				continue
			}
			if temp, err := strconv.Atoi(line); err == nil {
				// Win32_TemperatureProbe returns in tenths of Kelvin
				celsius := (temp / 10) - 273
				if celsius > 0 && celsius < 150 {
					return celsius
				}
			}
		}
	}

	// METHOD 3: Try Win32_PerfFormattedData_Counters_ThermalZoneInformation
	cmd = exec.Command("wmic", "path", "Win32_PerfFormattedData_Counters_ThermalZoneInformation", "get", "Temperature")
	output, err = cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line == "" || strings.Contains(line, "Temperature") {
				continue
			}
			if temp, err := strconv.Atoi(line); err == nil {
				// This returns Kelvin directly
				celsius := temp - 273
				if celsius > 0 && celsius < 150 {
					return celsius
				}
			}
		}
	}

	// METHOD 4: Try PowerShell WMI query (more reliable on some systems)
	cmd = exec.Command("powershell", "-Command", "(Get-WmiObject -Namespace root/wmi -Class MSAcpi_ThermalZoneTemperature | Select-Object -First 1).CurrentTemperature")
	output, err = cmd.Output()
	if err == nil {
		line := strings.TrimSpace(string(output))
		if temp, err := strconv.Atoi(line); err == nil {
			celsius := (temp / 10) - 273
			if celsius > 0 && celsius < 150 {
				return celsius
			}
		}
	}

	// METHOD 5: Try CIM (newer Windows interface)
	cmd = exec.Command("powershell", "-Command", "(Get-CimInstance -ClassName CIM_TemperatureSensor | Select-Object -First 1).CurrentReading")
	output, err = cmd.Output()
	if err == nil {
		line := strings.TrimSpace(string(output))
		if temp, err := strconv.ParseFloat(line, 64); err == nil {
			celsius := int(temp)
			if celsius > 0 && celsius < 150 {
				return celsius
			}
		}
	}

	return 0
}

// getTempFromExternalTools tries platform-specific external tools
func getTempFromExternalTools() int {
	switch runtime.GOOS {
	case "linux":
		return getTempFromLinuxSensors()
	case "windows":
		return getTempFromWindowsTools()
	case "darwin":
		return getTempFromMacTools()
	default:
		return 0
	}
}

// getTempFromLinuxSensors uses lm-sensors on Linux - ENHANCED with multiple fallbacks
func getTempFromLinuxSensors() int {
	// METHOD 1: Try sensors command (lm-sensors package)
	cmd := exec.Command("sensors", "-u")
	output, err := cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			// Look for coretemp or k10temp (AMD/Intel)
			if strings.Contains(line, "_input:") && (strings.Contains(line, "temp") || strings.Contains(line, "Core")) {
				fields := strings.Fields(line)
				if len(fields) >= 2 {
					if temp, err := strconv.ParseFloat(fields[1], 64); err == nil {
						if temp > 0 && temp < 150 {
							return int(temp)
						}
					}
				}
			}
		}
	}

	// METHOD 2: Try /sys/class/hwmon (direct kernel interface)
	hwmonDirs, _ := filepath.Glob("/sys/class/hwmon/hwmon*")
	for _, hwmonDir := range hwmonDirs {
		// Read hwmon name to identify CPU sensors
		nameBytes, err := os.ReadFile(filepath.Join(hwmonDir, "name"))
		if err != nil {
			continue
		}
		name := strings.ToLower(strings.TrimSpace(string(nameBytes)))

		// Look for CPU-related sensors (coretemp, k10temp, zenpower)
		if strings.Contains(name, "coretemp") || strings.Contains(name, "k10temp") ||
			strings.Contains(name, "zenpower") || strings.Contains(name, "cpu") {
			// Find temperature input files
			tempFiles, _ := filepath.Glob(filepath.Join(hwmonDir, "temp*_input"))
			for _, tempFile := range tempFiles {
				tempBytes, err := os.ReadFile(tempFile)
				if err != nil {
					continue
				}
				if temp, err := strconv.Atoi(strings.TrimSpace(string(tempBytes))); err == nil {
					celsius := temp / 1000 // Convert from millidegrees
					if celsius > 0 && celsius < 150 {
						return celsius
					}
				}
			}
		}
	}

	// METHOD 3: Try /sys/class/thermal/thermal_zone* (thermal zones)
	thermalZones, _ := filepath.Glob("/sys/class/thermal/thermal_zone*/temp")
	for _, zoneTempFile := range thermalZones {
		tempBytes, err := os.ReadFile(zoneTempFile)
		if err != nil {
			continue
		}
		if temp, err := strconv.Atoi(strings.TrimSpace(string(tempBytes))); err == nil {
			celsius := temp / 1000
			if celsius > 0 && celsius < 150 {
				return celsius
			}
		}
	}

	// METHOD 4: Try acpi command (if available)
	cmd = exec.Command("acpi", "-t")
	output, err = cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.Contains(line, "ok,") {
				// Parse format: "Thermal 0: ok, 45.0 degrees C"
				parts := strings.Split(line, ",")
				if len(parts) >= 2 {
					tempStr := strings.TrimSpace(parts[1])
					tempStr = strings.Split(tempStr, " ")[0]
					if temp, err := strconv.ParseFloat(tempStr, 64); err == nil {
						if temp > 0 && temp < 150 {
							return int(temp)
						}
					}
				}
			}
		}
	}

	// METHOD 5: Try reading CPU package temperature directly
	packageTempFiles := []string{
		"/sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input", // Intel
		"/sys/devices/platform/k10temp.0/hwmon/hwmon*/temp1_input",  // AMD
	}
	for _, pattern := range packageTempFiles {
		matches, _ := filepath.Glob(pattern)
		for _, match := range matches {
			tempBytes, err := os.ReadFile(match)
			if err != nil {
				continue
			}
			if temp, err := strconv.Atoi(strings.TrimSpace(string(tempBytes))); err == nil {
				celsius := temp / 1000
				if celsius > 0 && celsius < 150 {
					return celsius
				}
			}
		}
	}

	return 0
}

// getTempFromWindowsTools tries Windows-specific tools
func getTempFromWindowsTools() int {
	// Try OpenHardwareMonitor CLI (if installed)
	cmd := exec.Command("OpenHardwareMonitorCLI.exe", "/cpu")
	output, err := cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.Contains(strings.ToLower(line), "temperature") {
				fields := strings.Fields(line)
				for _, field := range fields {
					if temp, err := strconv.ParseFloat(strings.TrimSuffix(field, "°C"), 64); err == nil {
						if temp > 0 && temp < 150 {
							return int(temp)
						}
					}
				}
			}
		}
	}

	return 0
}

// getTempFromMacTools tries macOS-specific tools
func getTempFromMacTools() int {
	// Try osx-cpu-temp (if installed via brew)
	cmd := exec.Command("osx-cpu-temp")
	output, err := cmd.Output()
	if err == nil {
		// Output format: "61.8°C"
		str := strings.TrimSpace(string(output))
		str = strings.TrimSuffix(str, "°C")
		if temp, err := strconv.ParseFloat(str, 64); err == nil {
			if temp > 0 && temp < 150 {
				return int(temp)
			}
		}
	}

	// Try smc command
	cmd = exec.Command("smc", "-k", "TC0P", "-r")
	output, err = cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.Contains(line, "bytes") {
				fields := strings.Fields(line)
				for _, field := range fields {
					if temp, err := strconv.ParseFloat(field, 64); err == nil {
						if temp > 0 && temp < 150 {
							return int(temp)
						}
					}
				}
			}
		}
	}

	return 0
}

func collectGPUInfo() GPUInfo {
	gpuInfo := GPUInfo{
		Status:  "unavailable",
		Count:   0,
		Devices: []GPUDevice{},
	}

	// 1. Try NVIDIA (nvidia-smi) - Best Data
	if nvidiaInfo := collectNvidiaInfo(); nvidiaInfo.Status == "ok" {
		return nvidiaInfo
	}

	// 2. Fallback: Windows Generic (WMI/CIM) - Essential Data (Name)
	if runtime.GOOS == "windows" {
		return collectWindowsGPUs()
	}

	return gpuInfo
}

func collectNvidiaInfo() GPUInfo {
	gpuInfo := GPUInfo{Status: "unavailable"}

	cmd := exec.Command("nvidia-smi", "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits")
	output, err := cmd.Output()
	if err != nil {
		return gpuInfo
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	for _, line := range lines {
		fields := strings.Split(line, ", ")
		if len(fields) >= 5 {
			var util, memUsed, memTotal, temp int
			fmt.Sscanf(fields[1], "%d", &util)
			fmt.Sscanf(fields[2], "%d", &memUsed)
			fmt.Sscanf(fields[3], "%d", &memTotal)
			fmt.Sscanf(fields[4], "%d", &temp)

			gpuInfo.Devices = append(gpuInfo.Devices, GPUDevice{
				Vendor:             "NVIDIA",
				Model:              fields[0],
				UtilizationPercent: util,
				MemoryUsedMB:       memUsed,
				MemoryTotalMB:      memTotal,
				TemperatureCelsius: temp,
				Status:             "ok",
			})
		}
	}

	if len(gpuInfo.Devices) > 0 {
		gpuInfo.Status = "ok"
		gpuInfo.Count = len(gpuInfo.Devices)
	}

	return gpuInfo
}

func collectWindowsGPUs() GPUInfo {
	gpuInfo := GPUInfo{Status: "unavailable"}

	// Use PowerShell to get clean JSON output for Video Controllers
	cmd := exec.Command("powershell", "-Command", "Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM | ConvertTo-Json -Compress")
	output, err := cmd.Output()
	if err != nil {
		return gpuInfo
	}

	// Define struct for parsing PowerShell JSON
	type WinVideoController struct {
		Name       string      `json:"Name"`
		AdapterRAM interface{} `json:"AdapterRAM"` // Can be float64 or int
	}

	var controllers []WinVideoController
	
	// Handle single object vs array return from PowerShell
	jsonStr := strings.TrimSpace(string(output))
	if strings.HasPrefix(jsonStr, "{") {
		var single WinVideoController
		if err := json.Unmarshal([]byte(jsonStr), &single); err == nil {
			controllers = append(controllers, single)
		}
	} else if strings.HasPrefix(jsonStr, "[") {
		json.Unmarshal([]byte(jsonStr), &controllers)
	}

	for _, card := range controllers {
		// Filter out basic display adapters if needed, but usually keep all
		vendor := "Unknown"
		nameLower := strings.ToLower(card.Name)
		if strings.Contains(nameLower, "nvidia") {
			vendor = "NVIDIA"
		} else if strings.Contains(nameLower, "amd") || strings.Contains(nameLower, "radeon") {
			vendor = "AMD"
		} else if strings.Contains(nameLower, "intel") {
			vendor = "Intel"
		}

		// Calculate RAM in MB
		ramMB := 0
		if card.AdapterRAM != nil {
			if val, ok := card.AdapterRAM.(float64); ok {
				ramMB = int(val / 1024 / 1024)
			}
		}

		// Attempt to get Temperature via Generic Tools
		// Note: Accurate GPU temp for AMD/Intel often requires complex API calls (ADL/IGCL)
		// We try to grab the generic CPU temp as a proxy or 0 if unknown.
		// A future improvement could try OpenHardwareMonitor specifically for this GPU.
		temp := 0 
		
		gpuInfo.Devices = append(gpuInfo.Devices, GPUDevice{
			Vendor:             vendor,
			Model:              card.Name,
			UtilizationPercent: 0, // Not easily available via WMI
			MemoryUsedMB:       0,
			MemoryTotalMB:      ramMB,
			TemperatureCelsius: temp,
			Status:             "ok",
		})
	}

	if len(gpuInfo.Devices) > 0 {
		gpuInfo.Status = "ok"
		gpuInfo.Count = len(gpuInfo.Devices)
	}

	return gpuInfo
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	metrics, err := collectMetrics()
	if err != nil {
		http.Error(w, fmt.Sprintf("Error collecting metrics: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	json.NewEncoder(w).Encode(metrics)
}

func refreshHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	metrics, err := collectMetrics()
	if err != nil {
		http.Error(w, fmt.Sprintf("Error collecting metrics: %v", err), http.StatusInternalServerError)
		return
	}

	// Force write to file
	if err := writeMetricsToFile(metrics); err != nil {
		log.Printf("[ERROR] Failed to write metrics to file during refresh: %v", err)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "success",
		"message":   "Native metrics refreshed and written to file",
		"timestamp": metrics.Timestamp,
	})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	response := map[string]string{
		"status":    "ok",
		"service":   "native-go-agent",
		"platform":  runtime.GOOS,
		"port":      PORT,
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func writeMetricsToFile(metrics *SystemMetrics) error {
	// Get the directory where the executable is located
	exePath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("failed to get executable path: %v", err)
	}
	exeDir := filepath.Dir(exePath)

	// Write to Host2/go_latest.json
	outputPath := filepath.Join(exeDir, OUTPUT_FILE)

	data, err := json.MarshalIndent(metrics, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal metrics: %v", err)
	}

	err = ioutil.WriteFile(outputPath, data, 0644)
	if err != nil {
		return fmt.Errorf("failed to write file: %v", err)
	}

	log.Printf("[FILE] Metrics written to %s", outputPath)
	return nil
}

func startPeriodicFileWriter() {
	ticker := time.NewTicker(UPDATE_INTERVAL)
	defer ticker.Stop()

	log.Printf("[FILE] Starting periodic file writer (interval: %v)", UPDATE_INTERVAL)

	// Write immediately on start
	metrics, err := collectMetrics()
	if err != nil {
		log.Printf("[FILE] Error collecting initial metrics: %v", err)
	} else {
		if err := writeMetricsToFile(metrics); err != nil {
			log.Printf("[FILE] Error writing initial metrics: %v", err)
		}
	}

	// Then write every 60 seconds
	for range ticker.C {
		metrics, err := collectMetrics()
		if err != nil {
			log.Printf("[FILE] Error collecting metrics: %v", err)
			continue
		}

		if err := writeMetricsToFile(metrics); err != nil {
			log.Printf("[FILE] Error writing metrics: %v", err)
		}
	}
}

func main() {
	http.HandleFunc("/metrics", metricsHandler)
	http.HandleFunc("/refresh", refreshHandler)
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		response := map[string]interface{}{
			"name":     "Native Go Host Agent",
			"version":  "1.0.0",
			"platform": runtime.GOOS,
			"endpoints": map[string]string{
				"/":        "This endpoint (API info)",
				"/health":  "Health check",
				"/metrics": "System metrics (native)",
			},
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(response)
	})

	fmt.Println("==========================================================")
	fmt.Println("  Native Go Host Agent - System Monitor")
	fmt.Println("==========================================================")
	fmt.Println()
	fmt.Printf("[*] Platform:  %s\n", runtime.GOOS)
	fmt.Printf("[*] Port:      %s\n", PORT)
	fmt.Println()
	fmt.Println("[*] Endpoints:")
	fmt.Printf("   - GET  http://localhost:%s/         (API Info)\n", PORT)
	fmt.Printf("   - GET  http://localhost:%s/health   (Health Check)\n", PORT)
	fmt.Printf("   - GET  http://localhost:%s/metrics  (System Metrics)\n", PORT)
	fmt.Println()
	fmt.Println("[*] Press Ctrl+C to stop")
	fmt.Println()
	fmt.Println("==========================================================")

	// Start background file writer
	go startPeriodicFileWriter()

	log.Fatal(http.ListenAndServe(":"+PORT, nil))
}
