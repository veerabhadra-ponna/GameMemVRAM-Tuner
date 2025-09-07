#requires -version 5.1
#requires -runasadministrator

<#
.SYNOPSIS
    Windows Gaming Performance Optimizer - ETW Cleanup & System Optimization Script

.DESCRIPTION
    Production-grade script to optimize Windows for gaming by disabling unnecessary ETW logging,
    telemetry services, and applying performance optimizations. Includes comprehensive logging,
    error handling, rollback capabilities, and system verification.

.PARAMETER Mode
    Operation mode: Apply, Rollback, or Verify
    
.PARAMETER LogPath
    Custom path for log files (default: script directory)
    
.PARAMETER Force
    Skip confirmation prompts
    
.PARAMETER CreateRestorePoint
    Create system restore point before changes

.EXAMPLE
    .\Gaming_Performance_Optimizer.ps1 -Mode Apply -CreateRestorePoint
    
.EXAMPLE
    .\Gaming_Performance_Optimizer.ps1 -Mode Rollback
    
.NOTES
    Version: 2.0
    Author: Gaming Performance Optimization
    Requires: Windows 10/11, PowerShell 5.1+, Administrator privileges
    
.LINK
    https://docs.microsoft.com/en-us/windows/win32/etw/event-tracing-portal
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Apply", "Rollback", "Verify")]
    [string]$Mode = "Apply",
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = $PSScriptRoot,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$CreateRestorePoint,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBackup,

    [Parameter(Mandatory=$false)]
    [string]$BackupFile
)

# Script configuration
$script:ScriptVersion = "2.0"
$script:ScriptName = "Gaming Performance Optimizer"
$script:ConfigFile = Join-Path $LogPath "GamingOptimizer_Config.json"
$script:LogFile = Join-Path $LogPath "GamingOptimizer_$(Get-Date -Format 'yyyy-MM-dd').log"
$script:BackupOutputFile = Join-Path $LogPath "GamingOptimizer_Backup_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"

# Initialize logging
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Console output with colors
    switch ($Level) {
        "INFO"    { Write-Host $Message -ForegroundColor White }
        "WARN"    { Write-Host $Message -ForegroundColor Yellow }
        "ERROR"   { Write-Host $Message -ForegroundColor Red }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        "DEBUG"   { Write-Host $Message -ForegroundColor Gray }
    }
    
    # File output
    try {
        Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not write to log file: $_"
    }
}

# System compatibility check
function Test-SystemCompatibility {
    Write-Log "Checking system compatibility..." "INFO"
    
    $compatible = $true
    $issues = @()
    
    # Check Windows version
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        $compatible = $false
        $issues += "Windows 10 or later required (detected: $($osVersion.ToString()))"
    }
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $compatible = $false
        $issues += "PowerShell 5.1 or later required (detected: $($PSVersionTable.PSVersion.ToString()))"
    }
    
    # Check disk space
    $systemDrive = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
    $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
    if ($freeSpaceGB -lt 1) {
        $compatible = $false
        $issues += "Insufficient disk space (available: $freeSpaceGB GB, required: 1 GB)"
    }
    
    # Check for gaming-related processes
    $gamingProcesses = Get-Process | Where-Object { 
        $_.ProcessName -match "(steam|origin|epic|battle|xbox|discord)" 
    }
    if ($gamingProcesses) {
        Write-Log "Warning: Gaming applications detected running. Consider closing them before optimization." "WARN"
    }
    
    if (-not $compatible) {
        Write-Log "System compatibility check failed:" "ERROR"
        $issues | ForEach-Object { Write-Log "  - $_" "ERROR" }
        return $false
    }
    
    Write-Log "System compatibility check passed" "SUCCESS"
    return $true
}

# Create system restore point
function New-SystemRestorePoint {
    if (-not $CreateRestorePoint) { return }
    
    Write-Log "Creating system restore point..." "INFO"
    try {
        # Enable system restore if disabled
        Enable-ComputerRestore -Drive "$env:SystemDrive"
        
        # Create restore point
        Checkpoint-Computer -Description "Gaming Performance Optimizer - Before Changes" -RestorePointType "MODIFY_SETTINGS"
        Write-Log "System restore point created successfully" "SUCCESS"
    }
    catch {
        Write-Log "Failed to create restore point: $($_.Exception.Message)" "WARN"
    }
}

# Enhanced registry backup with JSON format
function Backup-SystemState {
    Write-Log "Creating comprehensive system state backup..." "INFO"
    
    $backupData = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ScriptVersion = $script:ScriptVersion
        AutoLoggers = @{}
        Services = @{}
        RegistrySettings = @{}
        ActiveETWSessions = @()
    }
    
    try {
        Write-Log "[Backup] Enumerating ETW AutoLogger keys..." "DEBUG"
        $autoLoggerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger"
        if (Test-Path $autoLoggerPath) {
            $autoLoggerKeys = Get-ChildItem -Path $autoLoggerPath -ErrorAction SilentlyContinue
            $count = 0
            foreach ($key in $autoLoggerKeys) {
                try {
                    $startValue = Get-ItemProperty -Path $key.PSPath -Name "Start" -ErrorAction SilentlyContinue
                    if ($startValue) {
                        $backupData.AutoLoggers[$key.PSChildName] = [int]$startValue.Start
                        $count++
                    }
                } catch {
                    Write-Log "[Backup] Failed reading Start for $($key.PSChildName): $($_.Exception.Message)" "DEBUG"
                }
            }
            Write-Log "[Backup] AutoLogger entries captured: $count" "DEBUG"
        } else {
            Write-Log "[Backup] Autologger path not found" "DEBUG"
        }
        
        # Backup services
        Write-Log "[Backup] Capturing service states..." "DEBUG"
        $servicesToCheck = @("DiagTrack", "dmwappushservice", "DPS", "WerSvc", "RetailDemo")
        foreach ($svcName in $servicesToCheck) {
            $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($service) {
                $backupData.Services[$svcName] = @{
                    Status = $service.Status.ToString()
                    StartType = $service.StartType.ToString()
                }
            }
        }
        Write-Log "[Backup] Services captured: $($backupData.Services.Keys.Count)" "DEBUG"
        
        # Backup registry settings (value-only, avoid provider metadata)
        Write-Log "[Backup] Capturing registry settings..." "DEBUG"
        $regPaths = @{
            "MMCSS" = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            "Games" = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
            "DataCollection" = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        }
        foreach ($key in $regPaths.Keys) {
            $path = $regPaths[$key]
            if (Test-Path $path) {
                try {
                    $obj = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Select-Object -Property * -ExcludeProperty PS*, __*
                    $ht = @{}
                    if ($obj) {
                        $obj.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
                    }
                    $backupData.RegistrySettings[$key] = $ht
                } catch {
                    Write-Log "[Backup] Failed reading registry: $path - $($_.Exception.Message)" "DEBUG"
                }
            }
        }
        Write-Log "[Backup] Registry groups captured: $($backupData.RegistrySettings.Keys.Count)" "DEBUG"
        
        # Backup active ETW sessions
        Write-Log "[Backup] Querying active ETW sessions..." "DEBUG"
        $etwOutput = logman query -ets 2>&1
        if ($LASTEXITCODE -eq 0) {
            $backupData.ActiveETWSessions = $etwOutput | Where-Object { $_ -notmatch "^(Data Collector Set|Name|The command completed successfully)" -and $_ -ne "" }
            Write-Log "[Backup] Active ETW lines captured: $($backupData.ActiveETWSessions.Count)" "DEBUG"
        } else {
            Write-Log "[Backup] logman query -ets failed with code $LASTEXITCODE" "DEBUG"
        }
        
        # Save backup
        Write-Log "[Backup] Writing JSON to: $script:BackupOutputFile" "DEBUG"
        $json = $backupData | ConvertTo-Json -Depth 6
        Set-Content -Path $script:BackupOutputFile -Encoding UTF8 -Value $json
        Write-Log "Backup saved to: $script:BackupOutputFile" "SUCCESS"
        
        return $true
    }
    catch {
        Write-Log "Backup failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Enhanced ETW session management
function Get-ActiveETWSessions {
    try {
        $sessions = @()
        $output = logman query -ets 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $output | ForEach-Object {
                if ($_ -match "^[a-zA-Z]" -and $_ -notmatch "^(Data Collector Set|Name|The command completed successfully)") {
                    $sessionName = ($_ -split "\s+")[0]
                    if ($sessionName -and $sessionName.Length -gt 0) {
                        $sessions += $sessionName
                    }
                }
            }
        }
        
        return $sessions
    }
    catch {
        Write-Log "Failed to get ETW sessions: $($_.Exception.Message)" "ERROR"
        return @()
    }
}

# Safe ETW session termination with retry logic
function Stop-ETWSessionSafe {
    param(
        [string]$SessionName,
        [int]$MaxRetries = 3
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $result = logman stop $SessionName -ets 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Stopped ETW session: $SessionName" "SUCCESS"
                return $true
            }
            elseif ($result -match "not found") {
                Write-Log "- Session not found: $SessionName" "DEBUG"
                return $true
            }
            else {
                Write-Log "Attempt $i failed for session $SessionName : $result" "WARN"
                Start-Sleep -Seconds 2
            }
        }
        catch {
            Write-Log "Exception stopping session $SessionName (attempt $i): $($_.Exception.Message)" "WARN"
            Start-Sleep -Seconds 2
        }
    }
    
    Write-Log "Failed to stop session after $MaxRetries attempts: $SessionName" "ERROR"
    return $false
}

# Enhanced service management
function Set-ServiceStateSafe {
    param(
        [string]$ServiceName,
        [string]$DisplayName,
        [string]$StartupType,
        [string]$Action = "Stop"
    )
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Log "- Service not found: $DisplayName" "DEBUG"
            return $true
        }
        
        # Stop service if needed
        if ($Action -eq "Stop" -and $service.Status -eq "Running") {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            Write-Log "Stopped service: $DisplayName" "INFO"
        }
        
        # Set startup type
        Set-Service -Name $ServiceName -StartupType $StartupType -ErrorAction Stop
        Write-Log "Set $DisplayName startup type to: $StartupType" "SUCCESS"
        
        return $true
    }
    catch {
        Write-Log "Failed to configure service ${DisplayName}: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Main optimization function
function Invoke-GamingOptimization {
    $success = $true
    
    Write-Log "============================================" "INFO"
    Write-Log "$script:ScriptName v$script:ScriptVersion" "INFO"
    Write-Log "Starting gaming optimization process..." "INFO"
    Write-Log "============================================" "INFO"
    
    # Step 1: Show current ETW sessions
    Write-Log "`nSTEP 1: Analyzing Current ETW Sessions" "INFO"
    Write-Log "=======================================" "INFO"
    
    $activeSessions = Get-ActiveETWSessions
    Write-Log "Found $($activeSessions.Count) active ETW sessions:" "INFO"
    $activeSessions | ForEach-Object { Write-Log "  - $_" "DEBUG" }
    
    # Step 2: Disable ETW Auto Loggers
    Write-Log "`nSTEP 2: Disabling ETW Auto Loggers" "INFO"
    Write-Log "===================================" "INFO"
    
    $autoLoggersToDisable = @(
        "DiagTrack-Listener",
        "LwtNetLog", 
        "WiFiSession",
        "WdiContextLog",
        "Circular Kernel Context Logger",
        "CloudExperienceHostOobe",
        "DiagLog",
        "ReadyBoot",
        "SetupPlatform",
        "UBPM",
        "WFP-IPsec Trace",
        "Microsoft-Windows-Rdp-Graphics-RdpIdd-Trace",
        "NetCore",
        "NtfsLog",
        "RadioManager",
        "WinPhoneCritical"
    )
    
    $autoLoggerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger"
    $disabledCount = 0
    
    foreach ($logger in $autoLoggersToDisable) {
        $fullPath = "$autoLoggerPath\$logger"
        if (Test-Path $fullPath) {
            try {
                $currentValue = Get-ItemProperty -Path $fullPath -Name "Start" -ErrorAction SilentlyContinue
                if ($currentValue -and $currentValue.Start -ne 0) {
                    Set-ItemProperty -Path $fullPath -Name "Start" -Value 0 -Type DWord -ErrorAction Stop
                    Write-Log "Disabled auto logger: $logger" "SUCCESS"
                    $disabledCount++
                }
                else {
                    Write-Log "- Already disabled: $logger" "DEBUG"
                }
            }
            catch {
                Write-Log "Failed to disable: $logger - $($_.Exception.Message)" "ERROR"
                $success = $false
            }
        }
        else {
            Write-Log "- Auto logger not found: $logger" "DEBUG"
        }
    }
    
    Write-Log "Disabled $disabledCount auto loggers" "INFO"
    
    # Step 3: Stop Active ETW Sessions
    Write-Log "`nSTEP 3: Stopping Active ETW Sessions" "INFO"
    Write-Log "=====================================" "INFO"
    
    $sessionsToStop = @(
        "DiagLog",
        "DiagTrack-Listener", 
        "LwtNetLog",
        "WiFiSession",
        "WdiContextLog",
        "Circular Kernel Context Logger",
        "ReadyBoot",
        "SetupPlatform",
        "UBPM",
        "CloudExperienceHostOobe",
        "WFP-IPsec Trace",
        "Microsoft-Windows-Rdp-Graphics-RdpIdd-Trace",
        "NetCore"
    )
    
    $stoppedCount = 0
    foreach ($session in $sessionsToStop) {
        if (Stop-ETWSessionSafe -SessionName $session) {
            $stoppedCount++
        }
    }
    
    Write-Log "Processed $stoppedCount ETW sessions" "INFO"
    
    # Step 4: Configure Services
    Write-Log "`nSTEP 4: Configuring Telemetry Services" "INFO"
    Write-Log "=======================================" "INFO"
    
    $servicesToConfigure = @(
        @{Name="DiagTrack"; DisplayName="Connected User Experiences and Telemetry"; StartupType="Disabled"},
        @{Name="dmwappushservice"; DisplayName="Device Management Wireless Application Protocol"; StartupType="Disabled"},
        @{Name="DPS"; DisplayName="Diagnostic Policy Service"; StartupType="Manual"},
        @{Name="WerSvc"; DisplayName="Windows Error Reporting Service"; StartupType="Manual"},
        @{Name="RetailDemo"; DisplayName="Retail Demo Service"; StartupType="Disabled"},
        @{Name="PcaSvc"; DisplayName="Program Compatibility Assistant Service"; StartupType="Manual"},
        @{Name="SysMain"; DisplayName="Superfetch"; StartupType="Manual"}
    )
    
    $configuredCount = 0
    foreach ($svc in $servicesToConfigure) {
        if (Set-ServiceStateSafe -ServiceName $svc.Name -DisplayName $svc.DisplayName -StartupType $svc.StartupType) {
            $configuredCount++
        }
    }
    
    Write-Log "Configured $configuredCount services" "INFO"
    
    # Step 5: Apply Gaming Performance Optimizations
    Write-Log "`nSTEP 5: Applying Gaming Performance Optimizations" "INFO"
    Write-Log "==================================================" "INFO"
    
    try {
        # MMCSS optimizations
        $mmcssPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        if (Test-Path $mmcssPath) {
            Set-ItemProperty -Path $mmcssPath -Name "SystemResponsiveness" -Value 0 -Type DWord
            Set-ItemProperty -Path $mmcssPath -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord
            Write-Log "Applied MMCSS optimizations" "SUCCESS"
        }
        
        # Gaming task optimizations
        $gamesPath = "$mmcssPath\Tasks\Games"
        if (-not (Test-Path $gamesPath)) {
            New-Item -Path $gamesPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $gamesPath -Name "GPU Priority" -Value 8 -Type DWord
        Set-ItemProperty -Path $gamesPath -Name "Priority" -Value 6 -Type DWord
        Set-ItemProperty -Path $gamesPath -Name "Scheduling Category" -Value "High" -Type String
        Set-ItemProperty -Path $gamesPath -Name "SFIO Priority" -Value "High" -Type String
        Write-Log "Applied gaming task optimizations" "SUCCESS"
        
        # Additional performance settings
        $performanceSettings = @{
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" = @{
                "AllowTelemetry" = 0
                "DoNotShowFeedbackNotifications" = 1
            }
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" = @{
                "AllowTelemetry" = 0
            }
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" = @{
                "AITEnable" = 0
                "DisableInventory" = 1
            }
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" = @{
                "DisabledByGroupPolicy" = 1
            }
            "HKLM:\SYSTEM\CurrentControlSet\Control\Power" = @{
                "HibernateEnabled" = 0
            }
        }
        
        foreach ($regPath in $performanceSettings.Keys) {
            try {
                if (-not (Test-Path $regPath)) {
                    New-Item -Path $regPath -Force | Out-Null
                }
                foreach ($setting in $performanceSettings[$regPath].Keys) {
                    Set-ItemProperty -Path $regPath -Name $setting -Value $performanceSettings[$regPath][$setting] -Type DWord -ErrorAction Stop
                }
                Write-Log "Applied settings to: $($regPath.Split('\\')[-1])" "SUCCESS"
            }
            catch {
                Write-Log "Failed to apply settings to: $regPath - $($_.Exception.Message)" "ERROR"
                $success = $false
            }
        }
        
        # Timer Resolution Optimization
        try {
            $timerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
            if (Test-Path $timerPath) {
                Set-ItemProperty -Path $timerPath -Name "GlobalTimerResolutionRequests" -Value 1 -Type DWord -ErrorAction Stop
                Write-Log "Enabled high resolution timers" "SUCCESS"
            }
        }
        catch {
            Write-Log "Timer resolution optimization failed: $($_.Exception.Message)" "WARN"
        }
        
    }
    catch {
        Write-Log "Performance optimization failed: $($_.Exception.Message)" "ERROR"
        $success = $false
    }
    
    return $success
}

# Rollback function
function Invoke-GamingRollback {
    param(
        [string]$BackupFilePath
    )
    Write-Log "Starting rollback process..." "INFO"
    
    # Resolve backup file to use
    $selectedFile = $null
    if ($BackupFilePath) {
        if (Test-Path $BackupFilePath) {
            $selectedFile = (Resolve-Path $BackupFilePath).Path
        }
        else {
            Write-Log "Specified backup file not found: $BackupFilePath" "ERROR"
            return $false
        }
    }
    else {
        $pattern = "GamingOptimizer_Backup_*.json"
        $candidates = Get-ChildItem -Path $LogPath -Filter $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($candidates -and $candidates.Count -gt 0) {
            $selectedFile = $candidates[0].FullName
            Write-Log "Using latest backup: $selectedFile" "INFO"
        }
        else {
            Write-Log "No backup file found in $LogPath matching $pattern. Cannot perform rollback." "ERROR"
            return $false
        }
    }
    
    try {
        $backupData = Get-Content $selectedFile -Raw | ConvertFrom-Json
        Write-Log "Loaded backup from: $($backupData.Timestamp)" "INFO"
        
        # Restore auto loggers
        foreach ($logger in $backupData.AutoLoggers.PSObject.Properties) {
            $path = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$($logger.Name)"
            if (Test-Path $path) {
                Set-ItemProperty -Path $path -Name "Start" -Value $logger.Value -Type DWord
                Write-Log "Restored auto logger: $($logger.Name)" "SUCCESS"
            }
        }
        
        # Restore services
        foreach ($service in $backupData.Services.PSObject.Properties) {
            $svcData = $service.Value
            Set-Service -Name $service.Name -StartupType $svcData.StartType
            if ($svcData.Status -eq "Running") {
                Start-Service -Name $service.Name -ErrorAction SilentlyContinue
            }
            Write-Log "Restored service: $($service.Name)" "SUCCESS"
        }
        
        Write-Log "Rollback completed successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Rollback failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# System verification
function Test-OptimizationStatus {
    Write-Log "Verifying optimization status..." "INFO"
    
    $results = @{
        ETWSessions = 0
        DisabledServices = 0
        OptimizedSettings = 0
        Issues = @()
    }
    
    # Check ETW sessions
    $activeSessions = Get-ActiveETWSessions
    $results.ETWSessions = $activeSessions.Count
    Write-Log "Active ETW sessions: $($activeSessions.Count)" "INFO"
    
    # Check services
    $targetServices = @("DiagTrack", "dmwappushservice", "RetailDemo")
    foreach ($svcName in $targetServices) {
        $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($service -and $service.StartType -eq "Disabled") {
            $results.DisabledServices++
        }
    }
    
    # Check registry settings
    $mmcssPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (Test-Path $mmcssPath) {
        $sysResp = Get-ItemProperty -Path $mmcssPath -Name "SystemResponsiveness" -ErrorAction SilentlyContinue
        if ($sysResp -and $sysResp.SystemResponsiveness -eq 0) {
            $results.OptimizedSettings++
        }
    }
    
    Write-Log "Verification complete - Services: $($results.DisabledServices), Settings: $($results.OptimizedSettings)" "INFO"
    return $results
}

# Main execution
function Main {
    try {
        # Initialize
        if (-not (Test-Path $LogPath)) {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
        }
        
        Write-Log "Starting $script:ScriptName v$script:ScriptVersion in $Mode mode" "INFO"
        Write-Log "Log file: $script:LogFile" "INFO"
        
        # System compatibility check
        if (-not (Test-SystemCompatibility)) {
            return 1
        }
        
        # Mode-specific execution
        switch ($Mode) {
            "Apply" {
                if (-not $Force) {
                    $confirmation = Read-Host "This will modify system settings. Continue? (y/N)"
                    if ($confirmation -notmatch '^[Yy]') {
                        Write-Log "Operation cancelled by user" "INFO"
                        return 0
                    }
                }
                
                # Create restore point if requested
                New-SystemRestorePoint
                
                # Create backup
                if (-not $SkipBackup) {
                    if (-not (Backup-SystemState)) {
                        Write-Log "Backup failed. Aborting for safety." "ERROR"
                        return 1
                    }
                } else {
                    Write-Log "Skipping backup at user request (-SkipBackup)." "WARN"
                }
                
                # Apply optimizations
                $success = Invoke-GamingOptimization
                
                if ($success) {
                    Write-Log "`nOptimization completed successfully!" "SUCCESS"
                    Write-Log "Restart required for all changes to take effect." "WARN"
                    
                    if (-not $Force) {
                        $restart = Read-Host "`nRestart now? (y/N)"
                        if ($restart -match '^[Yy]') {
                            Restart-Computer -Force
                        }
                    }
                }
                else {
                    Write-Log "Optimization completed with some errors. Check log for details." "WARN"
                    return 1
                }
            }
            
            "Rollback" {
                $success = Invoke-GamingRollback -BackupFilePath $BackupFile
                if ($success) { return 0 } else { return 1 }
            }
            
            "Verify" {
                $results = Test-OptimizationStatus
                Write-Log "Verification results:" "INFO"
                Write-Log "  Active ETW Sessions: $($results.ETWSessions)" "INFO"
                Write-Log "  Disabled Services: $($results.DisabledServices)" "INFO"
                Write-Log "  Optimized Settings: $($results.OptimizedSettings)" "INFO"
            }
        }
        
        return 0
    }
    catch {
        Write-Log "Critical error: $($_.Exception.Message)" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "DEBUG"
        return 1
    }
}

# Execute main function
$exitCode = Main
exit $exitCode
