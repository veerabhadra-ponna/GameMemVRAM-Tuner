# ETW-Cleanup.psm1 - ETW logging and telemetry cleanup for GameMemVRAM-Tuner Ultimate

# ========================= ETW SESSION MANAGEMENT =========================
function Get-ActiveETWSessions {
    Write-Log "Enumerating active ETW sessions" -Level Debug -Category "ETW"
    
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
        else {
            Write-Log "logman query failed with exit code $LASTEXITCODE" -Level Warn -Category "ETW"
        }
        
        Write-Log "Found $($sessions.Count) active ETW sessions" -Level Info -Category "ETW"
        return $sessions
        
    } catch {
        Write-Log "Failed to get ETW sessions: $($_.Exception.Message)" -Level Error -Category "ETW"
        return @()
    }
}

function Stop-ETWSessionSafe {
    param(
        [Parameter(Mandatory)]
        [string]$SessionName,
        
        [Parameter()]
        [int]$MaxRetries = 3,
        
        [Parameter()]
        [switch]$WhatIf
    )
    
    if ($WhatIf) {
        Write-Log "[PREVIEW] Would stop ETW session: $SessionName" -Level Info -Category "ETW"
        return $true
    }
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $result = logman stop $SessionName -ets 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Stopped ETW session: $SessionName" -Level Info -Category "ETW"
                return $true
            }
            elseif ($result -match "not found|does not exist") {
                Write-Log "ETW session not found: $SessionName" -Level Debug -Category "ETW"
                return $true
            }
            else {
                Write-Log "Attempt $i failed for session $SessionName : $result" -Level Warn -Category "ETW"
                if ($i -lt $MaxRetries) {
                    Start-Sleep -Seconds 2
                }
            }
        }
        catch {
            Write-Log "Exception stopping session $SessionName (attempt $i): $($_.Exception.Message)" -Level Warn -Category "ETW"
            if ($i -lt $MaxRetries) {
                Start-Sleep -Seconds 2
            }
        }
    }
    
    Write-Log "Failed to stop session after $MaxRetries attempts: $SessionName" -Level Error -Category "ETW"
    return $false
}

function Disable-ETWLogging {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Disabling unnecessary ETW logging for gaming performance" -Level Info -Category "ETW"
    
    # Get current active sessions for reference
    $activeSessions = Get-ActiveETWSessions
    Write-Log "Current active ETW sessions: $($activeSessions.Count)" -Level Info -Category "ETW"
    
    # Sessions to stop (known performance impacting sessions)
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
        "NetCore",
        "NtfsLog",
        "RadioManager"
    )
    
    $stoppedCount = 0
    foreach ($session in $sessionsToStop) {
        if (Stop-ETWSessionSafe -SessionName $session -WhatIf:$WhatIf) {
            $stoppedCount++
        }
    }
    
    Write-Log "ETW session cleanup completed: $stoppedCount sessions processed" -Level Info -Category "ETW"
    return $stoppedCount -gt 0
}

function Cleanup-AutoLoggers {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Disabling ETW AutoLogger registry entries" -Level Info -Category "ETW"
    
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
        "WinPhoneCritical",
        "AppModel",
        "BackgroundTransfer",
        "BrokerInfrastructure",
        "Cellcore",
        "DefenderApiLogger",
        "DefenderAuditLogger",
        "DiagLog",
        "EventLog-Application",
        "EventLog-System",
        "LUAFacilities",
        "Microsoft-Windows-PushNotification-Platform-Connection",
        "Microsoft-Windows-PushNotification-Platform-Notification",
        "WdiContextLog"
    )
    
    $autoLoggerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger"
    $disabledCount = 0
    
    if (-not (Test-Path $autoLoggerPath)) {
        Write-Log "AutoLogger registry path not found: $autoLoggerPath" -Level Warn -Category "ETW"
        return $false
    }
    
    foreach ($logger in $autoLoggersToDisable) {
        $fullPath = "$autoLoggerPath\$logger"
        
        if (Test-Path $fullPath) {
            try {
                # Backup current value
                Backup-RegistryValue -Path $fullPath -Name "Start" -Description "ETW AutoLogger start setting"
                
                $currentValue = Get-RegistryValue -Path $fullPath -Name "Start" -DefaultValue 1
                
                if ($currentValue -ne 0) {
                    if ($WhatIf) {
                        Write-Log "[PREVIEW] Would disable AutoLogger: $logger (current: $currentValue)" -Level Info -Category "ETW"
                    }
                    else {
                        $success = Set-RegistryValue -Path $fullPath -Name "Start" -Value 0 -Type "DWord" -Description "Disabled ETW AutoLogger"
                        if ($success) {
                            Write-Log "Disabled AutoLogger: $logger" -Level Info -Category "ETW"
                            $disabledCount++
                        }
                    }
                }
                else {
                    Write-Log "AutoLogger already disabled: $logger" -Level Debug -Category "ETW"
                }
            }
            catch {
                Write-Log "Failed to disable AutoLogger $logger : $($_.Exception.Message)" -Level Error -Category "ETW"
            }
        }
        else {
            Write-Log "AutoLogger not found: $logger" -Level Debug -Category "ETW"
        }
    }
    
    Write-Log "AutoLogger cleanup completed: $disabledCount AutoLoggers disabled" -Level Info -Category "ETW"
    return $disabledCount -gt 0
}

function Stop-TelemetryServices {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Configuring telemetry and diagnostic services" -Level Info -Category "ETW"
    
    $servicesToConfigure = @(
        @{
            Name = "DiagTrack"
            DisplayName = "Connected User Experiences and Telemetry"
            StartupType = "Disabled"
            StopService = $true
            Impact = "Disables Windows telemetry collection"
        },
        @{
            Name = "dmwappushservice"
            DisplayName = "Device Management Wireless Application Protocol"
            StartupType = "Disabled"
            StopService = $true
            Impact = "Disables wireless push notifications"
        },
        @{
            Name = "DPS"
            DisplayName = "Diagnostic Policy Service"
            StartupType = "Manual"
            StopService = $false
            Impact = "Reduces automatic diagnostic activities"
        },
        @{
            Name = "WerSvc"
            DisplayName = "Windows Error Reporting Service"
            StartupType = "Manual"
            StopService = $false
            Impact = "Reduces error reporting overhead"
        },
        @{
            Name = "RetailDemo"
            DisplayName = "Retail Demo Service"
            StartupType = "Disabled"
            StopService = $true
            Impact = "Disables retail demo features"
        },
        @{
            Name = "PcaSvc"
            DisplayName = "Program Compatibility Assistant Service"
            StartupType = "Manual"
            StopService = $false
            Impact = "Reduces compatibility checking overhead"
        },
        @{
            Name = "WSearch"
            DisplayName = "Windows Search"
            StartupType = "Manual"
            StopService = $false
            Impact = "Reduces indexing during gaming"
        }
    )
    
    $configuredCount = 0
    foreach ($svc in $servicesToConfigure) {
        try {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if (-not $service) {
                Write-Log "Service not found: $($svc.DisplayName)" -Level Debug -Category "ETW"
                continue
            }
            
            # Backup current service state
            Backup-ServiceState -ServiceName $svc.Name
            
            if ($WhatIf) {
                Write-Log "[PREVIEW] Would configure $($svc.DisplayName): $($svc.StartupType) - $($svc.Impact)" -Level Info -Category "ETW"
                if ($svc.StopService -and $service.Status -eq "Running") {
                    Write-Log "[PREVIEW] Would stop service: $($svc.DisplayName)" -Level Info -Category "ETW"
                }
            }
            else {
                # Stop service if needed and requested
                if ($svc.StopService -and $service.Status -eq "Running") {
                    try {
                        Stop-Service -Name $svc.Name -Force -ErrorAction Stop
                        Write-Log "Stopped service: $($svc.DisplayName)" -Level Info -Category "ETW"
                    }
                    catch {
                        Write-Log "Failed to stop service $($svc.DisplayName): $($_.Exception.Message)" -Level Warn -Category "ETW"
                    }
                }
                
                # Set startup type
                try {
                    Set-Service -Name $svc.Name -StartupType $svc.StartupType -ErrorAction Stop
                    Write-Log "Configured $($svc.DisplayName): $($svc.StartupType) - $($svc.Impact)" -Level Info -Category "ETW"
                    $configuredCount++
                }
                catch {
                    Write-Log "Failed to configure service $($svc.DisplayName): $($_.Exception.Message)" -Level Error -Category "ETW"
                }
            }
        }
        catch {
            Write-Log "Error processing service $($svc.Name): $($_.Exception.Message)" -Level Error -Category "ETW"
        }
    }
    
    Write-Log "Telemetry services configuration completed: $configuredCount services configured" -Level Info -Category "ETW"
    return $configuredCount -gt 0
}

function Disable-WindowsTelemetry {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Disabling Windows telemetry and data collection" -Level Info -Category "ETW"
    
    $telemetrySettings = @{
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" = @{
            "AllowTelemetry" = @{ Value = 0; Type = "DWord"; Description = "Disable telemetry data collection" }
            "DoNotShowFeedbackNotifications" = @{ Value = 1; Type = "DWord"; Description = "Disable feedback notifications" }
            "AllowDeviceNameInTelemetry" = @{ Value = 0; Type = "DWord"; Description = "Don't include device name in telemetry" }
        }
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" = @{
            "AllowTelemetry" = @{ Value = 0; Type = "DWord"; Description = "Disable telemetry (policy override)" }
            "MaxTelemetryAllowed" = @{ Value = 0; Type = "DWord"; Description = "Maximum telemetry level: Security only" }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat" = @{
            "AITEnable" = @{ Value = 0; Type = "DWord"; Description = "Disable Application Impact Telemetry" }
            "DisableInventory" = @{ Value = 1; Type = "DWord"; Description = "Disable application inventory" }
            "DisableUAR" = @{ Value = 1; Type = "DWord"; Description = "Disable User Activity Reporting" }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" = @{
            "DisabledByGroupPolicy" = @{ Value = 1; Type = "DWord"; Description = "Disable advertising ID tracking" }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" = @{
            "DisableWindowsConsumerFeatures" = @{ Value = 1; Type = "DWord"; Description = "Disable consumer features and ads" }
            "DisableThirdPartySuggestions" = @{ Value = 1; Type = "DWord"; Description = "Disable third-party suggestions" }
        }
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" = @{
            "TailoredExperiencesWithDiagnosticDataEnabled" = @{ Value = 0; Type = "DWord"; Description = "Disable tailored experiences" }
        }
    }
    
    $appliedCount = 0
    foreach ($regPath in $telemetrySettings.Keys) {
        try {
            foreach ($settingName in $telemetrySettings[$regPath].Keys) {
                $setting = $telemetrySettings[$regPath][$settingName]
                
                # Backup current value
                Backup-RegistryValue -Path $regPath -Name $settingName -Description $setting.Description
                
                if ($WhatIf) {
                    Write-Log "[PREVIEW] Would set $regPath\$settingName = $($setting.Value) - $($setting.Description)" -Level Info -Category "ETW"
                }
                else {
                    $success = Set-RegistryValue -Path $regPath -Name $settingName -Value $setting.Value -Type $setting.Type -Description $setting.Description
                    if ($success) {
                        Write-Log "Applied telemetry setting: $settingName - $($setting.Description)" -Level Info -Category "ETW"
                        $appliedCount++
                    }
                }
            }
        }
        catch {
            Write-Log "Failed to apply telemetry settings to $regPath : $($_.Exception.Message)" -Level Error -Category "ETW"
        }
    }
    
    Write-Log "Windows telemetry configuration completed: $appliedCount settings applied" -Level Info -Category "ETW"
    return $appliedCount -gt 0
}

function Optimize-SystemPerformanceSettings {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Applying additional system performance optimizations" -Level Info -Category "ETW"
    
    $performanceSettings = @{
        # Multimedia Class Scheduler Service optimizations
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" = @{
            "SystemResponsiveness" = @{ Value = 0; Type = "DWord"; Description = "Minimize system responsiveness delay for games" }
            "NetworkThrottlingIndex" = @{ Value = 0xffffffff; Type = "DWord"; Description = "Disable network throttling" }
        }
        
        # Gaming task optimizations
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" = @{
            "GPU Priority" = @{ Value = 8; Type = "DWord"; Description = "High GPU priority for games" }
            "Priority" = @{ Value = 6; Type = "DWord"; Description = "High CPU priority for games" }
            "Scheduling Category" = @{ Value = "High"; Type = "String"; Description = "High priority scheduling category" }
            "SFIO Priority" = @{ Value = "High"; Type = "String"; Description = "High storage I/O priority" }
        }
        
        # Timer resolution optimization
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" = @{
            "GlobalTimerResolutionRequests" = @{ Value = 1; Type = "DWord"; Description = "Allow high resolution timer requests" }
        }
        
        # Power management optimization
        "HKLM:\SYSTEM\CurrentControlSet\Control\Power" = @{
            "HibernateEnabled" = @{ Value = 0; Type = "DWord"; Description = "Disable hibernation for faster shutdown/startup" }
        }
    }
    
    $appliedCount = 0
    foreach ($regPath in $performanceSettings.Keys) {
        foreach ($settingName in $performanceSettings[$regPath].Keys) {
            $setting = $performanceSettings[$regPath][$settingName]
            
            try {
                # Backup current value
                Backup-RegistryValue -Path $regPath -Name $settingName -Description $setting.Description
                
                if ($WhatIf) {
                    Write-Log "[PREVIEW] Would set $regPath\$settingName = $($setting.Value) - $($setting.Description)" -Level Info -Category "ETW"
                }
                else {
                    $success = Set-RegistryValue -Path $regPath -Name $settingName -Value $setting.Value -Type $setting.Type -Description $setting.Description
                    if ($success) {
                        Write-Log "Applied performance setting: $settingName - $($setting.Description)" -Level Info -Category "ETW"
                        $appliedCount++
                    }
                }
            }
            catch {
                Write-Log "Failed to apply setting $regPath\$settingName : $($_.Exception.Message)" -Level Error -Category "ETW"
            }
        }
    }
    
    Write-Log "System performance settings optimization completed: $appliedCount settings applied" -Level Info -Category "ETW"
    return $appliedCount -gt 0
}

function Get-ETWOptimizationStatus {
    Write-Log "Checking ETW and telemetry optimization status" -Level Info -Category "ETW"
    
    $status = @{
        ActiveETWSessions = 0
        DisabledAutoLoggers = 0
        TelemetryDisabled = $false
        ServicesOptimized = 0
        PerformanceOptimized = $false
    }
    
    # Check active ETW sessions
    $activeSessions = Get-ActiveETWSessions
    $status.ActiveETWSessions = $activeSessions.Count
    
    # Check disabled AutoLoggers
    $autoLoggerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger"
    if (Test-Path $autoLoggerPath) {
        $autoLoggers = Get-ChildItem -Path $autoLoggerPath -ErrorAction SilentlyContinue
        $disabledLoggers = 0
        foreach ($logger in $autoLoggers) {
            $startValue = Get-RegistryValue -Path $logger.PSPath -Name "Start" -DefaultValue 1
            if ($startValue -eq 0) {
                $disabledLoggers++
            }
        }
        $status.DisabledAutoLoggers = $disabledLoggers
    }
    
    # Check telemetry settings
    $telemetryValue = Get-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -DefaultValue 3
    $status.TelemetryDisabled = $telemetryValue -eq 0
    
    # Check service configurations
    $targetServices = @("DiagTrack", "dmwappushservice", "RetailDemo")
    $optimizedServices = 0
    foreach ($svcName in $targetServices) {
        $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($service -and $service.StartType -eq "Disabled") {
            $optimizedServices++
        }
    }
    $status.ServicesOptimized = $optimizedServices
    
    # Check performance settings
    $sysResp = Get-RegistryValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "SystemResponsiveness" -DefaultValue 20
    $status.PerformanceOptimized = $sysResp -eq 0
    
    return $status
}

function Show-ETWOptimizationReport {
    $status = Get-ETWOptimizationStatus
    
    Write-Host ""
    Write-Host "??? ETW & Telemetry Cleanup Status:" -ForegroundColor Yellow
    Write-Host ""
    
    $optimizations = @(
        @{ Name = "Active ETW Sessions"; Value = $status.ActiveETWSessions; Good = $status.ActiveETWSessions -lt 10; Unit = "sessions" },
        @{ Name = "Disabled AutoLoggers"; Value = $status.DisabledAutoLoggers; Good = $status.DisabledAutoLoggers -gt 5; Unit = "loggers" },
        @{ Name = "Telemetry Disabled"; Value = $status.TelemetryDisabled; Good = $status.TelemetryDisabled; Unit = "" },
        @{ Name = "Services Optimized"; Value = $status.ServicesOptimized; Good = $status.ServicesOptimized -ge 2; Unit = "services" },
        @{ Name = "Performance Settings"; Value = $status.PerformanceOptimized; Good = $status.PerformanceOptimized; Unit = "" }
    )
    
    foreach ($opt in $optimizations) {
        $statusText = if ($opt.Good) { "? Optimized" } else { "? Not Optimized" }
        $color = if ($opt.Good) { "Green" } else { "Red" }
        
        $valueText = if ($opt.Value -is [bool]) {
            if ($opt.Value) { "Yes" } else { "No" }
        } else {
            "$($opt.Value) $($opt.Unit)".Trim()
        }
        
        Write-Host "  $($opt.Name.PadRight(25)): $statusText ($valueText)" -ForegroundColor $color
    }
    
    $optimizedCount = ($optimizations | Where-Object { $_.Good }).Count
    $totalCount = $optimizations.Count
    $optimizationPercent = [math]::Round(($optimizedCount / $totalCount) * 100)
    
    Write-Host ""
    Write-Host "  Overall ETW Optimization: $optimizedCount/$totalCount ($optimizationPercent%)" -ForegroundColor Cyan
    
    if ($optimizationPercent -lt 100) {
        Write-Host "  ?? Run ETW cleanup to reduce system overhead and improve gaming performance" -ForegroundColor Yellow
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Get-ActiveETWSessions',
    'Stop-ETWSessionSafe',
    'Disable-ETWLogging',
    'Cleanup-AutoLoggers', 
    'Stop-TelemetryServices',
    'Disable-WindowsTelemetry',
    'Optimize-SystemPerformanceSettings',
    'Get-ETWOptimizationStatus',
    'Show-ETWOptimizationReport'
)