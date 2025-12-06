<#
.SYNOPSIS
    Complete CPU Temperature Diagnostic - ALL KNOWN METHODS
    
.DESCRIPTION
    Tests EVERY known method to read CPU temperature on Windows:
    
    I. Operating System APIs (Windows-Exposed Data)
       1. WMI/CIM - MSAcpi_ThermalZoneTemperature
       2. WMI - Win32_TemperatureProbe
       3. PowerShell Performance Counters
    
    II. Generic Hardware Monitoring Libraries
       1. LibreHardwareMonitor
       2. OpenHardwareMonitor
    
    III. Direct Low-Level Hardware Access
       1. Direct MSR (Model-Specific Register) Reading
       2. SMBus/I2C Access (via WinRing0)
    
    IV. Manufacturer-Specific Access
       1. Intel XTU SDK (if available)
       2. AMD Ryzen Master (if available)
       3. Vendor-specific tools detection
    
.NOTES
    Author: System Monitor Project
    Version: 3.0.0 - Complete Edition
    Requires: Administrator privileges
    
.REQUIREMENTS
    - Run as Administrator
    - WinRing0x64.dll and WinRing0x64.sys in libs/drivers/
    - LibreHardwareMonitorLib.dll in libs/
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# =============================================================================
# CONFIGURATION
# =============================================================================

$global:Config = @{
    ProjectPath = "C:\Users\DELL\Desktop\system-monitor-project"
    LibsPath = "C:\Users\DELL\Desktop\system-monitor-project\libs"
    DriversPath = "C:\Users\DELL\Desktop\system-monitor-project\libs\drivers"
    Results = @{}
    StartTime = Get-Date
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

function Write-Header {
    Clear-Host
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "   COMPLETE CPU TEMPERATURE DIAGNOSTIC - ALL METHODS" -ForegroundColor Cyan
    Write-Host "   Testing Every Known Method to Read CPU Temperature" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Category, [string]$Method)
    Write-Host "`n┌─────────────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
    Write-Host "│ $Category" -ForegroundColor Cyan
    Write-Host "│ METHOD: $Method" -ForegroundColor Yellow
    Write-Host "└─────────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
}

function Write-Result {
    param(
        [string]$Message,
        [ValidateSet("SUCCESS", "FAIL", "WARN", "INFO", "TEMP", "DATA")]
        [string]$Type = "INFO"
    )
    
    $icon = switch ($Type) {
        "SUCCESS" { "✓"; $color = "Green" }
        "FAIL"    { "✗"; $color = "Red" }
        "WARN"    { "⚠"; $color = "Yellow" }
        "INFO"    { "ℹ"; $color = "White" }
        "TEMP"    { "🌡"; $color = "Cyan" }
        "DATA"    { "▶"; $color = "Gray" }
    }
    
    Write-Host "  [$icon] $Message" -ForegroundColor $color
}

function Save-MethodResult {
    param(
        [string]$MethodName,
        [string]$Status,
        [object]$Data = $null,
        [string]$ErrorMessage = $null
    )
    
    $global:Config.Results[$MethodName] = @{
        Status = $Status
        Data = $Data
        ErrorMessage = $ErrorMessage
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# =============================================================================
# CATEGORY I: OPERATING SYSTEM APIs
# =============================================================================

function Test-WMI-ThermalZone {
    Write-Section "CATEGORY I: OS APIs" "WMI - MSAcpi_ThermalZoneTemperature"
    
    try {
        $temps = Get-WmiObject -Namespace "root/wmi" -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        
        if ($temps) {
            $results = @()
            foreach ($temp in $temps) {
                $celsius = ($temp.CurrentTemperature / 10) - 273.15
                $rounded = [math]::Round($celsius, 1)
                
                $results += @{
                    Zone = $temp.InstanceName
                    Temperature = $rounded
                    Unit = "°C"
                }
                
                Write-Result "Zone: $($temp.InstanceName) = ${rounded}°C" "TEMP"
            }
            
            Save-MethodResult -MethodName "WMI_ThermalZone" -Status "Success" -Data $results
            Write-Result "Method: SUCCESS" "SUCCESS"
        } else {
            Write-Result "No thermal zones found" "WARN"
            Save-MethodResult -MethodName "WMI_ThermalZone" -Status "No Data"
        }
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "WMI_ThermalZone" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

function Test-WMI-TemperatureProbe {
    Write-Section "CATEGORY I: OS APIs" "WMI - Win32_TemperatureProbe"
    
    try {
        $probes = Get-WmiObject -Class Win32_TemperatureProbe -ErrorAction Stop
        
        if ($probes) {
            $results = @()
            foreach ($probe in $probes) {
                if ($probe.CurrentReading) {
                    $celsius = ($probe.CurrentReading / 10) - 273.15
                    $rounded = [math]::Round($celsius, 1)
                    
                    $results += @{
                        Name = $probe.Name
                        Description = $probe.Description
                        Temperature = $rounded
                    }
                    
                    Write-Result "$($probe.Name): ${rounded}°C" "TEMP"
                }
            }
            
            if ($results.Count -gt 0) {
                Save-MethodResult -MethodName "Win32_TemperatureProbe" -Status "Success" -Data $results
                Write-Result "Method: SUCCESS" "SUCCESS"
            } else {
                Write-Result "No valid temperature readings" "WARN"
                Save-MethodResult -MethodName "Win32_TemperatureProbe" -Status "No Data"
            }
        } else {
            Write-Result "No temperature probes found" "WARN"
            Save-MethodResult -MethodName "Win32_TemperatureProbe" -Status "No Data"
        }
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "Win32_TemperatureProbe" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

function Test-PerformanceCounters {
    Write-Section "CATEGORY I: OS APIs" "PowerShell Performance Counters"
    
    try {
        $thermalCounters = Get-Counter -ListSet "Thermal Zone Information" -ErrorAction Stop
        
        if ($thermalCounters) {
            Write-Result "Found thermal zone counters" "SUCCESS"
            
            $results = @()
            $counters = $thermalCounters.Counter | Where-Object { $_ -like "*Temperature*" }
            
            foreach ($counter in $counters) {
                try {
                    $value = (Get-Counter -Counter $counter -ErrorAction SilentlyContinue).CounterSamples.CookedValue
                    if ($value) {
                        # Performance counter temps are in tenths of Kelvin
                        $celsius = ($value / 10) - 273.15
                        $rounded = [math]::Round($celsius, 1)
                        
                        $results += @{
                            Counter = $counter
                            Temperature = $rounded
                        }
                        
                        Write-Result "Counter: $($rounded)°C" "TEMP"
                    }
                } catch {
                    # Skip inaccessible counters
                }
            }
            
            if ($results.Count -gt 0) {
                Save-MethodResult -MethodName "PerformanceCounters" -Status "Success" -Data $results
                Write-Result "Method: SUCCESS" "SUCCESS"
            } else {
                Save-MethodResult -MethodName "PerformanceCounters" -Status "No Data"
            }
        } else {
            Write-Result "No thermal zone counters available" "WARN"
            Save-MethodResult -MethodName "PerformanceCounters" -Status "Not Available"
        }
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "PerformanceCounters" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

function Test-CIM-ThermalZone {
    Write-Section "CATEGORY I: OS APIs" "CIM - MSAcpi_ThermalZoneTemperature"
    
    try {
        $temps = Get-CimInstance -Namespace "root/wmi" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        
        if ($temps) {
            $results = @()
            foreach ($temp in $temps) {
                $celsius = ($temp.CurrentTemperature / 10) - 273.15
                $rounded = [math]::Round($celsius, 1)
                
                $results += @{
                    Zone = $temp.InstanceName
                    Temperature = $rounded
                }
                
                Write-Result "Zone: $($temp.InstanceName) = ${rounded}°C" "TEMP"
            }
            
            Save-MethodResult -MethodName "CIM_ThermalZone" -Status "Success" -Data $results
            Write-Result "Method: SUCCESS" "SUCCESS"
        } else {
            Write-Result "No CIM thermal zones found" "WARN"
            Save-MethodResult -MethodName "CIM_ThermalZone" -Status "No Data"
        }
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "CIM_ThermalZone" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

# =============================================================================
# CATEGORY II: HARDWARE MONITORING LIBRARIES
# =============================================================================

function Test-LibreHardwareMonitor {
    Write-Section "CATEGORY II: Hardware Libraries" "LibreHardwareMonitor"
    
    try {
        $dllPath = Join-Path $global:Config.LibsPath "LibreHardwareMonitorLib.dll"
        
        if (-not (Test-Path $dllPath)) {
            Write-Result "LibreHardwareMonitorLib.dll not found" "FAIL"
            Save-MethodResult -MethodName "LibreHardwareMonitor" -Status "Not Available"
            return
        }
        
        Add-Type -Path $dllPath -ErrorAction Stop
        
        $computer = New-Object LibreHardwareMonitor.Hardware.Computer
        $computer.IsCpuEnabled = $true
        $computer.IsMotherboardEnabled = $true
        $computer.Open()
        
        $cpuTemps = @()
        
        foreach ($hardware in $computer.Hardware) {
            $hardware.Update()
            
            Write-Result "Hardware: $($hardware.Name) [$($hardware.HardwareType)]" "DATA"
            
            foreach ($sensor in $hardware.Sensors) {
                if ($sensor.SensorType -eq [LibreHardwareMonitor.Hardware.SensorType]::Temperature) {
                    if ($sensor.Value) {
                        $cpuTemps += @{
                            Hardware = $hardware.Name
                            Sensor = $sensor.Name
                            Temperature = [math]::Round($sensor.Value, 1)
                        }
                        Write-Result "$($sensor.Name): $([math]::Round($sensor.Value, 1))°C" "TEMP"
                    } else {
                        Write-Result "$($sensor.Name): No value (NULL)" "WARN"
                    }
                }
            }
            
            foreach ($subhardware in $hardware.SubHardware) {
                $subhardware.Update()
                foreach ($sensor in $subhardware.Sensors) {
                    if ($sensor.SensorType -eq [LibreHardwareMonitor.Hardware.SensorType]::Temperature) {
                        if ($sensor.Value) {
                            $cpuTemps += @{
                                Hardware = "$($hardware.Name) - $($subhardware.Name)"
                                Sensor = $sensor.Name
                                Temperature = [math]::Round($sensor.Value, 1)
                            }
                            Write-Result "$($sensor.Name): $([math]::Round($sensor.Value, 1))°C" "TEMP"
                        }
                    }
                }
            }
        }
        
        $computer.Close()
        
        if ($cpuTemps.Count -gt 0) {
            Save-MethodResult -MethodName "LibreHardwareMonitor" -Status "Success" -Data $cpuTemps
            Write-Result "Method: SUCCESS - Found $($cpuTemps.Count) sensor(s)" "SUCCESS"
        } else {
            Write-Result "No CPU temperatures detected (sensors exist but values are NULL)" "WARN"
            Save-MethodResult -MethodName "LibreHardwareMonitor" -Status "No Data"
        }
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "LibreHardwareMonitor" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

function Test-OpenHardwareMonitor {
    Write-Section "CATEGORY II: Hardware Libraries" "OpenHardwareMonitor"
    
    try {
        $dllPath = Join-Path $global:Config.LibsPath "OpenHardwareMonitorLib.dll"
        
        if (-not (Test-Path $dllPath)) {
            Write-Result "OpenHardwareMonitorLib.dll not found" "WARN"
            Save-MethodResult -MethodName "OpenHardwareMonitor" -Status "Not Available"
            return
        }
        
        Add-Type -Path $dllPath -ErrorAction Stop
        
        $computer = New-Object OpenHardwareMonitor.Hardware.Computer
        $computer.CPUEnabled = $true
        $computer.MainboardEnabled = $true
        $computer.Open()
        
        $cpuTemps = @()
        
        foreach ($hardware in $computer.Hardware) {
            $hardware.Update()
            
            if ($hardware.HardwareType -eq [OpenHardwareMonitor.Hardware.HardwareType]::CPU) {
                Write-Result "CPU: $($hardware.Name)" "DATA"
                
                foreach ($sensor in $hardware.Sensors) {
                    if ($sensor.SensorType -eq [OpenHardwareMonitor.Hardware.SensorType]::Temperature) {
                        if ($sensor.Value) {
                            $cpuTemps += @{
                                Sensor = $sensor.Name
                                Temperature = [math]::Round($sensor.Value, 1)
                            }
                            Write-Result "$($sensor.Name): $([math]::Round($sensor.Value, 1))°C" "TEMP"
                        }
                    }
                }
            }
        }
        
        $computer.Close()
        
        if ($cpuTemps.Count -gt 0) {
            Save-MethodResult -MethodName "OpenHardwareMonitor" -Status "Success" -Data $cpuTemps
            Write-Result "Method: SUCCESS" "SUCCESS"
        } else {
            Save-MethodResult -MethodName "OpenHardwareMonitor" -Status "No Data"
        }
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "OpenHardwareMonitor" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

# =============================================================================
# CATEGORY III: DIRECT LOW-LEVEL HARDWARE ACCESS
# =============================================================================

function Test-DirectMSR {
    Write-Section "CATEGORY III: Low-Level Hardware" "Direct MSR (Model-Specific Register) Reading"
    
    $msrCode = @"
using System;
using System.Runtime.InteropServices;

public class IntelMSR
{
    [DllImport("WinRing0x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern bool InitializeOls();
    
    [DllImport("WinRing0x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void DeinitializeOls();
    
    [DllImport("WinRing0x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern bool Rdmsr(uint index, ref uint eax, ref uint edx);
    
    [DllImport("WinRing0x64.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern bool RdmsrTx(uint index, ref uint eax, ref uint edx, UIntPtr threadAffinityMask);
    
    private const uint MSR_IA32_THERM_STATUS = 0x19C;
    private const uint MSR_IA32_TEMPERATURE_TARGET = 0x1A2;
    
    public static int GetTjMax()
    {
        uint eax = 0, edx = 0;
        if (Rdmsr(MSR_IA32_TEMPERATURE_TARGET, ref eax, ref edx))
        {
            return (int)((eax >> 16) & 0xFF);
        }
        return 100;
    }
    
    public static int[] GetCoreTemperatures(int coreCount)
    {
        int tjMax = GetTjMax();
        int[] temps = new int[coreCount];
        
        for (int i = 0; i < coreCount; i++)
        {
            uint eax = 0, edx = 0;
            UIntPtr affinityMask = new UIntPtr((ulong)(1 << i));
            
            if (RdmsrTx(MSR_IA32_THERM_STATUS, ref eax, ref edx, affinityMask))
            {
                int digitalReadout = (int)((eax >> 16) & 0x7F);
                temps[i] = tjMax - digitalReadout;
            }
            else
            {
                temps[i] = -1;
            }
        }
        
        return temps;
    }
}
"@

    try {
        $winRingDll = Join-Path $global:Config.DriversPath "WinRing0x64.dll"
        $winRingSys = Join-Path $global:Config.DriversPath "WinRing0x64.sys"
        
        if (-not (Test-Path $winRingDll) -or -not (Test-Path $winRingSys)) {
            Write-Result "WinRing0 driver files not found" "FAIL"
            Write-Result "Required: WinRing0x64.dll and WinRing0x64.sys" "INFO"
            Save-MethodResult -MethodName "DirectMSR" -Status "Driver Not Found"
            return
        }
        
        # Add DLL directory to PATH
        $env:PATH = "$($global:Config.DriversPath);$env:PATH"
        
        Add-Type -TypeDefinition $msrCode -ErrorAction Stop
        
        if ([IntelMSR]::InitializeOls()) {
            Write-Result "WinRing0 initialized successfully" "SUCCESS"
            
            $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
            $coreCount = $cpu.NumberOfCores
            
            $tjMax = [IntelMSR]::GetTjMax()
            Write-Result "TjMax (Thermal Junction Maximum): ${tjMax}°C" "INFO"
            
            $temps = [IntelMSR]::GetCoreTemperatures($coreCount)
            
            $results = @()
            $validCount = 0
            
            for ($i = 0; $i -lt $temps.Length; $i++) {
                if ($temps[$i] -gt 0 -and $temps[$i] -lt 150) {
                    $results += @{
                        Core = $i
                        Temperature = $temps[$i]
                    }
                    Write-Result "Core ${i}: $($temps[$i])°C" "TEMP"
                    $validCount++
                } else {
                    Write-Result "Core ${i}: Failed to read" "WARN"
                }
            }
            
            [IntelMSR]::DeinitializeOls()
            
            if ($validCount -gt 0) {
                Save-MethodResult -MethodName "DirectMSR" -Status "Success" -Data $results
                Write-Result "Method: SUCCESS - Read $validCount core(s)" "SUCCESS"
            } else {
                Save-MethodResult -MethodName "DirectMSR" -Status "No Valid Data"
            }
        } else {
            Write-Result "Failed to initialize WinRing0" "FAIL"
            Save-MethodResult -MethodName "DirectMSR" -Status "Initialization Failed"
        }
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "DirectMSR" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

function Test-SMBus {
    Write-Section "CATEGORY III: Low-Level Hardware" "SMBus/I2C Hardware Monitoring Chip Access"
    
    Write-Result "SMBus/I2C method requires specific chip identification" "INFO"
    Write-Result "Common chips: IT8728F, NCT6791D, W83627DHG" "INFO"
    
    try {
        $winRingDll = Join-Path $global:Config.DriversPath "WinRing0x64.dll"
        
        if (-not (Test-Path $winRingDll)) {
            Write-Result "WinRing0 driver not available" "FAIL"
            Save-MethodResult -MethodName "SMBus" -Status "Driver Not Found"
            return
        }
        
        Write-Result "SMBus access requires chip-specific implementation" "WARN"
        Write-Result "This is typically handled by hardware monitoring libraries" "INFO"
        Save-MethodResult -MethodName "SMBus" -Status "Not Implemented"
        
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "SMBus" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

# =============================================================================
# CATEGORY IV: MANUFACTURER-SPECIFIC ACCESS
# =============================================================================

function Test-IntelXTU {
    Write-Section "CATEGORY IV: Manufacturer Tools" "Intel Extreme Tuning Utility (XTU) SDK"
    
    try {
        $xtuPath = "${env:ProgramFiles}\Intel\Intel(R) Extreme Tuning Utility"
        
        if (Test-Path $xtuPath) {
            Write-Result "Intel XTU installation detected" "SUCCESS"
            Write-Result "Path: $xtuPath" "INFO"
            
            # Check if SDK is available
            $sdkPath = Join-Path $xtuPath "SDK"
            if (Test-Path $sdkPath) {
                Write-Result "XTU SDK found" "SUCCESS"
                Write-Result "SDK would require specific Intel API implementation" "INFO"
                Save-MethodResult -MethodName "IntelXTU" -Status "Available (Not Implemented)"
            } else {
                Write-Result "XTU SDK not found" "WARN"
                Save-MethodResult -MethodName "IntelXTU" -Status "No SDK"
            }
        } else {
            Write-Result "Intel XTU not installed" "INFO"
            Save-MethodResult -MethodName "IntelXTU" -Status "Not Installed"
        }
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "IntelXTU" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

function Test-AMDRyzenMaster {
    Write-Section "CATEGORY IV: Manufacturer Tools" "AMD Ryzen Master"
    
    try {
        $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
        
        if ($cpu.Manufacturer -notmatch "AMD") {
            Write-Result "Not an AMD CPU - Skipping" "INFO"
            Save-MethodResult -MethodName "AMDRyzenMaster" -Status "Not Applicable"
            return
        }
        
        $ryzenPath = "${env:ProgramFiles}\AMD\RyzenMaster"
        
        if (Test-Path $ryzenPath) {
            Write-Result "AMD Ryzen Master detected" "SUCCESS"
            Write-Result "Path: $ryzenPath" "INFO"
            Write-Result "Would require AMD-specific API implementation" "INFO"
            Save-MethodResult -MethodName "AMDRyzenMaster" -Status "Available (Not Implemented)"
        } else {
            Write-Result "AMD Ryzen Master not installed" "INFO"
            Save-MethodResult -MethodName "AMDRyzenMaster" -Status "Not Installed"
        }
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "AMDRyzenMaster" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

function Test-VendorTools {
    Write-Section "CATEGORY IV: Manufacturer Tools" "Vendor-Specific Monitoring Tools"
    
    try {
        $vendors = @{
            "Dell" = @(
                "${env:ProgramFiles}\Dell\CommandUpdate",
                "${env:ProgramFiles(x86)}\Dell\CommandUpdate"
            )
            "HP" = @(
                "${env:ProgramFiles}\HP\HP Support Framework",
                "${env:ProgramFiles(x86)}\Hewlett-Packard\HP Support Framework"
            )
            "Lenovo" = @(
                "${env:ProgramFiles}\Lenovo\System Update",
                "${env:ProgramFiles(x86)}\Lenovo\System Update"
            )
            "ASUS" = @(
                "${env:ProgramFiles}\ASUS\ASUS System Control Interface",
                "${env:ProgramFiles(x86)}\ASUS"
            )
        }
        
        $foundVendors = @()
        
        foreach ($vendor in $vendors.Keys) {
            foreach ($path in $vendors[$vendor]) {
                if (Test-Path $path) {
                    Write-Result "$vendor tools detected: $path" "SUCCESS"
                    $foundVendors += $vendor
                    break
                }
            }
        }
        
        if ($foundVendors.Count -gt 0) {
            Save-MethodResult -MethodName "VendorTools" -Status "Found" -Data $foundVendors
            Write-Result "Method: Detected $($foundVendors.Count) vendor tool(s)" "SUCCESS"
        } else {
            Write-Result "No vendor-specific tools detected" "INFO"
            Save-MethodResult -MethodName "VendorTools" -Status "None Found"
        }
    } catch {
        Write-Result "FAILED: $($_.Exception.Message)" "FAIL"
        Save-MethodResult -MethodName "VendorTools" -Status "Error" -ErrorMessage $_.Exception.Message
    }
}

# =============================================================================
# SYSTEM INFORMATION
# =============================================================================

function Get-SystemInformation {
    Write-Section "SYSTEM INFORMATION" "Hardware Details"
    
    try {
        $cpu = Get-WmiObject Win32_Processor | Select-Object -First 1
        $os = Get-WmiObject Win32_OperatingSystem
        $bios = Get-WmiObject Win32_BIOS
        $board = Get-WmiObject Win32_BaseBoard
        
        Write-Result "CPU: $($cpu.Name)" "INFO"
        Write-Result "Manufacturer: $($cpu.Manufacturer)" "INFO"
        Write-Result "Cores: $($cpu.NumberOfCores) | Logical: $($cpu.NumberOfLogicalProcessors)" "INFO"
        Write-Result "Max Clock: $($cpu.MaxClockSpeed) MHz" "INFO"
        Write-Result "Current Clock: $($cpu.CurrentClockSpeed) MHz" "INFO"
        Write-Result "" "INFO"
        Write-Result "OS: $($os.Caption) $($os.Version)" "INFO"
        Write-Result "Architecture: $($os.OSArchitecture)" "INFO"
        Write-Result "" "INFO"
        Write-Result "BIOS: $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)" "INFO"
        Write-Result "Motherboard: $($board.Manufacturer) $($board.Product)" "INFO"
        
        $global:Config.Results["SystemInfo"] = @{
            CPU = $cpu.Name
            Manufacturer = $cpu.Manufacturer
            Cores = $cpu.NumberOfCores
            LogicalProcessors = $cpu.NumberOfLogicalProcessors
            OS = $os.Caption
            BIOS = "$($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)"
            Motherboard = "$($board.Manufacturer) $($board.Product)"
        }
    } catch {
        Write-Result "Failed to get system info: $($_.Exception.Message)" "FAIL"
    }
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

Write-Header
Get-SystemInformation

# Category I: Operating System APIs
Test-WMI-ThermalZone
Test-WMI-TemperatureProbe
Test-PerformanceCounters
Test-CIM-ThermalZone

# Category II: Hardware Monitoring Libraries
Test-LibreHardwareMonitor
Test-OpenHardwareMonitor

# Category III: Direct Low-Level Access
Test-DirectMSR
Test-SMBus

# Category IV: Manufacturer-Specific
Test-IntelXTU
Test-AMDRyzenMaster
Test-VendorTools
# =============================================================================
# SUMMARY OF RESULTS
# =============================================================================
Write-Section "DIAGNOSTIC SUMMARY" "All Methods Overview"
foreach ($method in $global:Config.Results.Keys) {
    $result = $global:Config.Results[$method]
    $status = $result.Status
    $timestamp = $result.Timestamp
    
    switch ($status) {
        "Success" { $type = "SUCCESS" }
        "Error"   { $type = "FAIL" }
        "Warn"    { $type = "WARN" }
        default   { $type = "INFO" }
    }
    
    Write-Result "$method - Status: $status (Timestamp: $timestamp)" $type
}
Write-Host "`nDiagnostic completed at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")" -ForegroundColor Cyan
# Save results to JSON file
$resultsPath = Join-Path $global:Config.ProjectPath "CPU_Temperature_D
iagnostic_Results.json"
$global:Config.Results | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultsPath -Encoding UTF8
Write-Host "Results saved to: $resultsPath" -ForegroundColor Cyan

# =============================================================================
# END OF SCRIPT
# =============================================================================
Write-Host "Complete!" -ForegroundColor Green
Write-Host "Diagnostic completed at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")" -ForegroundColor Cyan
# Save results to JSON file
$resultsPath = Join-Path $global:Config.ProjectPath "CPU_Temperature_Diagnostic_Results.json"
$global:Config.Results | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultsPath -Encoding UTF8
Write-Host "Results saved to: $resultsPath" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
# =============================================================================
# END OF SCRIPT
# =============================================================================
Write-Host "Complete!" -ForegroundColor Green
Write-Host "Diagnostic completed at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")" -ForegroundColor Cyan
# Save results to JSON file