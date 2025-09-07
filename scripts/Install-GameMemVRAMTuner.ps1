#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installation script for GameMemVRAM-Tuner system optimization tool.

.DESCRIPTION
    This script installs the GameMemVRAM-Tuner with the following features:
    - Creates scheduled tasks for automatic optimization
    - Sets up performance monitoring
    - Configures Windows Event Log source
    - Creates desktop shortcuts and Start Menu entries
    - Validates system compatibility
    - Installs required dependencies

.PARAMETER InstallPath
    Installation directory (default: C:\Program Files\GameMemVRAM-Tuner)

.PARAMETER CreateScheduledTask
    Create scheduled task for automatic optimization on boot

.PARAMETER EnableMonitoring
    Enable performance monitoring and logging

.PARAMETER CreateShortcuts
    Create desktop and Start Menu shortcuts

.EXAMPLE
    .\Install-GameMemVRAMTuner.ps1
    
.EXAMPLE
    .\Install-GameMemVRAMTuner.ps1 -InstallPath "C:\Tools\GMVT" -CreateScheduledTask -EnableMonitoring
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallPath = "C:\Program Files\GameMemVRAM-Tuner",
    
    [Parameter()]
    [switch]$CreateScheduledTask,
    
    [Parameter()]
    [switch]$EnableMonitoring,
    
    [Parameter()]
    [switch]$CreateShortcuts,
    
    [Parameter()]
    [switch]$Force
)

# Constants
$Script:ScriptName = "GameMemVRAM-Tuner Installer"
$Script:EventLogSource = "GameMemVRAM-Tuner"

function Write-InstallLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Cyan }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Also log to Windows Event Log if source exists
    try {
        if ([System.Diagnostics.EventLog]::SourceExists($Script:EventLogSource)) {
            $eventType = switch ($Level) {
                'Error' { 'Error' }
                'Warning' { 'Warning' }
                default { 'Information' }
            }
            Write-EventLog -LogName Application -Source $Script:EventLogSource -EventId 1000 -EntryType $eventType -Message $Message
        }
    } catch {
        # Silently continue if event logging fails
    }
}

function Test-InstallationPrerequisites {
    Write-InstallLog "Validating installation prerequisites..." -Level Info
    
    $errors = @()
    
    # Administrator check
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $errors += "This installer must be run as Administrator"
    }
    
    # PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $errors += "PowerShell 5.1 or later is required. Current version: $($PSVersionTable.PSVersion)"
    }
    
    # Windows version
    $osVersion = [Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        $errors += "Windows 10 or later is required. Current version: $osVersion"
    }
    
    # Disk space (minimum 100 MB)
    $installDrive = Split-Path $InstallPath -Qualifier
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $installDrive }
        if ($disk -and ($disk.FreeSpace / 1MB) -lt 100) {
            $errors += "Insufficient disk space. At least 100 MB required on drive $installDrive"
        }
    } catch {
        Write-InstallLog "Warning: Could not verify disk space on $installDrive" -Level Warning
    }
    
    if ($errors.Count -gt 0) {
        foreach ($error in $errors) {
            Write-InstallLog $error -Level Error
        }
        throw "Prerequisites not met. Installation cannot continue."
    }
    
    Write-InstallLog "Prerequisites validated successfully" -Level Success
}

function New-InstallationDirectories {
    Write-InstallLog "Creating installation directories..." -Level Info
    
    $directories = @(
        $InstallPath,
        (Join-Path $InstallPath "Scripts"),
        (Join-Path $InstallPath "Config"),
        (Join-Path $InstallPath "Logs"),
        (Join-Path $InstallPath "Backup"),
        (Join-Path $InstallPath "Profiles")
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                Write-InstallLog "Created directory: $dir" -Level Info
            } catch {
                throw "Failed to create directory: $dir - $($_.Exception.Message)"
            }
        } else {
            Write-InstallLog "Directory already exists: $dir" -Level Info
        }
    }
    
    Write-InstallLog "Installation directories created" -Level Success
}

function Copy-InstallationFiles {
    Write-InstallLog "Copying installation files..." -Level Info
    
    $sourceDir = Split-Path $MyInvocation.PSCommandPath -Parent
    $sourceFiles = @(
        @{ Source = "GameMemVRAM-Tuner-Production.ps1"; Destination = "Scripts"; Required = $true },
        @{ Source = "..\config\default-config.json"; Destination = "Config"; Required = $false }
    )
    
    foreach ($file in $sourceFiles) {
        $sourcePath = Join-Path $sourceDir $file.Source
        $destPath = Join-Path $InstallPath $file.Destination
        $fileName = Split-Path $file.Source -Leaf
        $fullDestPath = Join-Path $destPath $fileName
        
        if (Test-Path $sourcePath) {
            try {
                Copy-Item -Path $sourcePath -Destination $fullDestPath -Force
                Write-InstallLog "Copied: $fileName to $($file.Destination)" -Level Info
            } catch {
                $message = "Failed to copy $fileName : $($_.Exception.Message)"
                if ($file.Required) {
                    throw $message
                } else {
                    Write-InstallLog $message -Level Warning
                }
            }
        } elseif ($file.Required) {
            throw "Required source file not found: $sourcePath"
        } else {
            Write-InstallLog "Optional file not found: $sourcePath" -Level Warning
        }
    }
    
    Write-InstallLog "Installation files copied" -Level Success
}

function Register-EventLogSource {
    Write-InstallLog "Registering Windows Event Log source..." -Level Info
    
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($Script:EventLogSource)) {
            New-EventLog -LogName Application -Source $Script:EventLogSource
            Write-InstallLog "Event log source registered: $Script:EventLogSource" -Level Success
        } else {
            Write-InstallLog "Event log source already exists: $Script:EventLogSource" -Level Info
        }
    } catch {
        Write-InstallLog "Failed to register event log source: $($_.Exception.Message)" -Level Warning
    }
}

function New-ScheduledTask {
    if (-not $CreateScheduledTask) {
        Write-InstallLog "Scheduled task creation skipped (not requested)" -Level Info
        return
    }
    
    Write-InstallLog "Creating scheduled task for automatic optimization..." -Level Info
    
    try {
        $taskName = "GameMemVRAM-Tuner Auto Optimization"
        $scriptPath = Join-Path $InstallPath "Scripts\GameMemVRAM-Tuner-Production.ps1"
        $arguments = "-Apply -Force"
        
        # Remove existing task if it exists
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-InstallLog "Removed existing scheduled task" -Level Info
        }
        
        # Create new task
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" $arguments"
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Automatically applies GameMemVRAM-Tuner optimizations at system startup"
        
        Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null
        
        Write-InstallLog "Scheduled task created: $taskName" -Level Success
        
    } catch {
        Write-InstallLog "Failed to create scheduled task: $($_.Exception.Message)" -Level Error
    }
}

function New-PerformanceMonitoring {
    if (-not $EnableMonitoring) {
        Write-InstallLog "Performance monitoring setup skipped (not requested)" -Level Info
        return
    }
    
    Write-InstallLog "Setting up performance monitoring..." -Level Info
    
    try {
        # Create monitoring script
        $monitoringScript = @'
# GameMemVRAM-Tuner Performance Monitor
param([string]$LogPath = "C:\Program Files\GameMemVRAM-Tuner\Logs\performance.log")

function Write-PerformanceLog {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    "$timestamp - $Message" | Out-File -FilePath $LogPath -Append
}

# Collect performance metrics
$memory = Get-CimInstance Win32_OperatingSystem
$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterRAM -gt 0 } | Select-Object -First 1

$metrics = @{
    TotalRAM_MB = [math]::Round($memory.TotalVisibleMemorySize / 1024, 2)
    AvailableRAM_MB = [math]::Round($memory.AvailablePhysicalMemory / 1024, 2)
    UsedRAM_Percent = [math]::Round((($memory.TotalVisibleMemorySize - $memory.AvailablePhysicalMemory) / $memory.TotalVisibleMemorySize) * 100, 2)
    GPU_Name = $gpu.Name
    PageFileUsage_MB = [math]::Round(($memory.TotalVirtualMemorySize - $memory.AvailableVirtualMemory) / 1024, 2)
}

$logEntry = "RAM: $($metrics.UsedRAM_Percent)% | Available: $($metrics.AvailableRAM_MB) MB | PageFile: $($metrics.PageFileUsage_MB) MB | GPU: $($metrics.GPU_Name)"
Write-PerformanceLog $logEntry
'@
        
        $monitoringScriptPath = Join-Path $InstallPath "Scripts\Performance-Monitor.ps1"
        $monitoringScript | Out-File -FilePath $monitoringScriptPath -Encoding UTF8
        
        # Create monitoring scheduled task
        $taskName = "GameMemVRAM-Tuner Performance Monitor"
        $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$monitoringScriptPath`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Monitors system performance metrics for GameMemVRAM-Tuner"
        
        Register-ScheduledTask -TaskName $taskName -InputObject $task | Out-Null
        
        Write-InstallLog "Performance monitoring configured" -Level Success
        
    } catch {
        Write-InstallLog "Failed to setup performance monitoring: $($_.Exception.Message)" -Level Error
    }
}

function New-Shortcuts {
    if (-not $CreateShortcuts) {
        Write-InstallLog "Shortcut creation skipped (not requested)" -Level Info
        return
    }
    
    Write-InstallLog "Creating shortcuts..." -Level Info
    
    try {
        $shell = New-Object -ComObject WScript.Shell
        $scriptPath = Join-Path $InstallPath "Scripts\GameMemVRAM-Tuner-Production.ps1"
        
        # Desktop shortcut
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        $shortcutPath = Join-Path $desktopPath "GameMemVRAM-Tuner.lnk"
        
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "PowerShell.exe"
        $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$scriptPath`" -Apply"
        $shortcut.WorkingDirectory = Split-Path $scriptPath -Parent
        $shortcut.Description = "GameMemVRAM-Tuner System Optimizer"
        $shortcut.WindowStyle = 1  # Normal window
        $shortcut.Save()
        
        Write-InstallLog "Desktop shortcut created: $shortcutPath" -Level Success
        
        # Start Menu shortcut
        $startMenuPath = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
        $startMenuShortcutPath = Join-Path $startMenuPath "GameMemVRAM-Tuner.lnk"
        
        $startMenuShortcut = $shell.CreateShortcut($startMenuShortcutPath)
        $startMenuShortcut.TargetPath = "PowerShell.exe"
        $startMenuShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$scriptPath`" -Apply"
        $startMenuShortcut.WorkingDirectory = Split-Path $scriptPath -Parent
        $startMenuShortcut.Description = "GameMemVRAM-Tuner System Optimizer"
        $startMenuShortcut.WindowStyle = 1
        $startMenuShortcut.Save()
        
        Write-InstallLog "Start Menu shortcut created: $startMenuShortcutPath" -Level Success
        
    } catch {
        Write-InstallLog "Failed to create shortcuts: $($_.Exception.Message)" -Level Error
    }
}

function Set-InstallationPermissions {
    Write-InstallLog "Setting installation directory permissions..." -Level Info
    
    try {
        # Grant full control to Administrators and SYSTEM
        $acl = Get-Acl $InstallPath
        
        # Administrator permissions
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($adminRule)
        
        # SYSTEM permissions  
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($systemRule)
        
        # Read permissions for Users
        $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Users", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($userRule)
        
        Set-Acl -Path $InstallPath -AclObject $acl
        
        Write-InstallLog "Installation permissions configured" -Level Success
        
    } catch {
        Write-InstallLog "Failed to set permissions: $($_.Exception.Message)" -Level Warning
    }
}

function Test-Installation {
    Write-InstallLog "Validating installation..." -Level Info
    
    $errors = @()
    
    # Check main script exists and is executable
    $mainScript = Join-Path $InstallPath "Scripts\GameMemVRAM-Tuner-Production.ps1"
    if (-not (Test-Path $mainScript)) {
        $errors += "Main script not found: $mainScript"
    } else {
        try {
            # Test script syntax
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $mainScript -Raw), [ref]$null)
            Write-InstallLog "Main script syntax validated" -Level Info
        } catch {
            $errors += "Main script has syntax errors: $($_.Exception.Message)"
        }
    }
    
    # Check directories
    $requiredDirs = @("Scripts", "Config", "Logs", "Backup")
    foreach ($dir in $requiredDirs) {
        $fullPath = Join-Path $InstallPath $dir
        if (-not (Test-Path $fullPath)) {
            $errors += "Required directory missing: $fullPath"
        }
    }
    
    if ($errors.Count -gt 0) {
        foreach ($error in $errors) {
            Write-InstallLog $error -Level Error
        }
        throw "Installation validation failed"
    }
    
    Write-InstallLog "Installation validation completed successfully" -Level Success
}

function Show-InstallationSummary {
    Write-Host "`n" + ("="*60) -ForegroundColor Green
    Write-Host "INSTALLATION COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host ("="*60) -ForegroundColor Green
    
    Write-Host "`nInstallation Details:" -ForegroundColor Cyan
    Write-Host "  Install Path: $InstallPath"
    Write-Host "  Main Script: Scripts\GameMemVRAM-Tuner-Production.ps1"
    Write-Host "  Configuration: Config\default-config.json"
    Write-Host "  Logs Directory: Logs\"
    Write-Host "  Backup Directory: Backup\"
    
    if ($CreateScheduledTask) {
        Write-Host "`nScheduled Tasks:" -ForegroundColor Cyan
        Write-Host "  ✓ Auto Optimization (runs at startup)"
        if ($EnableMonitoring) {
            Write-Host "  ✓ Performance Monitor (runs every 15 minutes)"
        }
    }
    
    if ($CreateShortcuts) {
        Write-Host "`nShortcuts Created:" -ForegroundColor Cyan
        Write-Host "  ✓ Desktop shortcut"
        Write-Host "  ✓ Start Menu shortcut"
    }
    
    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "  1. Run the main script to optimize your system:"
    Write-Host "     PowerShell -ExecutionPolicy Bypass -File `"$InstallPath\Scripts\GameMemVRAM-Tuner-Production.ps1`" -Apply"
    Write-Host "  2. Create a backup before making changes:"
    Write-Host "     Add -Backup -BackupPath `"$InstallPath\Backup`" to the command"
    Write-Host "  3. Review logs in: $InstallPath\Logs\"
    
    Write-Host "`nFor help and documentation, run:" -ForegroundColor Cyan
    Write-Host "  Get-Help `"$InstallPath\Scripts\GameMemVRAM-Tuner-Production.ps1`" -Full"
}

# Main installation process
try {
    Write-Host "Starting GameMemVRAM-Tuner Installation..." -ForegroundColor Green
    Write-Host ("="*50) -ForegroundColor Green
    
    Test-InstallationPrerequisites
    New-InstallationDirectories
    Copy-InstallationFiles
    Register-EventLogSource
    New-ScheduledTask
    New-PerformanceMonitoring
    New-Shortcuts
    Set-InstallationPermissions
    Test-Installation
    
    Show-InstallationSummary
    
} catch {
    Write-InstallLog "Installation failed: $($_.Exception.Message)" -Level Error
    Write-Host "`nInstallation failed. See error details above." -ForegroundColor Red
    exit 1
}