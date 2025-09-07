# Gaming-Optimization.psm1 - Gaming-specific optimizations for GameMemVRAM-Tuner Ultimate

# ========================= GAMING MODE OPTIMIZATION =========================
function Optimize-GameMode {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Optimizing Windows Game Mode settings" -Level Info -Category "Gaming"
    
    $gameBarPath = "HKCU:\Software\Microsoft\GameBar"
    $gameConfigPath = "HKCU:\System\GameConfigStore"
    
    $settings = @(
        @{
            Path = $gameBarPath
            Name = "AllowAutoGameMode"
            Value = 1
            Type = "DWord"
            Description = "Enable automatic Game Mode activation"
            Impact = "Automatic CPU/GPU priority optimization during gaming"
        },
        @{
            Path = $gameBarPath
            Name = "UseNexusForGameBarEnabled"
            Value = 0
            Type = "DWord"
            Description = "Disable Game Bar Nexus integration"
            Impact = "Reduced Game Bar overhead"
        }
    )
    
    $applied = 0
    foreach ($setting in $settings) {
        try {
            # Backup current value
            Backup-RegistryValue -Path $setting.Path -Name $setting.Name -Description $setting.Description
            
            if ($WhatIf) {
                Write-Log "[PREVIEW] Would set $($setting.Path)\$($setting.Name) = $($setting.Value) - $($setting.Impact)" -Level Info -Category "Gaming"
            }
            else {
                $success = Set-RegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -Description $setting.Description
                if ($success) {
                    Write-Log "Applied Game Mode setting: $($setting.Name) - $($setting.Impact)" -Level Info -Category "Gaming"
                    $applied++
                }
            }
        }
        catch {
            Write-Log "Failed to apply Game Mode setting $($setting.Name): $($_.Exception.Message)" -Level Error -Category "Gaming"
        }
    }
    
    Write-Log "Game Mode optimization completed: $applied settings applied" -Level Info -Category "Gaming"
    return $applied -gt 0
}

function Disable-GameDVR {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Disabling Xbox Game DVR for better gaming performance" -Level Info -Category "Gaming"
    
    $gameConfigPath = "HKCU:\System\GameConfigStore"
    
    $settings = @(
        @{
            Name = "GameDVR_Enabled"
            Value = 0
            Description = "Disable Xbox Game DVR recording"
            Impact = "Eliminates recording overhead, improves FPS"
        },
        @{
            Name = "GameDVR_FSEBehaviorMode"
            Value = 2
            Description = "Optimize Game DVR fullscreen exclusive behavior"
            Impact = "Better fullscreen performance"
        },
        @{
            Name = "GameDVR_HonorUserFSEBehaviorMode"
            Value = 1
            Description = "Honor user FSE behavior mode preferences"
            Impact = "Consistent fullscreen behavior"
        },
        @{
            Name = "GameDVR_DXGIHonorFSEWindowsCompatible"
            Value = 1
            Description = "DXGI FSE Windows compatibility mode"
            Impact = "Better DirectX compatibility"
        },
        @{
            Name = "GameDVR_EFSEFeatureFlags"
            Value = 0
            Description = "Disable enhanced FSE features"
            Impact = "Reduced complexity and overhead"
        }
    )
    
    $applied = 0
    foreach ($setting in $settings) {
        try {
            # Backup current value
            Backup-RegistryValue -Path $gameConfigPath -Name $setting.Name -Description $setting.Description
            
            if ($WhatIf) {
                Write-Log "[PREVIEW] Would set Game DVR setting: $($setting.Name) = $($setting.Value) - $($setting.Impact)" -Level Info -Category "Gaming"
            }
            else {
                $success = Set-RegistryValue -Path $gameConfigPath -Name $setting.Name -Value $setting.Value -Type "DWord" -Description $setting.Description
                if ($success) {
                    Write-Log "Applied Game DVR setting: $($setting.Name) - $($setting.Impact)" -Level Info -Category "Gaming"
                    $applied++
                }
            }
        }
        catch {
            Write-Log "Failed to apply Game DVR setting $($setting.Name): $($_.Exception.Message)" -Level Error -Category "Gaming"
        }
    }
    
    Write-Log "Game DVR disable completed: $applied settings applied" -Level Info -Category "Gaming"
    return $applied -gt 0
}

function Optimize-FullscreenExclusive {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Optimizing fullscreen exclusive mode settings" -Level Info -Category "Gaming"
    
    $fseSettings = @{
        "HKCU:\System\GameConfigStore" = @{
            "GameDVR_FSEBehavior" = @{ Value = 2; Description = "Optimize FSE behavior for performance" }
            "GameDVR_HonorFSEWindowsCompatible" = @{ Value = 1; Description = "Honor FSE Windows compatibility" }
        }
        "HKLM:\SOFTWARE\Microsoft\Windows\Dwm" = @{
            "EnableAeroPeek" = @{ Value = 0; Description = "Disable Aero Peek for better FSE performance" }
        }
    }
    
    $applied = 0
    foreach ($regPath in $fseSettings.Keys) {
        foreach ($settingName in $fseSettings[$regPath].Keys) {
            $setting = $fseSettings[$regPath][$settingName]
            
            try {
                # Backup current value
                Backup-RegistryValue -Path $regPath -Name $settingName -Description $setting.Description
                
                if ($WhatIf) {
                    Write-Log "[PREVIEW] Would set FSE setting: $regPath\$settingName = $($setting.Value) - $($setting.Description)" -Level Info -Category "Gaming"
                }
                else {
                    $success = Set-RegistryValue -Path $regPath -Name $settingName -Value $setting.Value -Type "DWord" -Description $setting.Description
                    if ($success) {
                        Write-Log "Applied FSE setting: $settingName - $($setting.Description)" -Level Info -Category "Gaming"
                        $applied++
                    }
                }
            }
            catch {
                Write-Log "Failed to apply FSE setting $regPath\$settingName : $($_.Exception.Message)" -Level Error -Category "Gaming"
            }
        }
    }
    
    Write-Log "Fullscreen exclusive optimization completed: $applied settings applied" -Level Info -Category "Gaming"
    return $applied -gt 0
}

# Export module functions
Export-ModuleMember -Function @(
    'Optimize-GameMode',
    'Disable-GameDVR',
    'Optimize-FullscreenExclusive'
)