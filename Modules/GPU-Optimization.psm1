# GPU-Optimization.psm1 - GPU and VRAM optimizations for GameMemVRAM-Tuner Ultimate

# ========================= GPU SETTINGS OPTIMIZATION =========================
function Optimize-GraphicsSettings {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Optimizing graphics settings for gaming performance" -Level Info -Category "GPU"
    
    $gfxPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    $dwmPath = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"
    
    $settings = @(
        @{ 
            Path = $gfxPath
            Name = "HwSchMode"
            Value = 2
            Type = "DWord"
            Description = "Enable Hardware Accelerated GPU Scheduling (HAGS)"
            Impact = "5-15% better GPU performance, reduced CPU overhead"
        },
        @{ 
            Path = $dwmPath
            Name = "OverlayTestMode"
            Value = 5
            Type = "DWord"
            Description = "Disable Multi-Plane Overlay (MPO)"
            Impact = "Eliminates fullscreen stuttering and flickering"
        }
    )
    
    $applied = 0
    foreach ($setting in $settings) {
        try {
            # Backup current value
            Backup-RegistryValue -Path $setting.Path -Name $setting.Name -Description $setting.Description
            
            if ($WhatIf) {
                Write-Log "[PREVIEW] Would set $($setting.Path)\$($setting.Name) = $($setting.Value) - $($setting.Impact)" -Level Info -Category "GPU"
            }
            else {
                $success = Set-RegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Description $setting.Description
                if ($success) {
                    Write-Log "Applied GPU setting: $($setting.Name) - $($setting.Impact)" -Level Info -Category "GPU"
                    $applied++
                }
            }
        }
        catch {
            Write-Log "Failed to apply GPU setting $($setting.Name): $($_.Exception.Message)" -Level Error -Category "GPU"
        }
    }
    
    Write-Log "Graphics settings optimization completed: $applied settings applied" -Level Info -Category "GPU"
    return $applied -gt 0
}

function Optimize-VRAMBudgeting {
    param(
        [Parameter()]
        [switch]$WhatIf,
        
        [Parameter()]
        [int]$ForceVramMB = 0
    )
    
    Write-Log "Optimizing VRAM budgeting hints" -Level Info -Category "GPU"
    
    # Get GPU information
    $gpuList = Get-GPUInformation
    if (-not $gpuList) {
        Write-Log "No GPU information available for VRAM optimization" -Level Warn -Category "GPU"
        return $false
    }
    
    # Focus on discrete GPUs
    $discreteGPUs = $gpuList | Where-Object IsDiscrete
    if (-not $discreteGPUs) {
        Write-Log "No discrete GPUs detected, skipping VRAM budgeting" -Level Info -Category "GPU"
        return $false
    }
    
    # Determine VRAM amount to use
    $maxVRAM_MB = if ($ForceVramMB -gt 0) {
        $ForceVramMB
    } else {
        ($discreteGPUs | Measure-Object -Property VRAM_MB -Maximum).Maximum
    }
    
    if ($maxVRAM_MB -le 0) {
        Write-Log "Could not determine VRAM amount for budgeting" -Level Warn -Category "GPU"
        return $false
    }
    
    Write-Log "Applying VRAM budgeting hint: $maxVRAM_MB MB" -Level Info -Category "GPU"
    
    # Get display registry nodes
    $displayNodes = Get-DisplayRegistryNodes
    $targetNodes = $displayNodes | Where-Object { $_.Vendor -in @("NVIDIA", "AMD") }
    
    if (-not $targetNodes) {
        Write-Log "No suitable GPU registry nodes found for VRAM budgeting" -Level Warn -Category "GPU"
        return $false
    }
    
    $applied = 0
    foreach ($node in $targetNodes) {
        try {
            # Backup current value
            Backup-RegistryValue -Path $node.Path -Name "DedicatedSegmentSize" -Description "VRAM budget hint"
            
            if ($WhatIf) {
                Write-Log "[PREVIEW] Would set VRAM hint for $($node.Description): $maxVRAM_MB MB" -Level Info -Category "GPU"
            }
            else {
                $success = Set-RegistryValue -Path $node.Path -Name "DedicatedSegmentSize" -Value ([uint32]$maxVRAM_MB) -Type "DWord" -Description "VRAM budget hint"
                if ($success) {
                    Write-Log "Applied VRAM hint to: $($node.Description) ($maxVRAM_MB MB)" -Level Info -Category "GPU"
                    $applied++
                }
            }
        }
        catch {
            Write-Log "Failed to apply VRAM hint to $($node.Description): $($_.Exception.Message)" -Level Error -Category "GPU"
        }
    }
    
    Write-Log "VRAM budgeting optimization completed: $applied nodes configured" -Level Info -Category "GPU"
    return $applied -gt 0
}

# Export module functions
Export-ModuleMember -Function @(
    'Optimize-GraphicsSettings',
    'Optimize-VRAMBudgeting'
)