# Core-Utils.psm1 - Shared utilities for GameMemVRAM-Tuner Ultimate

# ========================= LOGGING SYSTEM =========================
enum LogLevel {
    Error = 0
    Warn = 1
    Info = 2
    Debug = 3
}

$Script:CurrentLogLevel = [LogLevel]::Info
$Script:LogFile = $null

function Initialize-Logging {
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,
        
        [Parameter()]
        [LogLevel]$LogLevel = [LogLevel]::Info
    )
    
    $Script:LogFile = $LogPath
    $Script:CurrentLogLevel = $LogLevel
    
    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    Write-Log "Logging initialized: $LogPath (Level: $LogLevel)" -Level Info
}

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
    if ($Script:LogFile) {
        try {
            Add-Content -Path $Script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
        } catch {
            # Fallback if logging fails
        }
    }
    
    # Write to console with colors (only in interactive mode)
    if ([Environment]::UserInteractive) {
        switch ($Level) {
            ([LogLevel]::Error) { Write-Host "ERROR: $Message" -ForegroundColor Red }
            ([LogLevel]::Warn)  { Write-Host "WARN:  $Message" -ForegroundColor Yellow }
            ([LogLevel]::Info)  { Write-Host "INFO:  $Message" -ForegroundColor Cyan }
            ([LogLevel]::Debug) { Write-Host "DEBUG: $Message" -ForegroundColor Gray }
        }
    }
}

# ========================= SYSTEM VALIDATION =========================
function Test-SystemPrerequisites {
    Write-Log "Validating system prerequisites" -Level Info -Category "Validation"
    
    $issues = @()
    
    # Windows version check
    $osVersion = [Environment]::OSVersion.Version
    if ($osVersion -lt [Version]"10.0.0.0") {
        $issues += "Windows 10 or later required (detected: $osVersion)"
    }
    
    # PowerShell version check
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $issues += "PowerShell 5.1 or later required (detected: $($PSVersionTable.PSVersion))"
    }
    
    # Administrator check
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $issues += "This script must be run as Administrator"
    }
    
    # Disk space check
    $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
    if ($systemDrive -and ($systemDrive.FreeSpace / 1MB) -lt 100) {
        $issues += "Insufficient disk space (minimum 100MB required)"
    }
    
    # Check for pending reboots
    $pendingReboot = Test-PendingReboot
    if ($pendingReboot) {
        Write-Log "System has pending reboot. Recommended to restart before optimization." -Level Warn
    }
    
    if ($issues.Count -gt 0) {
        Write-Log "System prerequisites failed:" -Level Error -Category "Validation"
        $issues | ForEach-Object { Write-Log "  - $_" -Level Error -Category "Validation" }
        return $false
    }
    
    Write-Log "System prerequisites validated successfully" -Level Info -Category "Validation"
    return $true
}

function Test-PendingReboot {
    # Check various indicators of pending reboot
    $regKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    )
    
    foreach ($key in $regKeys) {
        if (Test-Path $key) {
            return $true
        }
    }
    
    # Check for pending file rename operations
    $pendingFileRename = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
    if ($pendingFileRename) {
        return $true
    }
    
    return $false
}

# ========================= REGISTRY OPERATIONS =========================
function Ensure-RegistryKey {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        Write-Log "Creating registry key: $Path" -Level Debug -Category "Registry"
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
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
        [string]$Description = "",
        
        [Parameter()]
        [switch]$WhatIf
    )
    
    try {
        Write-Log "Setting registry: $Path\$Name = $Value ($Type)" -Level Debug -Category "Registry"
        
        if (-not $WhatIf) {
            Ensure-RegistryKey $Path
            New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
        }
        return $true
    } catch {
        Write-Log "Failed to set $Path\$Name : $($_.Exception.Message)" -Level Error -Category "Registry"
        return $false
    }
}

function Get-RegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter()]
        [object]$DefaultValue = $null
    )
    
    try {
        if (Test-Path $Path) {
            $property = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
            return $property.$Name
        }
    } catch {
        Write-Log "Failed to read $Path\$Name : $($_.Exception.Message)" -Level Debug -Category "Registry"
    }
    
    return $DefaultValue
}

function Remove-RegistryValue {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter()]
        [switch]$WhatIf
    )
    
    try {
        Write-Log "Removing registry: $Path\$Name" -Level Debug -Category "Registry"
        
        if (-not $WhatIf -and (Test-Path $Path)) {
            Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        }
        return $true
    } catch {
        Write-Log "Failed to remove $Path\$Name : $($_.Exception.Message)" -Level Warn -Category "Registry"
        return $false
    }
}

# ========================= BACKUP SYSTEM =========================
$Script:BackupData = @{
    Timestamp = $null
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    ScriptVersion = $null
    RegistryValues = @{}
    Services = @{}
    SystemInfo = @{}
}

function Add-BackupEntry {
    param(
        [Parameter(Mandatory)]
        [string]$Category,
        
        [Parameter(Mandatory)]
        [string]$Key,
        
        [Parameter(Mandatory)]
        [object]$Value,
        
        [Parameter()]
        [string]$Description = ""
    )
    
    if (-not $Script:BackupData.ContainsKey($Category)) {
        $Script:BackupData[$Category] = @{}
    }
    
    $Script:BackupData[$Category][$Key] = @{
        Value = $Value
        Timestamp = Get-Date
        Description = $Description
    }
    
    Write-Log "Backed up: $Category\$Key" -Level Debug -Category "Backup"
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
        $currentValue = Get-RegistryValue -Path $Path -Name $Name
        if ($null -ne $currentValue) {
            $key = "$Path\$Name"
            $backupEntry = @{
                Path = $Path
                Name = $Name
                Value = $currentValue
                Type = (Get-Item $Path).GetValueKind($Name)
                Description = $Description
            }
            Add-BackupEntry -Category "RegistryValues" -Key $key -Value $backupEntry -Description $Description
        }
    } catch {
        Write-Log "Failed to backup $Path\$Name : $($_.Exception.Message)" -Level Warn -Category "Backup"
    }
}

function Backup-ServiceState {
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName
    )
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            $serviceState = @{
                Name = $service.Name
                Status = $service.Status.ToString()
                StartType = $service.StartType.ToString()
                DisplayName = $service.DisplayName
            }
            Add-BackupEntry -Category "Services" -Key $ServiceName -Value $serviceState -Description "Service state backup"
        }
    } catch {
        Write-Log "Failed to backup service $ServiceName : $($_.Exception.Message)" -Level Warn -Category "Backup"
    }
}

function New-SystemBackup {
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath
    )
    
    Write-Log "Creating comprehensive system backup" -Level Info -Category "Backup"
    
    try {
        # Initialize backup data
        $Script:BackupData.Timestamp = Get-Date
        $Script:BackupData.ScriptVersion = "3.0"
        
        # Collect system information
        $Script:BackupData.SystemInfo = @{
            OSVersion = [Environment]::OSVersion.Version.ToString()
            PSVersion = $PSVersionTable.PSVersion.ToString()
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            Domain = $env:USERDOMAIN
            TotalRAM_GB = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
        }
        
        # Export to JSON
        $json = $Script:BackupData | ConvertTo-Json -Depth 10
        Set-Content -Path $BackupPath -Value $json -Encoding UTF8
        
        Write-Log "System backup saved: $BackupPath" -Level Info -Category "Backup"
        return $true
        
    } catch {
        Write-Log "Backup creation failed: $($_.Exception.Message)" -Level Error -Category "Backup"
        return $false
    }
}

function Restore-SystemBackup {
    param(
        [Parameter(Mandatory)]
        [string]$BackupFile
    )
    
    Write-Log "Restoring system from backup: $BackupFile" -Level Info -Category "Restore"
    
    try {
        if (-not (Test-Path $BackupFile)) {
            throw "Backup file not found: $BackupFile"
        }
        
        $backupData = Get-Content $BackupFile -Raw | ConvertFrom-Json
        Write-Log "Loaded backup from: $($backupData.Timestamp)" -Level Info -Category "Restore"
        
        $restored = 0
        $failed = 0
        
        # Restore registry values
        if ($backupData.RegistryValues) {
            foreach ($key in $backupData.RegistryValues.PSObject.Properties.Name) {
                $regValue = $backupData.RegistryValues.$key
                try {
                    Set-RegistryValue -Path $regValue.Path -Name $regValue.Name -Value $regValue.Value -Type $regValue.Type
                    $restored++
                } catch {
                    Write-Log "Failed to restore $key : $($_.Exception.Message)" -Level Warn -Category "Restore"
                    $failed++
                }
            }
        }
        
        # Restore services
        if ($backupData.Services) {
            foreach ($serviceName in $backupData.Services.PSObject.Properties.Name) {
                $serviceData = $backupData.Services.$serviceName
                try {
                    Set-Service -Name $serviceName -StartupType $serviceData.StartType
                    if ($serviceData.Status -eq "Running") {
                        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                    }
                    $restored++
                } catch {
                    Write-Log "Failed to restore service $serviceName : $($_.Exception.Message)" -Level Warn -Category "Restore"
                    $failed++
                }
            }
        }
        
        Write-Log "Restore completed: $restored restored, $failed failed" -Level Info -Category "Restore"
        return $true
        
    } catch {
        Write-Log "Restore failed: $($_.Exception.Message)" -Level Error -Category "Restore"
        return $false
    }
}

# ========================= UTILITY FUNCTIONS =========================
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WindowsVersion {
    param(
        [Parameter(Mandatory)]
        [Version]$MinimumVersion
    )
    
    $osVersion = [Environment]::OSVersion.Version
    return $osVersion -ge $MinimumVersion
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,
        
        [Parameter()]
        [int]$MaxRetries = 3,
        
        [Parameter()]
        [int]$DelaySeconds = 2
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            return & $ScriptBlock
        }
        catch {
            Write-Log "Attempt $i failed: $($_.Exception.Message)" -Level Warn
            if ($i -lt $MaxRetries) {
                Start-Sleep -Seconds $DelaySeconds
            }
            else {
                throw
            }
        }
    }
}

function Get-SystemInformation {
    return @{
        ComputerName = $env:COMPUTERNAME
        OSVersion = "$([Environment]::OSVersion.Version) ($([Environment]::OSVersion.VersionString))"
        PSVersion = $PSVersionTable.PSVersion.ToString()
        Domain = $env:USERDOMAIN
        UserName = $env:USERNAME
        Is64Bit = [Environment]::Is64BitOperatingSystem
        ProcessorCount = $env:NUMBER_OF_PROCESSORS
        SystemDrive = $env:SystemDrive
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Initialize-Logging',
    'Write-Log',
    'Test-SystemPrerequisites',
    'Test-PendingReboot',
    'Ensure-RegistryKey',
    'Set-RegistryValue',
    'Get-RegistryValue',
    'Remove-RegistryValue',
    'Add-BackupEntry',
    'Backup-RegistryValue',
    'Backup-ServiceState',
    'New-SystemBackup',
    'Restore-SystemBackup',
    'Test-IsAdmin',
    'Test-WindowsVersion',
    'Invoke-WithRetry',
    'Get-SystemInformation'
)