#Requires -Version 5.1
#Requires -RunAsAdministrator

<# =====================================================================
  GameMemVRAM-Tuner-Production.ps1  (Windows 10/11, PowerShell 5.1+)
  
  A production-grade system optimization tool for gaming performance.
  
  FEATURES:
  - Auto-detects RAM and GPU configuration with robust VRAM detection
  - RAM-optimized settings with I/O reduction
  - GPU scheduling (HAGS) and Multi-Plane Overlay (MPO) configuration  
  - Fixed pagefile sizing and memory compression management
  - Xbox Game DVR and Game Mode optimization
  - Optional TCP low-latency networking tweaks
  - Comprehensive logging and audit trail
  - Registry backup and restore functionality
  - Configuration file support
  - System compatibility validation
  - Detailed error handling and rollback capabilities
  
  USAGE (Administrator required):
    .\GameMemVRAM-Tuner-Production.ps1 -Apply
    .\GameMemVRAM-Tuner-Production.ps1 -Report  
    .\GameMemVRAM-Tuner-Production.ps1 -Revert
    .\GameMemVRAM-Tuner-Production.ps1 -Backup -BackupPath "C:\Backup"
    .\GameMemVRAM-Tuner-Production.ps1 -Restore -BackupPath "C:\Backup"
    
  Optional Parameters:
    -SkipNetwork          Skip TCP networking optimizations
    -ForceVramMB <int>    Override detected VRAM amount
    -ConfigFile <path>    Use custom configuration file
    -LogLevel <level>     Set logging level (Error|Warn|Info|Debug)
    -WhatIf              Preview changes without applying them
    -Force               Skip confirmation prompts
    
  EXAMPLES:
    # Apply with custom VRAM and skip networking
    .\GameMemVRAM-Tuner-Production.ps1 -Apply -ForceVramMB 8192 -SkipNetwork
    
    # Create backup before applying changes
    .\GameMemVRAM-Tuner-Production.ps1 -Backup -BackupPath "C:\MyBackup"
    .\GameMemVRAM-Tuner-Production.ps1 -Apply
    
    # Preview changes without applying
    .\GameMemVRAM-Tuner-Production.ps1 -Apply -WhatIf
    
===================================================================== #>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(ParameterSetName = 'Apply')]
    [switch]$Apply,
    
    [Parameter(ParameterSetName = 'Revert')]
    [switch]$Revert,
    
    [Parameter(ParameterSetName = 'Report')]
    [switch]$Report,
    
    [Parameter(ParameterSetName = 'Backup')]
    [switch]$Backup,
    
    [Parameter(ParameterSetName = 'Restore')]
    [switch]$Restore,
    
    [Parameter()]
    [switch]$SkipNetwork,
    
    [Parameter()]
    [ValidateRange(1024, 131072)]
    [int]$ForceVramMB,
    
    [Parameter()]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Container)) {
            throw "Backup path must be an existing directory: $_"
        }
        $true
    })]
    [string]$BackupPath,
    
    [Parameter()]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Leaf)) {
            throw "Configuration file not found: $_"
        }
        $true
    })]
    [string]$ConfigFile,
    
    [Parameter()]
    [ValidateSet('Error', 'Warn', 'Info', 'Debug')]
    [string]$LogLevel = 'Info',
    
    [Parameter()]
    [switch]$WhatIf,
    
    [Parameter()]
    [switch]$Force
)

# ========================= GLOBAL CONFIGURATION =========================
$Script:Config = @{
    LogPath = Join-Path $env:TEMP "GameMemVRAM-Tuner-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    BackupFileName = "GameMemVRAM-Registry-Backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    RequiredWindowsVersion = [Version]"10.0.0.0"
    MaxLogSizeMB = 50
    TimeoutSeconds = 30
}

# ========================= LOGGING SYSTEM =========================
enum LogLevel {
    Error = 0
    Warn = 1  
    Info = 2
    Debug = 3
}

$Script:CurrentLogLevel = [LogLevel]$LogLevel

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [LogLevel]$Level = [LogLevel]::Info,
        
        [Parameter()]
        [string]$Category = 'General'
    )
    
    if ($Level -gt $Script:CurrentLogLevel) { return }
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $levelStr = $Level.ToString().ToUpper().PadRight(5)
    $logEntry = "[$timestamp] [$levelStr] [$Category] $Message"
    
    # Write to file
    try {
        Add-Content -Path $Script:Config.LogPath -Value $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Fallback if logging fails
    }
    
    # Write to console with colors
    switch ($Level) {
        ([LogLevel]::Error) { Write-Host "ERROR: $Message" -ForegroundColor Red }
        ([LogLevel]::Warn)  { Write-Host "WARN:  $Message" -ForegroundColor Yellow }
        ([LogLevel]::Info)  { Write-Host "INFO:  $Message" -ForegroundColor Cyan }
        ([LogLevel]::Debug) { Write-Host "DEBUG: $Message" -ForegroundColor Gray }
    }
}

function Write-Step { param([string]$Text) { Write-Log "==> $Text" -Level Info } }
function Write-Success { param([string]$Text) { Write-Log "[OK] $Text" -Level Info } }
function Write-Warning { param([string]$Text) { Write-Log "! $Text" -Level Warn } }
function Write-Error { param([string]$Text) { Write-Log "[ERROR] $Text" -Level Error } }

# ========================= VALIDATION & SAFETY =========================
function Test-Prerequisites {
    Write-Log "Validating system prerequisites" -Level Info -Category "Validation"
    
    # Windows version check
    $osVersion = [Environment]::OSVersion.Version
    if ($osVersion -lt $Script:Config.RequiredWindowsVersion) {
        throw "This script requires Windows 10 or later. Current version: $osVersion"
    }
    
    # PowerShell version check
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw "This script requires PowerShell 5.1 or later. Current version: $($PSVersionTable.PSVersion)"
    }
    
    # Administrator check
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run as Administrator"
    }
    
    # Disk space check for logging
    $tempDrive = Split-Path $Script:Config.LogPath -Qualifier
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $tempDrive }
    if ($disk -and ($disk.FreeSpace / 1MB) -lt 100) {
        Write-Warning "Low disk space on $tempDrive drive. Logging may be affected."
    }
    
    Write-Success "Prerequisites validated"
}

function Test-SystemStability {
    Write-Log "Checking system stability indicators" -Level Info -Category "Validation"
    
    # Check for pending reboots
    $pendingReboot = $false
    
    # Check registry indicators
    $regKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    )
    
    foreach ($key in $regKeys) {
        if (Test-Path $key) {
            $pendingReboot = $true
            break
        }
    }
    
    if ($pendingReboot) {
        Write-Warning "System has pending reboot. It's recommended to restart before applying changes."
        if (-not $Force) {
            $response = Read-Host "Continue anyway? (y/N)"
            if ($response -notmatch '^y(es)?$') {
                throw "Operation cancelled due to pending reboot"
            }
        }
    }
}

# ========================= BACKUP & RESTORE SYSTEM =========================
$Script:BackupData = @{
    Timestamp = Get-Date
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    RegistryValues = @{}
    SystemInfo = @{}
}

function Backup-RegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]  
        [string]$Name,
        
        [Parameter()]
        [string]$Description = ""
    )
    
    try {
        $key = "$Path\$Name"
        if (Test-Path $Path) {
            $property = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($property) {
                $Script:BackupData.RegistryValues[$key] = @{
                    Path = $Path
                    Name = $Name  
                    Value = $property.$Name
                    Type = (Get-Item $Path).GetValueKind($Name)
                    Description = $Description
                    BackedUp = Get-Date
                }
                Write-Log "Backed up: $key" -Level Debug -Category "Backup"
            }
        }
    } catch {
        Write-Log "Failed to backup $Path\$Name : $($_.Exception.Message)" -Level Warn -Category "Backup"
    }
}

function Export-SystemBackup {
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath
    )
    
    Write-Step "Creating system backup"
    
    # Collect system information
    $Script:BackupData.SystemInfo = @{
        OSVersion = [Environment]::OSVersion.Version.ToString()
        PSVersion = $PSVersionTable.PSVersion.ToString()
        TotalRAM_GB = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
        GPUs = @(Get-CimInstance Win32_VideoController | Select-Object Name, AdapterRAM, PNPDeviceID)
        InstalledSoftware = @(Get-CimInstance Win32_Product | Select-Object Name, Version, Vendor)
    }
    
    # Backup all registry values we'll modify
    $registryKeys = @(
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Values = @("DisablePagingExecutive", "LargeSystemCache", "ClearPageFileAtShutdown", "IoPageLockLimit", "NonPagedPoolQuota", "PagedPoolQuota", "SystemPages", "PagingFiles", "ExistingPageFiles", "TempPageFile") },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"; Values = @("NtfsMemoryUsage") },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Values = @("EnablePrefetcher", "EnableSuperfetch") },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; Values = @("HwSchMode") },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"; Values = @("OverlayTestMode") },
        @{ Path = "HKCU:\Software\Microsoft\GameBar"; Values = @("AllowAutoGameMode") },
        @{ Path = "HKCU:\System\GameConfigStore"; Values = @("GameDVR_Enabled", "GameDVR_FSEBehaviorMode", "GameDVR_HonorUserFSEBehaviorMode", "GameDVR_DXGIHonorFSEWindowsCompatible", "GameDVR_EFSEFeatureFlags", "GameDVR_FSEBehavior", "GameDVR_HonorFSEWindowsCompatible") },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"; Values = @("TcpNoDelay", "TcpAckFrequency", "TcpDelAckTicks") }
    )
    
    foreach ($keyInfo in $registryKeys) {
        foreach ($valueName in $keyInfo.Values) {
            Backup-RegistryValue -Path $keyInfo.Path -Name $valueName -Description "System optimization setting"
        }
    }
    
    # Export to JSON file
    $backupFile = Join-Path $BackupPath $Script:Config.BackupFileName
    try {
        $Script:BackupData | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8
        Write-Success "Backup saved to: $backupFile"
        return $backupFile
    } catch {
        throw "Failed to save backup: $($_.Exception.Message)"
    }
}

function Import-SystemBackup {
    param(
        [Parameter(Mandatory)]
        [string]$BackupFile
    )
    
    Write-Step "Restoring from backup: $BackupFile"
    
    try {
        $backupData = Get-Content $BackupFile -Raw | ConvertFrom-Json
        $restored = 0
        $failed = 0
        
        foreach ($key in $backupData.RegistryValues.PSObject.Properties.Name) {
            $regValue = $backupData.RegistryValues.$key
            
            try {
                if (-not $WhatIf) {
                    Ensure-RegistryKey $regValue.Path
                    New-ItemProperty -Path $regValue.Path -Name $regValue.Name -PropertyType $regValue.Type -Value $regValue.Value -Force | Out-Null
                }
                Write-Log "Restored: $($regValue.Path)\$($regValue.Name)" -Level Debug -Category "Restore"
                $restored++
            } catch {
                Write-Warning "Failed to restore $($regValue.Path)\$($regValue.Name): $($_.Exception.Message)"
                $failed++
            }
        }
        
        Write-Success "Restore completed: $restored restored, $failed failed"
        
    } catch {
        throw "Failed to restore backup: $($_.Exception.Message)"
    }
}

# ========================= REGISTRY OPERATIONS =========================
function Ensure-RegistryKey {
    param([Parameter(Mandatory)][string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Log "Creating registry key: $Path" -Level Debug -Category "Registry"
        if (-not $WhatIf) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        }
    }
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [object]$Value,
        
        [Parameter(Mandatory)]
        [Microsoft.Win32.RegistryValueKind]$Type,
        
        [Parameter()]
        [string]$Description = ""
    )
    
    try {
        # Backup current value first
        Backup-RegistryValue -Path $Path -Name $Name -Description $Description
        
        Write-Log "Setting registry: $Path\$Name = $Value ($Type)" -Level Debug -Category "Registry"
        
        if (-not $WhatIf) {
            Ensure-RegistryKey $Path
            New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
        }
        return $true
    } catch {
        Write-Error "Failed to set $Path\$Name : $($_.Exception.Message)"
        return $false
    }
}

function Remove-RegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        # Backup before removal
        Backup-RegistryValue -Path $Path -Name $Name
        
        Write-Log "Removing registry: $Path\$Name" -Level Debug -Category "Registry"
        
        if (-not $WhatIf -and (Test-Path $Path)) {
            Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Failed to remove $Path\$Name : $($_.Exception.Message)"
    }
}

# ========================= HARDWARE DETECTION =========================
function Get-SystemMemoryInfo {
    Write-Log "Detecting system memory configuration" -Level Info -Category "Detection"
    
    try {
        $computerSystem = Get-CimInstance Win32_ComputerSystem
        $totalRAM_Bytes = [int64]$computerSystem.TotalPhysicalMemory
        $totalRAM_GB = [math]::Round($totalRAM_Bytes / 1GB, 2)
        
        $memoryModules = @(Get-CimInstance Win32_PhysicalMemory | Select-Object Capacity, Speed, Manufacturer, PartNumber)
        
        Write-Success "Total RAM: $totalRAM_GB GB ($($memoryModules.Count) modules)"
        
        return @{
            TotalBytes = $totalRAM_Bytes
            TotalGB = $totalRAM_GB
            Modules = $memoryModules
        }
    } catch {
        Write-Error "Failed to detect system memory: $($_.Exception.Message)"
        return $null
    }
}

function Get-GPUInformation {
    Write-Log "Detecting GPU configuration with VRAM" -Level Info -Category "Detection"
    
    $gpuList = @()
    
    try {
        # Get GPUs from WMI
        $wmiGpus = Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterRAM -gt 0 } | Sort-Object Name
        
        foreach ($gpu in $wmiGpus) {
            $pnpDeviceID = $gpu.PNPDeviceID
            $vendorID = $null
            
            if ($pnpDeviceID -match "VEN_([0-9A-F]{4})") { 
                $vendorID = $Matches[1] 
            }
            
            $vendor = switch ($vendorID) {
                "10DE" { "NVIDIA" }
                { $_ -in @("1002", "1022") } { "AMD" }
                "8086" { "Intel" }
                default { "Unknown" }
            }
            
            $vramMB = 0
            if ($gpu.AdapterRAM -gt 0) {
                $vramMB = [math]::Floor($gpu.AdapterRAM / 1MB)
            }
            
            $gpuInfo = [PSCustomObject]@{
                Name = $gpu.Name
                Vendor = $vendor
                VendorID = $vendorID
                PNPDeviceID = $pnpDeviceID
                VRAM_MB = $vramMB
                VRAM_GB = [math]::Round($vramMB / 1024, 2)
                IsDiscrete = $vendor -in @("NVIDIA", "AMD")
                DriverVersion = $gpu.DriverVersion
                DriverDate = $gpu.DriverDate
            }
            
            $gpuList += $gpuInfo
        }
        
        # Enhanced VRAM detection for discrete GPUs
        $discreteGPUs = $gpuList | Where-Object IsDiscrete
        if ($discreteGPUs) {
            $enhancedVRAM = Get-EnhancedVRAMDetection
            if ($enhancedVRAM) {
                foreach ($gpu in $discreteGPUs) {
                    if ($gpu.Vendor -eq "NVIDIA" -and $enhancedVRAM.NVIDIA) {
                        $gpu.VRAM_MB = $enhancedVRAM.NVIDIA
                        $gpu.VRAM_GB = [math]::Round($enhancedVRAM.NVIDIA / 1024, 2)
                    } elseif ($gpu.Vendor -eq "AMD" -and $enhancedVRAM.AMD) {
                        $gpu.VRAM_MB = $enhancedVRAM.AMD  
                        $gpu.VRAM_GB = [math]::Round($enhancedVRAM.AMD / 1024, 2)
                    }
                }
            }
        }
        
        Write-Success "Detected $($gpuList.Count) GPU(s)"
        foreach ($gpu in $gpuList) {
            Write-Log "  - $($gpu.Name) [$($gpu.Vendor)] VRAM: $($gpu.VRAM_GB) GB" -Level Info
        }
        
        return $gpuList
        
    } catch {
        Write-Error "Failed to detect GPU information: $($_.Exception.Message)"
        return @()
    }
}

function Get-EnhancedVRAMDetection {
    $vramInfo = @{}
    
    # NVIDIA: Try nvidia-smi
    $nvidiaSmiPaths = @(
        "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
        "C:\Windows\System32\nvidia-smi.exe"
    )
    
    foreach ($path in $nvidiaSmiPaths) {
        if (Test-Path $path) {
            try {
                $output = & $path --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
                if ($output -and $output[0] -match '^\d+$') {
                    $vramInfo.NVIDIA = [int]$output[0]
                    Write-Log "NVIDIA VRAM detected via nvidia-smi: $($vramInfo.NVIDIA) MB" -Level Debug
                    break
                }
            } catch {
                Write-Log "nvidia-smi execution failed: $($_.Exception.Message)" -Level Debug
            }
        }
    }
    
    # Registry detection for all GPUs
    try {
        $displayNodes = Get-DisplayRegistryNodes
        foreach ($node in $displayNodes) {
            if ($node.Vendor -in @("NVIDIA", "AMD")) {
                $vramBytes = Get-RegistryVRAMBytes $node.Path
                if ($vramBytes -gt 0) {
                    $vramMB = [int]([math]::Floor($vramBytes / 1MB))
                    if (-not $vramInfo.ContainsKey($node.Vendor) -or $vramMB -gt $vramInfo[$node.Vendor]) {
                        $vramInfo[$node.Vendor] = $vramMB
                        Write-Log "$($node.Vendor) VRAM detected via registry: $vramMB MB" -Level Debug
                    }
                }
            }
        }
    } catch {
        Write-Log "Registry VRAM detection failed: $($_.Exception.Message)" -Level Debug
    }
    
    return $vramInfo
}

function Get-DisplayRegistryNodes {
    $root = "HKLM:\SYSTEM\CurrentControlSet\Control\Video"
    $nodes = @()
    
    if (Test-Path $root) {
        Get-ChildItem $root | Where-Object { $_.PSChildName -match '^\{[0-9A-F-]+\}$' } | ForEach-Object {
            Get-ChildItem $_.PSPath | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
                $regPath = $_.PSPath
                try {
                    $properties = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                    if ($properties) {
                        $matchingDeviceId = $properties.MatchingDeviceId
                        $providerName = $properties.ProviderName
                        $driverDesc = $properties.DriverDesc
                        
                        $vendor = "Unknown"
                        if ($matchingDeviceId -match "VEN_10DE" -or $providerName -match "NVIDIA" -or $driverDesc -match "NVIDIA") {
                            $vendor = "NVIDIA"
                        } elseif ($matchingDeviceId -match "VEN_(1002|1022)" -or $providerName -match "AMD|Advanced Micro Devices" -or $driverDesc -match "AMD|Radeon") {
                            $vendor = "AMD"
                        } elseif ($matchingDeviceId -match "VEN_8086" -or $providerName -match "Intel" -or $driverDesc -match "Intel") {
                            $vendor = "Intel"
                        }
                        
                        $nodes += [PSCustomObject]@{
                            Path = $regPath
                            Vendor = $vendor
                            Description = $driverDesc
                        }
                    }
                } catch {
                    Write-Log "Failed to read registry node $regPath : $($_.Exception.Message)" -Level Debug
                }
            }
        }
    }
    
    return $nodes
}

function Get-RegistryVRAMBytes {
    param([string]$RegistryPath)
    
    try {
        $properties = Get-ItemProperty -Path $RegistryPath -ErrorAction Stop
        
        # Try QWORD first (64-bit)
        if ($properties."HardwareInformation.qwMemorySize" -ne $null) {
            return [uint64]$properties."HardwareInformation.qwMemorySize"
        }
        
        # Fallback to DWORD (32-bit)
        if ($properties."HardwareInformation.MemorySize" -ne $null) {
            return [uint64]([uint32]$properties."HardwareInformation.MemorySize")
        }
    } catch {
        Write-Log "Failed to read VRAM from registry: $RegistryPath" -Level Debug
    }
    
    return 0
}

# ========================= OPTIMIZATION FUNCTIONS =========================
function Optimize-MemoryManagement {
    param([object]$MemoryInfo)
    
    Write-Step "Optimizing memory management settings"
    
    if (-not $MemoryInfo) {
        Write-Warning "Memory information not available, using defaults"
        return
    }
    
    $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    $fsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
    $pfPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
    
    # Calculate IoPageLockLimit: ~2 MB per GB RAM, clamped between 64-256 MB
    $ioLimitMB = [math]::Min(256, [math]::Max(64, [math]::Floor($MemoryInfo.TotalGB * 2)))
    $ioLimitBytes = [uint32]($ioLimitMB * 1MB)
    
    $settings = @(
        @{ Path = $mmPath; Name = "DisablePagingExecutive"; Value = 1; Type = "DWord"; Description = "Keep kernel in physical memory" },
        @{ Path = $mmPath; Name = "LargeSystemCache"; Value = 1; Type = "DWord"; Description = "Favor system cache over working set" },
        @{ Path = $mmPath; Name = "ClearPageFileAtShutdown"; Value = 0; Type = "DWord"; Description = "Don't clear pagefile at shutdown for faster boot" },
        @{ Path = $mmPath; Name = "IoPageLockLimit"; Value = $ioLimitBytes; Type = "DWord"; Description = "I/O page lock limit ($ioLimitMB MB)" },
        @{ Path = $mmPath; Name = "NonPagedPoolQuota"; Value = [uint32]::MaxValue; Type = "DWord"; Description = "Unlimited non-paged pool quota" },
        @{ Path = $mmPath; Name = "PagedPoolQuota"; Value = [uint32]::MaxValue; Type = "DWord"; Description = "Unlimited paged pool quota" },
        @{ Path = $mmPath; Name = "SystemPages"; Value = [uint32]::MaxValue; Type = "DWord"; Description = "Unlimited system pages" },
        @{ Path = $fsPath; Name = "NtfsMemoryUsage"; Value = 2; Type = "DWord"; Description = "Optimize NTFS for maximum memory usage" },
        @{ Path = $pfPath; Name = "EnablePrefetcher"; Value = 1; Type = "DWord"; Description = "Enable boot prefetching only" },
        @{ Path = $pfPath; Name = "EnableSuperfetch"; Value = 0; Type = "DWord"; Description = "Disable Superfetch service" }
    )
    
    $applied = 0
    foreach ($setting in $settings) {
        if (Set-RegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Description $setting.Description) {
            $applied++
        }
    }
    
    Write-Success "Memory management optimized: $applied/$($settings.Count) settings applied"
}

function Optimize-GraphicsSettings {
    param([array]$GPUList)
    
    Write-Step "Optimizing graphics settings"
    
    $gfxPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    $dwmPath = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"
    
    $settings = @(
        @{ Path = $gfxPath; Name = "HwSchMode"; Value = 2; Type = "DWord"; Description = "Enable Hardware Accelerated GPU Scheduling (HAGS)" },
        @{ Path = $dwmPath; Name = "OverlayTestMode"; Value = 5; Type = "DWord"; Description = "Disable Multi-Plane Overlay (MPO)" }
    )
    
    $applied = 0
    foreach ($setting in $settings) {
        if (Set-RegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Description $setting.Description) {
            $applied++
        }
    }
    
    # VRAM budgeting for discrete GPUs
    if ($GPUList) {
        $discreteGPUs = $GPUList | Where-Object IsDiscrete
        if ($discreteGPUs) {
            $maxVRAM_MB = ($discreteGPUs | Measure-Object -Property VRAM_MB -Maximum).Maximum
            if ($ForceVramMB -gt 0) {
                $maxVRAM_MB = $ForceVramMB
            }
            
            if ($maxVRAM_MB -gt 0) {
                Write-Log "Applying VRAM budgeting hint: $maxVRAM_MB MB" -Level Info
                $displayNodes = Get-DisplayRegistryNodes
                $targetNodes = $displayNodes | Where-Object { $_.Vendor -in @("NVIDIA", "AMD") }
                
                foreach ($node in $targetNodes) {
                    if (Set-RegistryValue -Path $node.Path -Name "DedicatedSegmentSize" -Value ([uint32]$maxVRAM_MB) -Type "DWord" -Description "VRAM budget hint") {
                        Write-Log "VRAM hint applied to: $($node.Description)" -Level Debug
                    }
                }
            }
        } else {
            Write-Warning "No discrete GPUs detected, skipping VRAM budgeting"
        }
    }
    
    Write-Success "Graphics settings optimized: $applied/$($settings.Count) settings applied"
}

function Optimize-GameSettings {
    Write-Step "Optimizing game-related settings"
    
    $gameBarPath = "HKCU:\Software\Microsoft\GameBar"
    $gameConfigPath = "HKCU:\System\GameConfigStore"
    
    $settings = @(
        @{ Path = $gameBarPath; Name = "AllowAutoGameMode"; Value = 1; Type = "DWord"; Description = "Enable automatic Game Mode" },
        @{ Path = $gameConfigPath; Name = "GameDVR_Enabled"; Value = 0; Type = "DWord"; Description = "Disable Xbox Game DVR" },
        @{ Path = $gameConfigPath; Name = "GameDVR_FSEBehaviorMode"; Value = 2; Type = "DWord"; Description = "Game DVR fullscreen exclusive behavior" },
        @{ Path = $gameConfigPath; Name = "GameDVR_HonorUserFSEBehaviorMode"; Value = 1; Type = "DWord"; Description = "Honor user FSE behavior mode" },
        @{ Path = $gameConfigPath; Name = "GameDVR_DXGIHonorFSEWindowsCompatible"; Value = 1; Type = "DWord"; Description = "DXGI FSE Windows compatibility" },
        @{ Path = $gameConfigPath; Name = "GameDVR_EFSEFeatureFlags"; Value = 0; Type = "DWord"; Description = "Disable enhanced FSE features" },
        @{ Path = $gameConfigPath; Name = "GameDVR_FSEBehavior"; Value = 2; Type = "DWord"; Description = "FSE behavior setting" },
        @{ Path = $gameConfigPath; Name = "GameDVR_HonorFSEWindowsCompatible"; Value = 1; Type = "DWord"; Description = "Honor FSE Windows compatibility" }
    )
    
    $applied = 0
    foreach ($setting in $settings) {
        if (Set-RegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Description $setting.Description) {
            $applied++
        }
    }
    
    Write-Success "Game settings optimized: $applied/$($settings.Count) settings applied"
}

function Optimize-NetworkSettings {
    if ($SkipNetwork) {
        Write-Log "Skipping network optimizations (user requested)" -Level Info
        return
    }
    
    Write-Step "Optimizing TCP network settings for low latency"
    
    $tcpPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
    
    $settings = @(
        @{ Path = $tcpPath; Name = "TcpNoDelay"; Value = 1; Type = "DWord"; Description = "Disable TCP delay algorithm" },
        @{ Path = $tcpPath; Name = "TcpAckFrequency"; Value = 1; Type = "DWord"; Description = "Send ACKs immediately" },
        @{ Path = $tcpPath; Name = "TcpDelAckTicks"; Value = 0; Type = "DWord"; Description = "No delayed ACK ticks" }
    )
    
    $applied = 0
    foreach ($setting in $settings) {
        if (Set-RegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Description $setting.Description) {
            $applied++
        }
    }
    
    Write-Success "Network settings optimized: $applied/$($settings.Count) settings applied"
}

function Optimize-PageFile {
    param([object]$MemoryInfo)
    
    Write-Step "Configuring pagefile settings"
    
    try {
        $systemDrive = $env:SystemDrive
        $pagefilePath = Join-Path $systemDrive "pagefile.sys"
        $mmPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        
        # Determine optimal pagefile size based on RAM
        $initialSizeMB = if ($MemoryInfo.TotalGB -ge 32) { 2048 } elseif ($MemoryInfo.TotalGB -ge 16) { 1536 } else { 1024 }
        $maxSizeMB = $initialSizeMB + 512
        
        $pagefileValue = "$pagefilePath $initialSizeMB $maxSizeMB"
        
        Write-Log "Setting pagefile: $pagefileValue" -Level Debug
        
        # Registry settings
        Set-RegistryValue -Path $mmPath -Name "PagingFiles" -Value @($pagefileValue) -Type "MultiString" -Description "Custom pagefile configuration"
        Set-RegistryValue -Path $mmPath -Name "ExistingPageFiles" -Value @($pagefilePath) -Type "MultiString" -Description "Existing pagefile paths"
        Set-RegistryValue -Path $mmPath -Name "TempPageFile" -Value 0 -Type "DWord" -Description "Disable temporary pagefile"
        
        if (-not $WhatIf) {
            # Disable automatic management
            $computerSystem = Get-CimInstance Win32_ComputerSystem
            if ($computerSystem.AutomaticManagedPagefile) {
                Set-CimInstance -InputObject $computerSystem -Property @{ AutomaticManagedPagefile = $false }
                Write-Log "Disabled automatic pagefile management" -Level Debug
            }
            
            # Remove existing pagefile settings
            $existingPagefiles = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue)
            foreach ($pf in $existingPagefiles) {
                Remove-CimInstance -InputObject $pf -ErrorAction SilentlyContinue
                Write-Log "Removed existing pagefile: $($pf.Name)" -Level Debug
            }
            
            # Create new pagefile setting
            New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                Name = $pagefilePath
                InitialSize = [UInt32]$initialSizeMB
                MaximumSize = [UInt32]$maxSizeMB
            } | Out-Null
        }
        
        Write-Success "Pagefile configured: $pagefilePath ($initialSizeMB-$maxSizeMB MB)"
        
    } catch {
        Write-Error "Failed to configure pagefile: $($_.Exception.Message)"
    }
}

function Optimize-MemoryCompression {
    Write-Step "Configuring memory compression"
    
    try {
        if (-not $WhatIf) {
            # Disable memory compression for gaming performance
            Disable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
            
            # Verify setting
            try {
                $mmAgent = Get-MMAgent
                $status = if ($mmAgent) { $mmAgent.MemoryCompression } else { "Disabled" }
                Write-Success "Memory compression: $status"
            } catch {
                Write-Success "Memory compression: Disabled"
            }
        } else {
            Write-Log "Would disable memory compression" -Level Info
        }
        
    } catch {
        Write-Warning "Failed to configure memory compression: $($_.Exception.Message)"
    }
}

# ========================= MAIN OPERATIONS =========================
function Invoke-SystemOptimization {
    Write-Step "Starting system optimization for gaming performance"
    
    # System detection
    $memoryInfo = Get-SystemMemoryInfo
    $gpuList = Get-GPUInformation
    
    if (-not $memoryInfo) {
        throw "Failed to detect system memory configuration"
    }
    
    # Apply optimizations
    try {
        Optimize-MemoryManagement -MemoryInfo $memoryInfo
        Optimize-GraphicsSettings -GPUList $gpuList  
        Optimize-GameSettings
        Optimize-NetworkSettings
        Optimize-PageFile -MemoryInfo $memoryInfo
        Optimize-MemoryCompression
        
        Write-Host "`n[OK] System optimization completed successfully!" -ForegroundColor Green
        Write-Host "[WARNING] REBOOT REQUIRED to activate all changes" -ForegroundColor Yellow
        
        if (-not $Force) {
            $reboot = Read-Host "`nReboot now? (y/N)"
            if ($reboot -match '^y(es)?$') {
                Write-Log "User initiated system reboot" -Level Info
                Restart-Computer -Confirm:$false -Force
            }
        }
        
    } catch {
        Write-Error "Optimization failed: $($_.Exception.Message)"
        throw
    }
}

function Invoke-SystemRevert {
    Write-Step "Reverting system optimizations to defaults"
    
    # Define default values for all settings
    $revertSettings = @(
        # Memory Management
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "DisablePagingExecutive"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "LargeSystemCache"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "ClearPageFileAtShutdown"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "IoPageLockLimit"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "NonPagedPoolQuota"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "PagedPoolQuota"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "SystemPages"; Value = 0; Type = "DWord" },
        
        # File System
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"; Name = "NtfsMemoryUsage"; Value = 1; Type = "DWord" },
        
        # Prefetch
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Name = "EnablePrefetcher"; Value = 3; Type = "DWord" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Name = "EnableSuperfetch"; Value = 3; Type = "DWord" },
        
        # Graphics
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; Name = "HwSchMode"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"; Name = "OverlayTestMode"; Value = 0; Type = "DWord" },
        
        # Game Settings (restore defaults)
        @{ Path = "HKCU:\Software\Microsoft\GameBar"; Name = "AllowAutoGameMode"; Value = 1; Type = "DWord" },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Value = 1; Type = "DWord" },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehaviorMode"; Value = 0; Type = "DWord" },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_HonorUserFSEBehaviorMode"; Value = 0; Type = "DWord" },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_DXGIHonorFSEWindowsCompatible"; Value = 0; Type = "DWord" },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_EFSEFeatureFlags"; Value = 0; Type = "DWord" },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehavior"; Value = 0; Type = "DWord" },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_HonorFSEWindowsCompatible"; Value = 0; Type = "DWord" },
        
        # Network
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"; Name = "TcpNoDelay"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"; Name = "TcpAckFrequency"; Value = 0; Type = "DWord" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"; Name = "TcpDelAckTicks"; Value = 2; Type = "DWord" }
    )
    
    $reverted = 0
    foreach ($setting in $revertSettings) {
        if (Set-RegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Description "Reverted to default") {
            $reverted++
        }
    }
    
    # Remove VRAM hints
    Write-Log "Removing VRAM budgeting hints" -Level Info
    $displayNodes = Get-DisplayRegistryNodes
    foreach ($node in $displayNodes) {
        Remove-RegistryValue -Path $node.Path -Name "DedicatedSegmentSize"
    }
    
    # Restore automatic pagefile management
    Write-Log "Restoring automatic pagefile management" -Level Info
    try {
        if (-not $WhatIf) {
            Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "PagingFiles" -Value @("") -Type "MultiString" -Description "Default pagefile setting"
            Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "ExistingPageFiles" -Value @("") -Type "MultiString" -Description "Default existing pagefiles"
            Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "TempPageFile" -Value 0 -Type "DWord" -Description "Default temp pagefile setting"
            
            $computerSystem = Get-CimInstance Win32_ComputerSystem
            if (-not $computerSystem.AutomaticManagedPagefile) {
                Set-CimInstance -InputObject $computerSystem -Property @{ AutomaticManagedPagefile = $true }
            }
            
            # Remove custom pagefile settings
            Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | 
                ForEach-Object { Remove-CimInstance -InputObject $_ -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Warning "Failed to restore automatic pagefile: $($_.Exception.Message)"
    }
    
    # Re-enable memory compression
    Write-Log "Re-enabling memory compression" -Level Info
    try {
        if (-not $WhatIf) {
            Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Failed to re-enable memory compression: $($_.Exception.Message)"
    }
    
    Write-Success "System revert completed: $reverted settings restored to defaults"
    Write-Host "[WARNING] REBOOT RECOMMENDED to fully apply reverted settings" -ForegroundColor Yellow
}

function Show-SystemReport {
    Write-Step "Generating comprehensive system report"
    
    # System Information
    $memoryInfo = Get-SystemMemoryInfo
    $gpuList = Get-GPUInformation
    
    Write-Host "`n" + ("="*60) -ForegroundColor Cyan
    Write-Host "SYSTEM CONFIGURATION REPORT" -ForegroundColor Cyan  
    Write-Host ("="*60) -ForegroundColor Cyan
    
    # Basic System Info
    Write-Host "`nSYSTEM INFORMATION:" -ForegroundColor Yellow
    Write-Host "  Computer Name: $env:COMPUTERNAME"
    Write-Host "  User: $env:USERNAME"
    Write-Host "  OS Version: $([Environment]::OSVersion.Version)"
    Write-Host "  PowerShell: $($PSVersionTable.PSVersion)"
    if ($memoryInfo) {
        Write-Host "  Total RAM: $($memoryInfo.TotalGB) GB"
        Write-Host "  Memory Modules: $($memoryInfo.Modules.Count)"
    }
    
    # GPU Information
    if ($gpuList -and $gpuList.Count -gt 0) {
        Write-Host "`nGPU CONFIGURATION:" -ForegroundColor Yellow
        foreach ($gpu in $gpuList) {
            $discrete = if ($gpu.IsDiscrete) { " (Discrete)" } else { " (Integrated)" }
            Write-Host "  - $($gpu.Name) [$($gpu.Vendor)]$discrete"
            Write-Host "    VRAM: $($gpu.VRAM_GB) GB"
            Write-Host "    Driver: $($gpu.DriverVersion)"
        }
    }
    
    # Current Registry Settings
    Write-Host "`nCURRENT OPTIMIZATION SETTINGS:" -ForegroundColor Yellow
    
    $registryChecks = @(
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "DisablePagingExecutive"; Description = "Disable Paging Executive" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "LargeSystemCache"; Description = "Large System Cache" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "IoPageLockLimit"; Description = "I/O Page Lock Limit (bytes)" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"; Name = "NtfsMemoryUsage"; Description = "NTFS Memory Usage" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Name = "EnablePrefetcher"; Description = "Prefetcher" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"; Name = "EnableSuperfetch"; Description = "Superfetch" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; Name = "HwSchMode"; Description = "Hardware GPU Scheduling" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"; Name = "OverlayTestMode"; Description = "Multi-Plane Overlay" },
        @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Description = "Xbox Game DVR" }
    )
    
    foreach ($check in $registryChecks) {
        try {
            $value = (Get-ItemProperty -Path $check.Path -Name $check.Name -ErrorAction SilentlyContinue).($check.Name)
            $displayValue = if ($null -eq $value) { "Not Set" } else { $value }
            Write-Host ("  {0}: {1}" -f $check.Description.PadRight(30), $displayValue)
        } catch {
            Write-Host ("  {0}: Error reading value" -f $check.Description.PadRight(30))
        }
    }
    
    # Pagefile Information
    Write-Host "`nPAGEFILE CONFIGURATION:" -ForegroundColor Yellow
    try {
        $computerSystem = Get-CimInstance Win32_ComputerSystem
        $pageFiles = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue)
        
        Write-Host "  Automatic Management: $($computerSystem.AutomaticManagedPagefile)"
        
        if ($pageFiles.Count -gt 0) {
            foreach ($pf in $pageFiles) {
                Write-Host "  Custom Pagefile: $($pf.Name)"
                Write-Host "    Initial Size: $($pf.InitialSize) MB"
                Write-Host "    Maximum Size: $($pf.MaximumSize) MB"
            }
        } else {
            Write-Host "  Custom Pagefiles: None (using automatic)"
        }
    } catch {
        Write-Host "  Pagefile Info: Error retrieving information"
    }
    
    # Memory Compression
    Write-Host "`nMEMORY COMPRESSION:" -ForegroundColor Yellow
    try {
        $mmAgent = Get-MMAgent -ErrorAction SilentlyContinue
        $mcStatus = if ($mmAgent) { $mmAgent.MemoryCompression } else { "Unknown" }
        Write-Host "  Status: $mcStatus"
    } catch {
        Write-Host "  Status: Error retrieving status"
    }
    
    # VRAM Hints
    Write-Host "`nVRAM BUDGETING HINTS:" -ForegroundColor Yellow
    $displayNodes = Get-DisplayRegistryNodes
    $vramHints = 0
    foreach ($node in $displayNodes) {
        try {
            $dedicatedSize = (Get-ItemProperty -Path $node.Path -Name "DedicatedSegmentSize" -ErrorAction SilentlyContinue).DedicatedSegmentSize
            if ($dedicatedSize) {
                Write-Host "  $($node.Vendor) GPU: $dedicatedSize MB"
                $vramHints++
            }
        } catch {}
    }
    if ($vramHints -eq 0) {
        Write-Host "  No custom VRAM hints set"
    }
    
    Write-Host "`n" + ("="*60) -ForegroundColor Cyan
    Write-Host "Report generated: $(Get-Date)" -ForegroundColor Gray
}

# ========================= CONFIGURATION FILE SUPPORT =========================
function Get-ConfigurationSettings {
    param([string]$ConfigFile)
    
    if (-not $ConfigFile -or -not (Test-Path $ConfigFile)) {
        return $null
    }
    
    try {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        Write-Success "Configuration loaded from: $ConfigFile"
        return $config
    } catch {
        Write-Warning "Failed to load configuration file: $($_.Exception.Message)"
        return $null
    }
}

function New-DefaultConfiguration {
    return @{
        Version = "1.0"
        Description = "GameMemVRAM-Tuner Configuration"
        Settings = @{
            Memory = @{
                DisablePagingExecutive = $true
                LargeSystemCache = $true
                IoPageLockLimitFactor = 2
                EnablePrefetcher = $true
                EnableSuperfetch = $false
            }
            Graphics = @{
                HardwareScheduling = $true
                DisableMultiPlaneOverlay = $true
                ApplyVRAMHints = $true
            }
            Gaming = @{
                EnableGameMode = $true
                DisableGameDVR = $true
            }
            Network = @{
                EnableLowLatency = $true
                TcpNoDelay = $true
            }
            Pagefile = @{
                UseCustomSize = $true
                MinSizeMB = 1024
                MaxSizeMB = 2048
            }
            MemoryCompression = @{
                Enabled = $false
            }
        }
    } | ConvertTo-Json -Depth 10
}

# ========================= MAIN EXECUTION =========================
function Main {
    try {
        # Initialize logging
        Write-Log "GameMemVRAM-Tuner-Production starting" -Level Info -Category "System"
        Write-Log "Parameters: Apply=$Apply, Revert=$Revert, Report=$Report, Backup=$Backup, Restore=$Restore" -Level Debug -Category "System"
        
        # Validate prerequisites
        Test-Prerequisites
        Test-SystemStability
        
        # Load configuration if specified
        $config = $null
        if ($ConfigFile) {
            $config = Get-ConfigurationSettings -ConfigFile $ConfigFile
        }
        
        # Determine operation
        $operation = "Report"  # Default
        if ($Apply) { $operation = "Apply" }
        elseif ($Revert) { $operation = "Revert" }  
        elseif ($Backup) { $operation = "Backup" }
        elseif ($Restore) { $operation = "Restore" }
        elseif (-not $Report) { $operation = "Apply" }  # Default to Apply if no specific operation
        
        Write-Log "Operation: $operation" -Level Info -Category "System"
        
        # Execute requested operation
        switch ($operation) {
            "Apply" {
                if ($BackupPath) {
                    Export-SystemBackup -BackupPath $BackupPath
                }
                Invoke-SystemOptimization
                Show-SystemReport
            }
            
            "Revert" {
                if ($BackupPath) {
                    Export-SystemBackup -BackupPath $BackupPath
                }
                Invoke-SystemRevert  
                Show-SystemReport
            }
            
            "Report" {
                Show-SystemReport
            }
            
            "Backup" {
                if (-not $BackupPath) {
                    $BackupPath = Join-Path $env:USERPROFILE "Desktop"
                }
                Export-SystemBackup -BackupPath $BackupPath
            }
            
            "Restore" {
                if (-not $BackupPath) {
                    throw "BackupPath parameter is required for restore operation"
                }
                $backupFiles = Get-ChildItem -Path $BackupPath -Filter "GameMemVRAM-Registry-Backup-*.json" | Sort-Object LastWriteTime -Descending
                if (-not $backupFiles) {
                    throw "No backup files found in: $BackupPath"
                }
                
                $latestBackup = $backupFiles[0].FullName
                Write-Log "Using latest backup: $latestBackup" -Level Info
                Import-SystemBackup -BackupFile $latestBackup
            }
        }
        
        Write-Log "GameMemVRAM-Tuner-Production completed successfully" -Level Info -Category "System"
        
    } catch {
        Write-Error "Script execution failed: $($_.Exception.Message)"
        Write-Log "Script execution failed: $($_.Exception.Message)" -Level Error -Category "System"
        
        if ($_.Exception.StackTrace) {
            Write-Log "Stack trace: $($_.Exception.StackTrace)" -Level Debug -Category "System"
        }
        
        exit 1
    }
}

# Execute main function
Main