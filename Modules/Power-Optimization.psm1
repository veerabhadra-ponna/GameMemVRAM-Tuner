# Power-Optimization.psm1 - Power and mouse precision optimizations for GameMemVRAM-Tuner Ultimate

# ========================= POWER PLAN MANAGEMENT =========================
function Enable-UltimatePerformance {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Configuring Ultimate Performance power plan" -Level Info -Category "Power"
    
    try {
        # Check if Ultimate Performance plan already exists
        $ultimatePlan = Get-WmiObject -Class Win32_PowerPlan -Namespace "root\cimv2\power" | 
                       Where-Object { $_.ElementName -eq "Ultimate Performance" }
        
        if (-not $ultimatePlan) {
            if ($WhatIf) {
                Write-Log "[PREVIEW] Would create Ultimate Performance power plan" -Level Info -Category "Power"
            }
            else {
                # Create Ultimate Performance power plan
                $result = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Created Ultimate Performance power plan" -Level Info -Category "Power"
                }
                else {
                    Write-Log "Failed to create Ultimate Performance power plan: $result" -Level Warn -Category "Power"
                    # Try to enable the existing hidden plan
                    $enableResult = powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Enabled existing Ultimate Performance power plan" -Level Info -Category "Power"
                    }
                    else {
                        throw "Failed to enable Ultimate Performance power plan: $enableResult"
                    }
                }
            }
        }
        
        # Set as active power plan
        if ($WhatIf) {
            $currentPlan = Get-WmiObject -Class Win32_PowerPlan -Namespace "root\cimv2\power" | 
                          Where-Object { $_.IsActive -eq $true }
            Write-Log "[PREVIEW] Current power plan: $($currentPlan.ElementName)" -Level Info -Category "Power"
            Write-Log "[PREVIEW] Would activate Ultimate Performance power plan" -Level Info -Category "Power"
        }
        else {
            # Get the Ultimate Performance plan GUID
            $plans = powercfg /list | Select-String "Ultimate Performance"
            if ($plans) {
                $planGuid = ($plans[0] -split ":")[0].Trim() -replace ".*\(([^)]+)\).*", '$1'
                $activateResult = powercfg /setactive $planGuid 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Activated Ultimate Performance power plan" -Level Info -Category "Power"
                }
                else {
                    Write-Log "Failed to activate Ultimate Performance plan: $activateResult" -Level Warn -Category "Power"
                }
            }
        }
        
        return $true
        
    } catch {
        Write-Log "Failed to configure Ultimate Performance power plan: $($_.Exception.Message)" -Level Error -Category "Power"
        return $false
    }
}

function Optimize-PowerSettings {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Optimizing power settings for gaming performance" -Level Info -Category "Power"
    
    $powerSettings = @{
        # USB selective suspend
        "SUB_2A737441-1930-4402-8D77-B2BEBBA308A3\48E6B7A6-50F5-4782-A5D4-53BB8F07E226" = @{
            Name = "USB selective suspend"
            Value = 0
            Description = "Disable USB selective suspend for consistent peripheral performance"
        }
        
        # PCI Express Link State Power Management
        "SUB_501A4D13-42AF-4429-9FD1-A8218C268E20\EE12F906-D277-404B-B6DA-E5FA1A576DF5" = @{
            Name = "PCI Express Link State Power Management"
            Value = 0
            Description = "Disable PCIe power management for consistent GPU/storage performance"
        }
        
        # Processor power management - Minimum processor state
        "SUB_54533251-82BE-4824-96C1-47B60B740D00\893DEE8E-2BEF-41E0-89C6-B55D0929964C" = @{
            Name = "Minimum processor state"
            Value = 100
            Description = "Set minimum CPU state to 100% for consistent performance"
        }
        
        # Processor power management - Maximum processor state
        "SUB_54533251-82BE-4824-96C1-47B60B740D00\BC5038F7-23E0-4960-96DA-33ABAF5935EC" = @{
            Name = "Maximum processor state"
            Value = 100
            Description = "Set maximum CPU state to 100%"
        }
        
        # System cooling policy
        "SUB_54533251-82BE-4824-96C1-47B60B740D00\94D3A615-A899-4AC5-AE2B-E4D8F634367F" = @{
            Name = "System cooling policy"
            Value = 0
            Description = "Set cooling policy to Active for better thermal management"
        }
        
        # Hard disk - Turn off hard disk after
        "SUB_0012EE47-9041-4B5D-9B77-535FBA8B1442\6738E2C4-E8A5-4A42-B16A-E040E769756E" = @{
            Name = "Turn off hard disk after"
            Value = 0
            Description = "Never turn off hard disks for consistent storage performance"
        }
        
        # Display - Turn off display after
        "SUB_7516B95F-F776-4464-8C53-06167F40CC99\3C0BC021-C8A8-4E07-A973-6B14CBCB2B7E" = @{
            Name = "Turn off display after"
            Value = 0
            Description = "Never turn off display when gaming"
        }
    }
    
    $appliedCount = 0
    foreach ($settingGuid in $powerSettings.Keys) {
        $setting = $powerSettings[$settingGuid]
        
        try {
            if ($WhatIf) {
                Write-Log "[PREVIEW] Would set power setting: $($setting.Name) = $($setting.Value) - $($setting.Description)" -Level Info -Category "Power"
            }
            else {
                # Apply power setting using powercfg
                $result = powercfg /setacvalueindex SCHEME_CURRENT $settingGuid $setting.Value 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $result2 = powercfg /setdcvalueindex SCHEME_CURRENT $settingGuid $setting.Value 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Applied power setting: $($setting.Name) - $($setting.Description)" -Level Info -Category "Power"
                        $appliedCount++
                    }
                    else {
                        Write-Log "Failed to set DC value for $($setting.Name): $result2" -Level Warn -Category "Power"
                    }
                }
                else {
                    Write-Log "Failed to set AC value for $($setting.Name): $result" -Level Warn -Category "Power"
                }
            }
        }
        catch {
            Write-Log "Error applying power setting $($setting.Name): $($_.Exception.Message)" -Level Error -Category "Power"
        }
    }
    
    # Apply the settings
    if (-not $WhatIf -and $appliedCount -gt 0) {
        $applyResult = powercfg /setactive SCHEME_CURRENT 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Power settings applied successfully" -Level Info -Category "Power"
        }
        else {
            Write-Log "Failed to apply power settings: $applyResult" -Level Warn -Category "Power"
        }
    }
    
    Write-Log "Power settings optimization completed: $appliedCount settings applied" -Level Info -Category "Power"
    return $appliedCount -gt 0
}

# ========================= MOUSE PRECISION OPTIMIZATION =========================
function Disable-MouseAcceleration {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Disabling mouse acceleration for precise gaming input" -Level Info -Category "Mouse"
    
    $mouseSettings = @{
        "HKCU:\Control Panel\Mouse" = @{
            "MouseAcceleration" = @{ Value = "0"; Type = "String"; Description = "Disable mouse acceleration" }
            "MouseSpeed" = @{ Value = "0"; Type = "String"; Description = "Set mouse speed to default" }
            "MouseThreshold1" = @{ Value = "0"; Type = "String"; Description = "Disable mouse threshold 1" }
            "MouseThreshold2" = @{ Value = "0"; Type = "String"; Description = "Disable mouse threshold 2" }
        }
        "HKU:\.DEFAULT\Control Panel\Mouse" = @{
            "MouseAcceleration" = @{ Value = "0"; Type = "String"; Description = "Disable mouse acceleration (default user)" }
            "MouseSpeed" = @{ Value = "0"; Type = "String"; Description = "Set mouse speed to default (default user)" }
            "MouseThreshold1" = @{ Value = "0"; Type = "String"; Description = "Disable mouse threshold 1 (default user)" }
            "MouseThreshold2" = @{ Value = "0"; Type = "String"; Description = "Disable mouse threshold 2 (default user)" }
        }
    }
    
    $appliedCount = 0
    foreach ($regPath in $mouseSettings.Keys) {
        foreach ($settingName in $mouseSettings[$regPath].Keys) {
            $setting = $mouseSettings[$regPath][$settingName]
            
            try {
                # Skip HKU\.DEFAULT if not accessible
                if ($regPath -match "HKU:" -and -not (Test-Path $regPath)) {
                    Write-Log "Skipping inaccessible registry path: $regPath" -Level Debug -Category "Mouse"
                    continue
                }
                
                # Backup current value
                Backup-RegistryValue -Path $regPath -Name $settingName -Description $setting.Description
                
                if ($WhatIf) {
                    Write-Log "[PREVIEW] Would set $regPath\$settingName = $($setting.Value) - $($setting.Description)" -Level Info -Category "Mouse"
                }
                else {
                    $success = Set-RegistryValue -Path $regPath -Name $settingName -Value $setting.Value -Type $setting.Type -Description $setting.Description
                    if ($success) {
                        Write-Log "Applied mouse setting: $settingName - $($setting.Description)" -Level Info -Category "Mouse"
                        $appliedCount++
                    }
                }
            }
            catch {
                Write-Log "Failed to apply mouse setting $regPath\$settingName : $($_.Exception.Message)" -Level Error -Category "Mouse"
            }
        }
    }
    
    Write-Log "Mouse acceleration disable completed: $appliedCount settings applied" -Level Info -Category "Mouse"
    return $appliedCount -gt 0
}

function Optimize-MouseSettings {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Optimizing advanced mouse settings for gaming" -Level Info -Category "Mouse"
    
    # Additional mouse optimizations
    $advancedMouseSettings = @{
        "HKCU:\Control Panel\Desktop" = @{
            "MenuShowDelay" = @{ Value = 0; Type = "DWord"; Description = "Remove menu show delay for faster navigation" }
        }
        "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters" = @{
            "MouseDataQueueSize" = @{ Value = 100; Type = "DWord"; Description = "Increase mouse data queue size for better responsiveness" }
        }
        "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters" = @{
            "KeyboardDataQueueSize" = @{ Value = 100; Type = "DWord"; Description = "Increase keyboard data queue size for better responsiveness" }
        }
    }
    
    $appliedCount = 0
    foreach ($regPath in $advancedMouseSettings.Keys) {
        foreach ($settingName in $advancedMouseSettings[$regPath].Keys) {
            $setting = $advancedMouseSettings[$regPath][$settingName]
            
            try {
                # Backup current value
                Backup-RegistryValue -Path $regPath -Name $settingName -Description $setting.Description
                
                if ($WhatIf) {
                    Write-Log "[PREVIEW] Would set $regPath\$settingName = $($setting.Value) - $($setting.Description)" -Level Info -Category "Mouse"
                }
                else {
                    $success = Set-RegistryValue -Path $regPath -Name $settingName -Value $setting.Value -Type $setting.Type -Description $setting.Description
                    if ($success) {
                        Write-Log "Applied advanced mouse setting: $settingName - $($setting.Description)" -Level Info -Category "Mouse"
                        $appliedCount++
                    }
                }
            }
            catch {
                Write-Log "Failed to apply advanced mouse setting $regPath\$settingName : $($_.Exception.Message)" -Level Error -Category "Mouse"
            }
        }
    }
    
    Write-Log "Advanced mouse settings optimization completed: $appliedCount settings applied" -Level Info -Category "Mouse"
    return $appliedCount -gt 0
}

# ========================= STATUS AND REPORTING =========================
function Get-PowerOptimizationStatus {
    Write-Log "Checking power and mouse optimization status" -Level Info -Category "Power"
    
    $status = @{
        UltimatePerformanceActive = $false
        CurrentPowerPlan = "Unknown"
        MouseAccelerationDisabled = $false
        PowerSettingsOptimized = $false
        USBSelectiveSuspendDisabled = $false
    }
    
    try {
        # Check current power plan
        $currentPlan = Get-WmiObject -Class Win32_PowerPlan -Namespace "root\cimv2\power" | 
                      Where-Object { $_.IsActive -eq $true }
        if ($currentPlan) {
            $status.CurrentPowerPlan = $currentPlan.ElementName
            $status.UltimatePerformanceActive = $currentPlan.ElementName -eq "Ultimate Performance"
        }
        
        # Check mouse acceleration
        $mouseAccel = Get-RegistryValue -Path "HKCU:\Control Panel\Mouse" -Name "MouseAcceleration" -DefaultValue "1"
        $status.MouseAccelerationDisabled = $mouseAccel -eq "0"
        
        # Check some key power settings (simplified check)
        $usbSuspend = Get-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\USB" -Name "DisableSelectiveSuspend" -DefaultValue 0
        $status.USBSelectiveSuspendDisabled = $usbSuspend -eq 1
        
        # Rough check for power settings optimization
        $status.PowerSettingsOptimized = $status.UltimatePerformanceActive
        
    } catch {
        Write-Log "Error checking power optimization status: $($_.Exception.Message)" -Level Error -Category "Power"
    }
    
    return $status
}

function Show-PowerOptimizationReport {
    $status = Get-PowerOptimizationStatus
    
    Write-Host ""
    Write-Host "? Power & Mouse Optimization Status:" -ForegroundColor Yellow
    Write-Host ""
    
    # Power Plan Status
    $planColor = if ($status.UltimatePerformanceActive) { "Green" } else { "Red" }
    $planStatus = if ($status.UltimatePerformanceActive) { "? Ultimate Performance" } else { "? $($status.CurrentPowerPlan)" }
    Write-Host "  Active Power Plan:             $planStatus" -ForegroundColor $planColor
    
    # Mouse Settings
    $mouseColor = if ($status.MouseAccelerationDisabled) { "Green" } else { "Red" }
    $mouseStatus = if ($status.MouseAccelerationDisabled) { "? Disabled" } else { "? Enabled" }
    Write-Host "  Mouse Acceleration:            $mouseStatus" -ForegroundColor $mouseColor
    
    # Power Settings
    $powerColor = if ($status.PowerSettingsOptimized) { "Green" } else { "Red" }
    $powerStatus = if ($status.PowerSettingsOptimized) { "? Optimized" } else { "? Not Optimized" }
    Write-Host "  Power Settings:                $powerStatus" -ForegroundColor $powerColor
    
    $optimizations = @($status.UltimatePerformanceActive, $status.MouseAccelerationDisabled, $status.PowerSettingsOptimized)
    $optimizedCount = ($optimizations | Where-Object { $_ }).Count
    $totalCount = $optimizations.Count
    $optimizationPercent = [math]::Round(($optimizedCount / $totalCount) * 100)
    
    Write-Host ""
    Write-Host "  Overall Power Optimization: $optimizedCount/$totalCount ($optimizationPercent%)" -ForegroundColor Cyan
    
    if ($optimizationPercent -lt 100) {
        Write-Host "  ?? Enable power optimizations for better gaming performance and input precision" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "  Benefits of Power Optimization:" -ForegroundColor DarkCyan
    Write-Host "    • Consistent CPU/GPU performance without throttling" -ForegroundColor DarkGray
    Write-Host "    • Reduced input latency and better mouse precision" -ForegroundColor DarkGray
    Write-Host "    • Eliminated USB device disconnect issues" -ForegroundColor DarkGray
    Write-Host "    • Faster storage access without power-saving delays" -ForegroundColor DarkGray
}

# Export module functions
Export-ModuleMember -Function @(
    'Enable-UltimatePerformance',
    'Optimize-PowerSettings',
    'Disable-MouseAcceleration',
    'Optimize-MouseSettings',
    'Get-PowerOptimizationStatus',
    'Show-PowerOptimizationReport'
)