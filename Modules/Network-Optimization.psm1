# Network-Optimization.psm1 - Network latency optimizations for GameMemVRAM-Tuner Ultimate

# ========================= NETWORK LATENCY OPTIMIZATION =========================
function Optimize-NetworkLatency {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Optimizing network settings for gaming latency" -Level Info -Category "Network"
    
    $tcpPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
    
    $settings = @(
        @{
            Name = "TcpNoDelay"
            Value = 1
            Description = "Disable Nagle's algorithm for immediate packet transmission"
            Impact = "2-5ms latency reduction in most games"
        },
        @{
            Name = "TcpAckFrequency"
            Value = 1
            Description = "Send ACK responses immediately"
            Impact = "Faster network acknowledgments"
        },
        @{
            Name = "TcpDelAckTicks"
            Value = 0
            Description = "Disable delayed ACK timer"
            Impact = "More responsive network communication"
        }
    )
    
    $applied = 0
    foreach ($setting in $settings) {
        try {
            # Backup current value
            Backup-RegistryValue -Path $tcpPath -Name $setting.Name -Description $setting.Description
            
            if ($WhatIf) {
                Write-Log "[PREVIEW] Would set network setting: $($setting.Name) = $($setting.Value) - $($setting.Impact)" -Level Info -Category "Network"
            }
            else {
                $success = Set-RegistryValue -Path $tcpPath -Name $setting.Name -Value $setting.Value -Type "DWord" -Description $setting.Description
                if ($success) {
                    Write-Log "Applied network setting: $($setting.Name) - $($setting.Impact)" -Level Info -Category "Network"
                    $applied++
                }
            }
        }
        catch {
            Write-Log "Failed to apply network setting $($setting.Name): $($_.Exception.Message)" -Level Error -Category "Network"
        }
    }
    
    Write-Log "Network latency optimization completed: $applied settings applied" -Level Info -Category "Network"
    return $applied -gt 0
}

function Disable-NagleAlgorithm {
    param(
        [Parameter()]
        [switch]$WhatIf
    )
    
    Write-Log "Disabling Nagle algorithm for gaming applications" -Level Info -Category "Network"
    
    # This is already covered in Optimize-NetworkLatency but kept as separate function
    # for modular access
    return Optimize-NetworkLatency -WhatIf:$WhatIf
}

# Export module functions
Export-ModuleMember -Function @(
    'Optimize-NetworkLatency',
    'Disable-NagleAlgorithm'
)