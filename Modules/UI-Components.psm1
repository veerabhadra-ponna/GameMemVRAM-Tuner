# UI-Components.psm1 - User interface components for GameMemVRAM-Tuner Ultimate

# ========================= SYSTEM REPORT FUNCTIONS =========================
function Show-SystemReport {
    Write-Log "Generating comprehensive system report" -Level Info -Category "UI"
    
    Clear-Host
    Write-Host @"
????????????????????????????????????????????????????????????????????
?                    SYSTEM OPTIMIZATION REPORT                   ?
????????????????????????????????????????????????????????????????????
"@ -ForegroundColor Cyan
    
    # Get comprehensive hardware information
    $hardwareInfo = Get-ComprehensiveHardwareInfo
    
    # System Information Section
    Write-Host ""
    Write-Host "?? System Information:" -ForegroundColor Yellow
    Write-Host "  Computer Name: $($hardwareInfo.System.ComputerName)" -ForegroundColor White
    Write-Host "  Operating System: $($hardwareInfo.System.OSVersion)" -ForegroundColor White
    Write-Host "  PowerShell Version: $($hardwareInfo.System.PSVersion)" -ForegroundColor White
    Write-Host "  Architecture: $(if ($hardwareInfo.System.Is64Bit) { '64-bit' } else { '32-bit' })" -ForegroundColor White
    
    # Hardware Information Section
    if ($hardwareInfo.CPU) {
        Write-Host ""
        Write-Host "?? Hardware Configuration:" -ForegroundColor Yellow
        Write-Host "  CPU: $($hardwareInfo.CPU.Name)" -ForegroundColor White
        Write-Host "       $($hardwareInfo.CPU.NumberOfCores) cores / $($hardwareInfo.CPU.NumberOfLogicalProcessors) threads @ $($hardwareInfo.CPU.MaxClockSpeedMHz) MHz" -ForegroundColor DarkGray
    }
    
    if ($hardwareInfo.Memory) {
        Write-Host "  RAM: $($hardwareInfo.Memory.TotalGB) GB ($($hardwareInfo.Memory.ModuleCount) modules)" -ForegroundColor White
        Write-Host "       Usage: $($hardwareInfo.Memory.UsagePercent)% ($($hardwareInfo.Memory.UsedGB) GB used, $($hardwareInfo.Memory.AvailableGB) GB available)" -ForegroundColor DarkGray
    }
    
    if ($hardwareInfo.GPU -and $hardwareInfo.GPU.Count -gt 0) {
        Write-Host "  GPU(s):" -ForegroundColor White
        foreach ($gpu in $hardwareInfo.GPU) {
            $discrete = if ($gpu.IsDiscrete) { " (Discrete)" } else { " (Integrated)" }
            Write-Host "       - $($gpu.Name) [$($gpu.Vendor)]$discrete" -ForegroundColor DarkGray
            Write-Host "         VRAM: $($gpu.VRAM_GB) GB" -ForegroundColor DarkGray
        }
    }
    
    if ($hardwareInfo.Storage) {
        $systemDrive = $hardwareInfo.Storage.SystemDrive
        if ($systemDrive) {
            Write-Host "  Storage: $($systemDrive.DriveLetter) ($($systemDrive.FileSystem))" -ForegroundColor White
            Write-Host "           $($systemDrive.TotalSizeGB) GB total, $($systemDrive.FreeSpaceGB) GB free ($($systemDrive.UsagePercent)% used)" -ForegroundColor DarkGray
        }
        
        $ssdCount = ($hardwareInfo.Storage.PhysicalDrives | Where-Object IsSSD).Count
        $totalDrives = $hardwareInfo.Storage.PhysicalDrives.Count
        if ($totalDrives -gt 0) {
            Write-Host "           Physical: $totalDrives drive(s), $ssdCount SSD(s)" -ForegroundColor DarkGray
        }
    }
    
    # Gaming Performance Score
    Write-Host ""
    Write-Host "?? Gaming Performance Assessment:" -ForegroundColor Yellow
    Write-Host "  Performance Score: $($hardwareInfo.GamingScore)/100" -ForegroundColor $(
        if ($hardwareInfo.GamingScore -ge 80) { "Green" }
        elseif ($hardwareInfo.GamingScore -ge 50) { "Yellow" }
        else { "Red" }
    )
    Write-Host "  Recommended Profile: $($hardwareInfo.RecommendedProfile)" -ForegroundColor White
    
    # Show individual optimization status reports
    Show-MemoryOptimizationReport
    Show-ETWOptimizationReport
    Show-PowerOptimizationReport
    Show-GamingOptimizationReport
    
    # Overall optimization summary
    Show-OverallOptimizationSummary
}

function Show-OverallOptimizationSummary {
    Write-Host ""
    Write-Host "?? Overall Optimization Summary:" -ForegroundColor Yellow
    
    # Get status from all modules
    $memoryStatus = Get-MemoryOptimizationStatus
    $etwStatus = Get-ETWOptimizationStatus
    $powerStatus = Get-PowerOptimizationStatus
    
    # Calculate overall scores
    $memoryScore = Calculate-MemoryOptimizationScore $memoryStatus
    $etwScore = Calculate-ETWOptimizationScore $etwStatus
    $powerScore = Calculate-PowerOptimizationScore $powerStatus
    
    $overallScore = [math]::Round(($memoryScore + $etwScore + $powerScore) / 3)
    
    Write-Host ""
    Write-Host "  Memory Optimization:    $memoryScore%" -ForegroundColor $(Get-ScoreColor $memoryScore)
    Write-Host "  ETW/Telemetry Cleanup:  $etwScore%" -ForegroundColor $(Get-ScoreColor $etwScore)
    Write-Host "  Power/Mouse Settings:   $powerScore%" -ForegroundColor $(Get-ScoreColor $powerScore)
    Write-Host "  ????????????????????????????????" -ForegroundColor DarkGray
    Write-Host "  Overall Optimization:   $overallScore%" -ForegroundColor $(Get-ScoreColor $overallScore)
    
    # Performance impact estimation
    $estimatedGain = Calculate-EstimatedPerformanceGain -OverallScore $overallScore
    Write-Host ""
    Write-Host "  Estimated Performance Gain: $estimatedGain" -ForegroundColor Cyan
    
    # Recommendations
    if ($overallScore -lt 80) {
        Write-Host ""
        Write-Host "  ?? Recommendations:" -ForegroundColor Yellow
        if ($memoryScore -lt 80) {
            Write-Host "    • Run memory optimizations for better RAM utilization" -ForegroundColor DarkYellow
        }
        if ($etwScore -lt 80) {
            Write-Host "    • Clean up ETW logging and telemetry for reduced overhead" -ForegroundColor DarkYellow
        }
        if ($powerScore -lt 80) {
            Write-Host "    • Optimize power settings and disable mouse acceleration" -ForegroundColor DarkYellow
        }
    }
}

function Calculate-MemoryOptimizationScore {
    param($Status)
    
    $score = 0
    $maxScore = 6
    
    if ($Status.DisablePagingExecutive) { $score++ }
    if ($Status.LargeSystemCache) { $score++ }
    if ($Status.IoPageLockLimit) { $score++ }
    if (-not $Status.MemoryCompression) { $score++ }
    if ($Status.OptimizedPrefetch) { $score++ }
    if ($Status.CustomPagefile) { $score++ }
    
    return [math]::Round(($score / $maxScore) * 100)
}

function Calculate-ETWOptimizationScore {
    param($Status)
    
    $score = 0
    
    # Active ETW sessions (lower is better)
    if ($Status.ActiveETWSessions -lt 5) { $score += 30 }
    elseif ($Status.ActiveETWSessions -lt 10) { $score += 20 }
    elseif ($Status.ActiveETWSessions -lt 15) { $score += 10 }
    
    # Disabled AutoLoggers (higher is better)
    if ($Status.DisabledAutoLoggers -gt 10) { $score += 25 }
    elseif ($Status.DisabledAutoLoggers -gt 5) { $score += 15 }
    elseif ($Status.DisabledAutoLoggers -gt 0) { $score += 10 }
    
    # Telemetry disabled
    if ($Status.TelemetryDisabled) { $score += 25 }
    
    # Services optimized
    if ($Status.ServicesOptimized -ge 3) { $score += 15 }
    elseif ($Status.ServicesOptimized -ge 1) { $score += 10 }
    
    # Performance settings
    if ($Status.PerformanceOptimized) { $score += 5 }
    
    return [math]::Min(100, $score)
}

function Calculate-PowerOptimizationScore {
    param($Status)
    
    $score = 0
    $maxScore = 3
    
    if ($Status.UltimatePerformanceActive) { $score++ }
    if ($Status.MouseAccelerationDisabled) { $score++ }
    if ($Status.PowerSettingsOptimized) { $score++ }
    
    return [math]::Round(($score / $maxScore) * 100)
}

function Get-ScoreColor {
    param([int]$Score)
    
    if ($Score -ge 80) { return "Green" }
    elseif ($Score -ge 60) { return "Yellow" }
    elseif ($Score -ge 40) { return "DarkYellow" }
    else { return "Red" }
}

function Calculate-EstimatedPerformanceGain {
    param([int]$OverallScore)
    
    $baseGain = [math]::Round($OverallScore * 0.25)  # Up to 25% gain at 100% optimization
    
    switch ($OverallScore) {
        { $_ -ge 90 } { "+$baseGain-$(([math]::Round($baseGain * 1.2)))% FPS, +25-40% responsiveness" }
        { $_ -ge 70 } { "+$baseGain-$(([math]::Round($baseGain * 1.1)))% FPS, +15-25% responsiveness" }
        { $_ -ge 50 } { "+$baseGain-$([math]::Round($baseGain * 1.1))% FPS, +10-20% responsiveness" }
        { $_ -ge 30 } { "+$baseGain-$baseGain% FPS, +5-15% responsiveness" }
        default { "+$baseGain% FPS, +5-10% responsiveness" }
    }
}

# ========================= PROFILE MANAGEMENT =========================
function Get-OptimizationProfile {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Gaming", "Balanced", "Conservative", "Custom")]
        [string]$ProfileName
    )
    
    Write-Log "Loading optimization profile: $ProfileName" -Level Info -Category "Profile"
    
    $profiles = @{
        "Gaming" = @{
            "Memory" = $true
            "GPU" = $true
            "ETW" = $true
            "Gaming" = $true
            "Network" = $true
            "MousePrecision" = $true
            "PowerPlan" = $true
            "VisualEffects" = $true
            "BackgroundApps" = $true
        }
        "Balanced" = @{
            "Memory" = $true
            "GPU" = $true
            "ETW" = $true
            "Gaming" = $true
            "Network" = $false
            "MousePrecision" = $true
            "PowerPlan" = $false
            "VisualEffects" = $false
            "BackgroundApps" = $false
        }
        "Conservative" = @{
            "Memory" = $false
            "GPU" = $true
            "ETW" = $false
            "Gaming" = $true
            "Network" = $false
            "MousePrecision" = $true
            "PowerPlan" = $false
            "VisualEffects" = $false
            "BackgroundApps" = $false
        }
        "Custom" = @{
            # Custom profiles loaded from file
        }
    }
    
    if ($profiles.ContainsKey($ProfileName)) {
        return $profiles[$ProfileName]
    }
    
    Write-Log "Profile not found: $ProfileName" -Level Error -Category "Profile"
    return $null
}

function Show-GamingOptimizationReport {
    # This would show GPU and gaming-specific optimizations
    # Implementation would go here based on other modules
    Write-Host ""
    Write-Host "?? Gaming Optimizations:" -ForegroundColor Yellow
    Write-Host "  (Gaming optimization status reporting - implementation pending)" -ForegroundColor DarkGray
}

# ========================= PROGRESS AND FEEDBACK =========================
function Show-OptimizationProgress {
    param(
        [Parameter(Mandatory)]
        [string]$Activity,
        
        [Parameter(Mandatory)]
        [int]$PercentComplete,
        
        [Parameter()]
        [string]$Status = ""
    )
    
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
}

function Show-CompletionSummary {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Results
    )
    
    Write-Host ""
    Write-Host "?? Optimization Complete!" -ForegroundColor Green
    Write-Host ""
    
    if ($Results.Success.Count -gt 0) {
        Write-Host "? Successfully Applied:" -ForegroundColor Green
        foreach ($category in $Results.Success) {
            $displayName = $Script:OptimizationCategories[$category].DisplayName
            $impact = $Script:OptimizationCategories[$category].EstimatedGain
            Write-Host "   • $displayName ($impact)" -ForegroundColor White
        }
    }
    
    if ($Results.Failed.Count -gt 0) {
        Write-Host ""
        Write-Host "? Failed to Apply:" -ForegroundColor Red
        foreach ($category in $Results.Failed) {
            $displayName = $Script:OptimizationCategories[$category].DisplayName
            Write-Host "   • $displayName" -ForegroundColor White
        }
    }
    
    if ($Results.Skipped.Count -gt 0) {
        Write-Host ""
        Write-Host "??  Skipped:" -ForegroundColor Yellow
        foreach ($category in $Results.Skipped) {
            $displayName = $Script:OptimizationCategories[$category].DisplayName
            Write-Host "   • $displayName" -ForegroundColor White
        }
    }
    
    # Check if reboot is required
    $requiresReboot = $false
    foreach ($category in $Results.Success) {
        if ($Script:OptimizationCategories[$category].RequiresReboot) {
            $requiresReboot = $true
            break
        }
    }
    
    if ($requiresReboot) {
        Write-Host ""
        Write-Host "??  Reboot Required" -ForegroundColor Yellow
        Write-Host "   Some optimizations require a system restart to take full effect." -ForegroundColor White
    }
}

# ========================= HELP AND DOCUMENTATION =========================
function Show-OptimizationHelp {
    param(
        [Parameter()]
        [string]$Category = ""
    )
    
    if ($Category -eq "") {
        # Show general help
        Write-Host ""
        Write-Host "?? GameMemVRAM-Tuner Ultimate Help" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Available Optimization Categories:" -ForegroundColor Yellow
        
        foreach ($categoryKey in $Script:OptimizationCategories.Keys) {
            $category = $Script:OptimizationCategories[$categoryKey]
            Write-Host "  $($category.DisplayName)" -ForegroundColor White
            Write-Host "    $($category.Description)" -ForegroundColor DarkGray
            Write-Host "    Impact: $($category.EstimatedGain)" -ForegroundColor DarkCyan
            Write-Host ""
        }
    }
    else {
        # Show specific category help
        if ($Script:OptimizationCategories.ContainsKey($Category)) {
            $cat = $Script:OptimizationCategories[$Category]
            Write-Host ""
            Write-Host "Help for: $($cat.DisplayName)" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Description: $($cat.Description)" -ForegroundColor White
            Write-Host "Estimated Performance Gain: $($cat.EstimatedGain)" -ForegroundColor Yellow
            Write-Host "Requires Reboot: $(if ($cat.RequiresReboot) { 'Yes' } else { 'No' })" -ForegroundColor White
            Write-Host ""
            Write-Host "Functions:" -ForegroundColor Yellow
            foreach ($func in $cat.Functions) {
                Write-Host "  - $func" -ForegroundColor DarkGray
            }
        }
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'Show-SystemReport',
    'Show-OverallOptimizationSummary',
    'Calculate-MemoryOptimizationScore',
    'Calculate-ETWOptimizationScore', 
    'Calculate-PowerOptimizationScore',
    'Get-ScoreColor',
    'Calculate-EstimatedPerformanceGain',
    'Get-OptimizationProfile',
    'Show-GamingOptimizationReport',
    'Show-OptimizationProgress',
    'Show-CompletionSummary',
    'Show-OptimizationHelp'
)