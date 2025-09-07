# Hardware-Detection.psm1 - Hardware detection for GameMemVRAM-Tuner Ultimate

# ========================= MEMORY DETECTION =========================
function Get-SystemMemoryInfo {
    Write-Log "Detecting system memory configuration" -Level Info -Category "Hardware"
    
    try {
        $computerSystem = Get-CimInstance Win32_ComputerSystem
        $totalRAM_Bytes = [int64]$computerSystem.TotalPhysicalMemory
        $totalRAM_GB = [math]::Round($totalRAM_Bytes / 1GB, 2)
        
        $memoryModules = @(Get-CimInstance Win32_PhysicalMemory | Select-Object @(
            'Capacity',
            'Speed', 
            'Manufacturer',
            'PartNumber',
            'ConfiguredClockSpeed',
            'FormFactor',
            @{Name='CapacityGB'; Expression={[math]::Round($_.Capacity / 1GB, 2)}}
        ))
        
        # Get memory usage information
        $availableBytes = (Get-Counter '\Memory\Available Bytes' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
        $availableGB = if ($availableBytes) { [math]::Round($availableBytes / 1GB, 2) } else { 0 }
        
        $memoryInfo = @{
            TotalBytes = $totalRAM_Bytes
            TotalGB = $totalRAM_GB
            AvailableGB = $availableGB
            UsedGB = [math]::Round($totalRAM_GB - $availableGB, 2)
            UsagePercent = if ($totalRAM_GB -gt 0) { [math]::Round((($totalRAM_GB - $availableGB) / $totalRAM_GB) * 100, 1) } else { 0 }
            Modules = $memoryModules
            ModuleCount = $memoryModules.Count
            MaxSingleModule = if ($memoryModules) { ($memoryModules | Measure-Object -Property CapacityGB -Maximum).Maximum } else { 0 }
        }
        
        Write-Log "Total RAM: $($memoryInfo.TotalGB) GB ($($memoryInfo.ModuleCount) modules, $($memoryInfo.UsagePercent)% used)" -Level Info -Category "Hardware"
        
        return $memoryInfo
        
    } catch {
        Write-Log "Failed to detect system memory: $($_.Exception.Message)" -Level Error -Category "Hardware"
        return $null
    }
}

function Get-MemoryFormFactorName {
    param([int]$FormFactor)
    
    switch ($FormFactor) {
        8 { "DIMM" }
        12 { "SO-DIMM" }
        13 { "Micro-DIMM" }
        default { "Unknown ($FormFactor)" }
    }
}

# ========================= GPU DETECTION =========================
function Get-GPUInformation {
    Write-Log "Detecting GPU configuration with VRAM" -Level Info -Category "Hardware"
    
    $gpuList = @()
    
    try {
        # Get GPUs from WMI
        $wmiGpus = Get-CimInstance Win32_VideoController | 
                   Where-Object { $_.AdapterRAM -gt 0 -or $_.Name -notmatch "Remote|RDP|TeamViewer" } | 
                   Sort-Object Name
        
        foreach ($gpu in $wmiGpus) {
            $pnpDeviceID = $gpu.PNPDeviceID
            $vendorID = $null
            
            if ($pnpDeviceID -match "VEN_([0-9A-F]{4})") { 
                $vendorID = $Matches[1] 
            }
            
            $vendor = Get-GPUVendorName -VendorID $vendorID -GPUName $gpu.Name
            
            $vramMB = 0
            if ($gpu.AdapterRAM -gt 0) {
                $vramMB = [math]::Floor($gpu.AdapterRAM / 1MB)
            }
            
            # Determine if this is a discrete GPU
            $isDiscrete = ($vendor -in @("NVIDIA", "AMD")) -and ($vramMB -ge 1024)
            
            $gpuInfo = [PSCustomObject]@{
                Name = $gpu.Name
                Vendor = $vendor
                VendorID = $vendorID
                PNPDeviceID = $pnpDeviceID
                VRAM_MB = $vramMB
                VRAM_GB = [math]::Round($vramMB / 1024, 2)
                IsDiscrete = $isDiscrete
                DriverVersion = $gpu.DriverVersion
                DriverDate = $gpu.DriverDate
                Status = $gpu.Status
                VideoProcessor = $gpu.VideoProcessor
                VideoArchitecture = $gpu.VideoArchitecture
                CurrentHorizontalResolution = $gpu.CurrentHorizontalResolution
                CurrentVerticalResolution = $gpu.CurrentVerticalResolution
                CurrentRefreshRate = $gpu.CurrentRefreshRate
            }
            
            $gpuList += $gpuInfo
        }
        
        # Enhanced VRAM detection for discrete GPUs
        $discreteGPUs = $gpuList | Where-Object IsDiscrete
        if ($discreteGPUs) {
            $enhancedVRAM = Get-EnhancedVRAMDetection
            if ($enhancedVRAM) {
                foreach ($gpu in $discreteGPUs) {
                    $vendorKey = $gpu.Vendor.ToUpper()
                    if ($enhancedVRAM.ContainsKey($vendorKey) -and $enhancedVRAM[$vendorKey] -gt $gpu.VRAM_MB) {
                        $gpu.VRAM_MB = $enhancedVRAM[$vendorKey]
                        $gpu.VRAM_GB = [math]::Round($enhancedVRAM[$vendorKey] / 1024, 2)
                        Write-Log "Enhanced VRAM detection for $($gpu.Name): $($gpu.VRAM_GB) GB" -Level Debug -Category "Hardware"
                    }
                }
            }
        }
        
        Write-Log "Detected $($gpuList.Count) GPU(s)" -Level Info -Category "Hardware"
        foreach ($gpu in $gpuList) {
            $discrete = if ($gpu.IsDiscrete) { " (Discrete)" } else { " (Integrated)" }
            Write-Log "  - $($gpu.Name) [$($gpu.Vendor)]$discrete VRAM: $($gpu.VRAM_GB) GB" -Level Info -Category "Hardware"
        }
        
        return $gpuList
        
    } catch {
        Write-Log "Failed to detect GPU information: $($_.Exception.Message)" -Level Error -Category "Hardware"
        return @()
    }
}

function Get-GPUVendorName {
    param(
        [string]$VendorID,
        [string]$GPUName
    )
    
    # Check VendorID first
    $vendor = switch ($VendorID) {
        "10DE" { "NVIDIA" }
        { $_ -in @("1002", "1022") } { "AMD" }
        "8086" { "Intel" }
        default { $null }
    }
    
    # Fallback to name-based detection
    if (-not $vendor -and $GPUName) {
        switch -Regex ($GPUName) {
            "NVIDIA|GeForce|GTX|RTX|Quadro|Tesla" { $vendor = "NVIDIA" }
            "AMD|Radeon|FirePro|Instinct" { $vendor = "AMD" }
            "Intel|HD Graphics|UHD Graphics|Iris|Arc" { $vendor = "Intel" }
            default { $vendor = "Unknown" }
        }
    }
    
    # Return vendor or "Unknown" if null
    if ($vendor) { return $vendor } else { return "Unknown" }
}

function Get-EnhancedVRAMDetection {
    $vramInfo = @{}
    
    # NVIDIA: Try nvidia-smi
    $nvidiaSmiPaths = @(
        "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
        "C:\Windows\System32\nvidia-smi.exe",
        "${env:ProgramFiles}\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
    )
    
    foreach ($path in $nvidiaSmiPaths) {
        if (Test-Path $path) {
            try {
                $output = & $path --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
                if ($output -and $output[0] -match '^\d+$') {
                    $vramInfo.NVIDIA = [int]$output[0]
                    Write-Log "NVIDIA VRAM detected via nvidia-smi: $($vramInfo.NVIDIA) MB" -Level Debug -Category "Hardware"
                    break
                }
            } catch {
                Write-Log "nvidia-smi execution failed: $($_.Exception.Message)" -Level Debug -Category "Hardware"
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
                    $vendorKey = $node.Vendor.ToUpper()
                    if (-not $vramInfo.ContainsKey($vendorKey) -or $vramMB -gt $vramInfo[$vendorKey]) {
                        $vramInfo[$vendorKey] = $vramMB
                        Write-Log "$($node.Vendor) VRAM detected via registry: $vramMB MB" -Level Debug -Category "Hardware"
                    }
                }
            }
        }
    } catch {
        Write-Log "Registry VRAM detection failed: $($_.Exception.Message)" -Level Debug -Category "Hardware"
    }
    
    # DXDIAG fallback (slower but comprehensive)
    if ($vramInfo.Count -eq 0) {
        try {
            $dxdiagVRAM = Get-DXDiagVRAM
            if ($dxdiagVRAM) {
                $vramInfo = $dxdiagVRAM
            }
        } catch {
            Write-Log "DXDIAG VRAM detection failed: $($_.Exception.Message)" -Level Debug -Category "Hardware"
        }
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
                            ProviderName = $providerName
                            MatchingDeviceId = $matchingDeviceId
                        }
                    }
                } catch {
                    Write-Log "Failed to read registry node $regPath : $($_.Exception.Message)" -Level Debug -Category "Hardware"
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
        
        # Try DedicatedVideoMemory
        if ($properties."HardwareInformation.DedicatedVideoMemory" -ne $null) {
            return [uint64]$properties."HardwareInformation.DedicatedVideoMemory"
        }
        
        # Fallback to DWORD (32-bit)
        if ($properties."HardwareInformation.MemorySize" -ne $null) {
            return [uint64]([uint32]$properties."HardwareInformation.MemorySize")
        }
        
        # Try AdapterMemorySize
        if ($properties."HardwareInformation.AdapterMemorySize" -ne $null) {
            return [uint64]$properties."HardwareInformation.AdapterMemorySize"
        }
        
    } catch {
        Write-Log "Failed to read VRAM from registry: $RegistryPath" -Level Debug -Category "Hardware"
    }
    
    return 0
}

function Get-DXDiagVRAM {
    try {
        $dxdiagPath = Join-Path $env:TEMP "dxdiag_vram_$(Get-Date -Format 'yyyyMMddHHmmss').txt"
        
        # Run dxdiag to get system information
        $process = Start-Process -FilePath "dxdiag" -ArgumentList "/t", $dxdiagPath -Wait -PassThru -WindowStyle Hidden
        
        if ($process.ExitCode -eq 0 -and (Test-Path $dxdiagPath)) {
            $content = Get-Content $dxdiagPath -Raw
            $vramInfo = @{}
            
            # Parse VRAM information from dxdiag output
            if ($content -match "Approximate total memory:\s*(\d+)\s*MB") {
                $totalVRAM = [int]$Matches[1]
                
                # Try to determine vendor from device description
                if ($content -match "Card name:\s*(.+)") {
                    $cardName = $Matches[1].Trim()
                    $vendor = Get-GPUVendorName -VendorID $null -GPUName $cardName
                    
                    if ($vendor -ne "Unknown") {
                        $vramInfo[$vendor.ToUpper()] = $totalVRAM
                    }
                }
            }
            
            # Cleanup temp file
            Remove-Item $dxdiagPath -Force -ErrorAction SilentlyContinue
            
            return $vramInfo
        }
    } catch {
        Write-Log "DXDIAG VRAM detection failed: $($_.Exception.Message)" -Level Debug -Category "Hardware"
    }
    
    return $null
}

# ========================= STORAGE DETECTION =========================
function Get-StorageInformation {
    Write-Log "Detecting storage configuration" -Level Info -Category "Hardware"
    
    try {
        $drives = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
            [PSCustomObject]@{
                DriveLetter = $_.DeviceID
                FileSystem = $_.FileSystem
                TotalSizeGB = [math]::Round($_.Size / 1GB, 2)
                FreeSpaceGB = [math]::Round($_.FreeSpace / 1GB, 2)
                UsedSpaceGB = [math]::Round(($_.Size - $_.FreeSpace) / 1GB, 2)
                UsagePercent = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
                IsSystemDrive = $_.DeviceID -eq $env:SystemDrive
            }
        }
        
        # Get physical drive information
        $physicalDrives = Get-CimInstance Win32_DiskDrive | ForEach-Object {
            [PSCustomObject]@{
                Model = $_.Model
                InterfaceType = $_.InterfaceType
                SizeGB = [math]::Round($_.Size / 1GB, 2)
                MediaType = $_.MediaType
                IsSSD = ($_.MediaType -eq "Fixed hard disk media" -and $_.Model -match "SSD|Solid State|NVMe") -or $_.InterfaceType -eq "SCSI"
            }
        }
        
        return @{
            LogicalDrives = $drives
            PhysicalDrives = $physicalDrives
            SystemDrive = $drives | Where-Object IsSystemDrive
        }
        
    } catch {
        Write-Log "Failed to detect storage information: $($_.Exception.Message)" -Level Error -Category "Hardware"
        return $null
    }
}

# ========================= CPU DETECTION =========================
function Get-CPUInformation {
    Write-Log "Detecting CPU configuration" -Level Info -Category "Hardware"
    
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        
        $cpuInfo = [PSCustomObject]@{
            Name = $cpu.Name.Trim()
            Manufacturer = $cpu.Manufacturer
            Architecture = $cpu.Architecture
            NumberOfCores = $cpu.NumberOfCores
            NumberOfLogicalProcessors = $cpu.NumberOfLogicalProcessors
            MaxClockSpeedMHz = $cpu.MaxClockSpeed
            CurrentClockSpeedMHz = $cpu.CurrentClockSpeed
            L3CacheSizeKB = $cpu.L3CacheSize
            L2CacheSizeKB = $cpu.L2CacheSize
            Voltage = $cpu.CurrentVoltage
            SocketDesignation = $cpu.SocketDesignation
            IsHyperThreading = $cpu.NumberOfLogicalProcessors -gt $cpu.NumberOfCores
            ProcessorId = $cpu.ProcessorId
        }
        
        Write-Log "CPU: $($cpuInfo.Name) ($($cpuInfo.NumberOfCores)C/$($cpuInfo.NumberOfLogicalProcessors)T @ $($cpuInfo.MaxClockSpeedMHz)MHz)" -Level Info -Category "Hardware"
        
        return $cpuInfo
        
    } catch {
        Write-Log "Failed to detect CPU information: $($_.Exception.Message)" -Level Error -Category "Hardware"
        return $null
    }
}

# ========================= COMPREHENSIVE SYSTEM DETECTION =========================
function Get-ComprehensiveHardwareInfo {
    Write-Log "Performing comprehensive hardware detection" -Level Info -Category "Hardware"
    
    $hardwareInfo = @{
        System = Get-SystemInformation
        Memory = Get-SystemMemoryInfo
        GPU = Get-GPUInformation
        Storage = Get-StorageInformation
        CPU = Get-CPUInformation
        Timestamp = Get-Date
    }
    
    # Add computed values
    $hardwareInfo.GamingScore = Get-GamingPerformanceScore -HardwareInfo $hardwareInfo
    $hardwareInfo.RecommendedProfile = Get-RecommendedOptimizationProfile -HardwareInfo $hardwareInfo
    
    return $hardwareInfo
}

function Get-GamingPerformanceScore {
    param([hashtable]$HardwareInfo)
    
    $score = 0
    
    # RAM scoring (0-30 points)
    if ($HardwareInfo.Memory) {
        $ramGB = $HardwareInfo.Memory.TotalGB
        if ($ramGB -ge 32) { $score += 30 }
        elseif ($ramGB -ge 16) { $score += 25 }
        elseif ($ramGB -ge 8) { $score += 15 }
        else { $score += 5 }
    }
    
    # GPU scoring (0-40 points)
    if ($HardwareInfo.GPU) {
        $discreteGPUs = $HardwareInfo.GPU | Where-Object IsDiscrete
        if ($discreteGPUs) {
            $maxVRAM = ($discreteGPUs | Measure-Object -Property VRAM_GB -Maximum).Maximum
            if ($maxVRAM -ge 12) { $score += 40 }
            elseif ($maxVRAM -ge 8) { $score += 35 }
            elseif ($maxVRAM -ge 6) { $score += 25 }
            elseif ($maxVRAM -ge 4) { $score += 15 }
            else { $score += 10 }
        }
        else { $score += 5 }
    }
    
    # CPU scoring (0-20 points)
    if ($HardwareInfo.CPU) {
        $cores = $HardwareInfo.CPU.NumberOfCores
        if ($cores -ge 8) { $score += 20 }
        elseif ($cores -ge 6) { $score += 15 }
        elseif ($cores -ge 4) { $score += 10 }
        else { $score += 5 }
    }
    
    # Storage scoring (0-10 points)
    if ($HardwareInfo.Storage -and $HardwareInfo.Storage.PhysicalDrives) {
        $hasSSD = $HardwareInfo.Storage.PhysicalDrives | Where-Object IsSSD
        if ($hasSSD) { $score += 10 }
        else { $score += 3 }
    }
    
    return [math]::Min(100, $score)
}

function Get-RecommendedOptimizationProfile {
    param([hashtable]$HardwareInfo)
    
    $score = Get-GamingPerformanceScore -HardwareInfo $HardwareInfo
    
    if ($score -ge 80) { return "Gaming" }
    elseif ($score -ge 50) { return "Balanced" }
    else { return "Conservative" }
}

# Export module functions
Export-ModuleMember -Function @(
    'Get-SystemMemoryInfo',
    'Get-GPUInformation',
    'Get-StorageInformation',
    'Get-CPUInformation',
    'Get-ComprehensiveHardwareInfo',
    'Get-GamingPerformanceScore',
    'Get-RecommendedOptimizationProfile',
    'Get-DisplayRegistryNodes',
    'Get-EnhancedVRAMDetection'
)