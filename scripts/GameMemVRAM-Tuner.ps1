<# =====================================================================
  GameMemVRAM-Tuner.ps1  (Windows 10/11, PowerShell 5.1 compatible)

  WHAT IT DOES
  - Auto-detects total RAM and GPU(s)
  - Skips Intel iGPU for VRAM hints; applies to NVIDIA/AMD dGPU only
  - Robust VRAM detection (nvidia-smi -> registry QWORD -> dxdiag -> WMI)
  - Favors RAM + reduces I/O (NtfsMemoryUsage, IoPageLockLimit, etc.)
  - Enables HAGS; disables MPO; disables Xbox DVR
  - Forces small fixed pagefile (1–2 GB) on system drive (typed WMI)
  - Optional TCP low-latency knobs
  - Apply / Revert / Report with verbose color output

  USAGE (Admin):
    .\GameMemVRAM-Tuner.ps1 -Apply
    .\GameMemVRAM-Tuner.ps1 -Report
    .\GameMemVRAM-Tuner.ps1 -Revert

  Optional:
    .\GameMemVRAM-Tuner.ps1 -Apply -SkipNetwork
===================================================================== #>

[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$Revert,
  [switch]$Report,
  [switch]$SkipNetwork,
  [int]$ForceVramMB
)

# ----------------------- Utility / safety ----------------------------#
function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run this script as Administrator." -ForegroundColor Red
    exit 1
  }
}
function Write-Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Write-OK($text)   { Write-Host "  ✓ $text" -ForegroundColor Green }
function Write-Warn2($t)   { Write-Host "  ! $t" -ForegroundColor Yellow }
function Write-Info($t)    { Write-Host "    $t" -ForegroundColor Gray }
function Coalesce($a,$b){ if($null -ne $a -and $a -ne ''){$a}else{$b} }

Assert-Admin

# ----------------------- Helpers: Registry --------------------------#
function Ensure-RegKey($Path){
  if (-not (Test-Path $Path)) {
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
  }
}
function Set-Dword($Path,$Name,$Value) {
  try {
    Ensure-RegKey $Path
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value ([uint32]$Value) -Force | Out-Null
    return $true
  } catch { Write-Warn2 "Failed to set $Path -> $Name : $($_.Exception.Message)"; return $false }
}
function Set-String($Path,$Name,$Value) {
  try {
    Ensure-RegKey $Path
    New-ItemProperty -Path $Path -Name $Name -PropertyType String -Value "$Value" -Force | Out-Null
    return $true
  } catch { Write-Warn2 "Failed to set $Path -> $Name : $($_.Exception.Message)"; return $false }
}
function Set-ExpandString($Path,$Name,$Value) {
  try {
    Ensure-RegKey $Path
    New-ItemProperty -Path $Path -Name $Name -PropertyType ExpandString -Value "$Value" -Force | Out-Null
    return $true
  } catch { Write-Warn2 "Failed to set $Path -> $Name : $($_.Exception.Message)"; return $false }
}
function Set-MultiSZ($Path,$Name,[string[]]$Values) {
  try {
    Ensure-RegKey $Path
    New-ItemProperty -Path $Path -Name $Name -PropertyType MultiString -Value $Values -Force | Out-Null
    return $true
  } catch { Write-Warn2 "Failed to set $Path -> $Name : $($_.Exception.Message)"; return $false }
}
function Remove-Prop($Path,$Name) {
  try {
    if (Test-Path $Path) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue }
  } catch { }
}

# Enumerate Control\Video nodes and tag vendor
function Get-DisplayRegNodes {
  $root = "HKLM:\SYSTEM\CurrentControlSet\Control\Video"
  $nodes = @()
  if (!(Test-Path $root)) { return $nodes }
  Get-ChildItem $root | Where-Object { $_.PSChildName -match '^\{[0-9A-F-]+\}$' } | ForEach-Object {
    Get-ChildItem $_.PsPath | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
      $p = $_.PsPath
      $props = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
      $matchId = $props.MatchingDeviceId
      $prov    = $props.ProviderName
      $desc    = $props.DriverDesc
      $ven =
        if ($matchId -match "VEN_10DE") { "NVIDIA" }
        elseif ($matchId -match "VEN_1002|VEN_1022") { "AMD" }
        elseif ($matchId -match "VEN_8086") { "Intel" }
        elseif ($prov -match "NVIDIA") { "NVIDIA" }
        elseif ($prov -match "Advanced Micro Devices|AMD") { "AMD" }
        elseif ($prov -match "Intel") { "Intel" }
        elseif ($desc -match "NVIDIA") { "NVIDIA" }
        elseif ($desc -match "AMD|Radeon") { "AMD" }
        elseif ($desc -match "Intel") { "Intel" }
        else { "Unknown" }
      $nodes += [pscustomobject]@{ Path=$p; Vendor=$ven; Desc=$desc }
    }
  }
  return $nodes
}

# ----------------------- Detection ----------------------------------#
Write-Step "Detecting system memory and GPUs"

# RAM
try {
  $cs = Get-CimInstance Win32_ComputerSystem
  $totalRAM_Bytes = [int64]$cs.TotalPhysicalMemory
  $totalRAM_GB    = [math]::Round($totalRAM_Bytes / 1GB, 1)
  Write-OK "Total RAM: $totalRAM_GB GB"
} catch {
  Write-Warn2 "Could not read total RAM."
  $totalRAM_GB = 0
}

# ----------------------- GPU detection (robust VRAM) -----------------#
function Get-NvidiaSmiVramMB {
  $paths = @(
    "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe",
    "C:\Windows\System32\nvidia-smi.exe"
  )
  $exe = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $exe) { return @() }
  try {
    $out = & $exe --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
    return ($out | ForEach-Object { [int]($_.Trim()) })
  } catch { return @() }
}
function Get-NodeVramBytes-FromRegistry($nodePath) {
  try {
    $p = Get-ItemProperty -Path $nodePath -ErrorAction Stop
    $qw = $p."HardwareInformation.qwMemorySize"
    if ($qw -ne $null -and [uint64]$qw -gt 0) { return [uint64]$qw }
    $dw = $p."HardwareInformation.MemorySize"
    if ($dw -ne $null -and [uint32]$dw -gt 0) { return [uint64]([uint32]$dw) }
  } catch {}
  return $null
}
function Get-DxdiagVramMB {
  $tmp = Join-Path $env:TEMP "dxdiag_gmvt.txt"
  try {
    & dxdiag /t $tmp 2>$null | Out-Null
    if (Test-Path $tmp) {
      $txt = Get-Content $tmp -Raw
      $matches = [regex]::Matches($txt, "Dedicated Memory:\s+(\d+)\s*MB", "IgnoreCase")
      if ($matches.Count -gt 0) {
        return ($matches | ForEach-Object { [int]$_.Groups[1].Value })
      }
    }
  } catch {}
  return @()
}

# Build GPU list via WMI first (names & vendors)
$gpuList = @()
try {
  $wmiGpus = Get-CimInstance Win32_VideoController | Sort-Object -Property Name
  foreach ($g in $wmiGpus) {
    $pnp = $g.PNPDeviceID
    $venId = $null
    if ($pnp -match "VEN_([0-9A-F]{4})") { $venId = $Matches[1] }
    $vendor =
      if ($venId -eq "10DE") {"NVIDIA"}
      elseif ($venId -eq "1002" -or $venId -eq "1022") {"AMD"}
      elseif ($venId -eq "8086") {"Intel"}
      else {"Unknown"}
    $gpuList += [pscustomobject]@{
      Name       = $g.Name
      Vendor     = $vendor
      VendorID   = $venId
      PNP        = $pnp
      AdapterRAM = ([int64]($g.AdapterRAM) 2>$null)
      VRAM_GB    = $null
    }
  }
} catch {
  Write-Warn2 "Failed to enumerate GPUs via WMI: $($_.Exception.Message)"
}

if ($gpuList.Count -eq 0) {
  Write-Warn2 "No GPUs detected. Exiting."
  exit 1
}

Write-Info "Detected GPUs:"
$gpuList | ForEach-Object {
  Write-Info (" - {0} [{1}]" -f $_.Name, $_.Vendor)
}

$dGpus = $gpuList | Where-Object { $_.Vendor -in @("NVIDIA","AMD") }
$iGpus = $gpuList | Where-Object { $_.Vendor -eq "Intel" }

if ($iGpus) { Write-OK  ("Intel iGPU present: " + ($iGpus | ForEach-Object {$_.Name}) -join "; ") }
if ($dGpus) { Write-OK  ("dGPU(s): " + ($dGpus  | ForEach-Object {$_.Name}) -join "; ") }
else        { Write-Warn2 "No AMD/NVIDIA dGPU found — VRAM hints will be skipped." }

# Determine VRAM (MB) robustly
$nvMb = @()
if ($dGpus | Where-Object Vendor -eq "NVIDIA") { $nvMb = Get-NvidiaSmiVramMB }

$dispNodes = Get-DisplayRegNodes
$dgpuNodes = $dispNodes | Where-Object { $_.Vendor -in @("NVIDIA","AMD") }
$regMbAll = @()
foreach ($n in $dgpuNodes) {
  $bytes = Get-NodeVramBytes-FromRegistry $n.Path
  if ($bytes -ne $null -and $bytes -gt 0) {
    $regMbAll += [int]([math]::Floor($bytes / 1MB))
  }
}

$dxMb  = Get-DxdiagVramMB

$wmiMb = @()
foreach ($g in $dGpus) {
  if ($g.AdapterRAM -gt 0) { $wmiMb += [int]([math]::Floor($g.AdapterRAM / 1MB)) }
}

$allMb = @()
if ($nvMb.Count -gt 0)     { $allMb += $nvMb }
if ($regMbAll.Count -gt 0) { $allMb += $regMbAll }
if ($dxMb.Count -gt 0)     { $allMb += $dxMb }
if ($wmiMb.Count -gt 0)    { $allMb += $wmiMb }

$maxDgpuVramMB = 0
if ($allMb.Count -gt 0) {
  $maxDgpuVramMB = ($allMb | Measure-Object -Maximum).Maximum
}
if ($ForceVramMB -gt 0) { $maxDgpuVramMB = $ForceVramMB }

foreach ($g in $gpuList) {
  $mb = 0
  if ($g.Vendor -eq "NVIDIA" -and $nvMb.Count -gt 0) { $mb = ($nvMb | Measure-Object -Maximum).Maximum }
  elseif ($regMbAll.Count -gt 0)                       { $mb = ($regMbAll | Measure-Object -Maximum).Maximum }
  elseif ($dxMb.Count -gt 0)                           { $mb = ($dxMb | Measure-Object -Maximum).Maximum }
  elseif ($wmiMb.Count -gt 0)                          { $mb = ($wmiMb | Measure-Object -Maximum).Maximum }
  if ($mb -gt 0) { $g.VRAM_GB = [math]::Round($mb/1024,2) }
}

Write-Info "Resolved VRAM (best available):"
$gpuList | ForEach-Object {
  $vramDisplay = if ($null -ne $_.VRAM_GB) { $_.VRAM_GB } else { "n/a" }
  Write-Info (" - {0} [{1}] VRAM={2} GB" -f $_.Name, $_.Vendor, $vramDisplay)
}

# ----------------------- Actions: Apply ------------------------------#
function Apply-Tweaks {

  # A) RAM-first + I/O reduction
  Write-Step "Applying RAM-first + I/O reduction"
  $mm = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
  $fs = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
  $pf = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"

  # IoPageLockLimit bytes: ~2 MB per GB RAM, clamp [64,256] MB
  $ioMB =  [int][math]::Min(256, [math]::Max(64, [math]::Floor($totalRAM_GB * 2)))
  $ioB  =  [uint32]($ioMB * 1MB)

  Set-Dword $mm "DisablePagingExecutive" 1       | Out-Null
  Set-Dword $mm "LargeSystemCache"       1       | Out-Null
  Set-Dword $mm "ClearPageFileAtShutdown" 0      | Out-Null
  Set-Dword $mm "IoPageLockLimit"        $ioB    | Out-Null

  # Use explicit UInt32 max instead of "-1"
  Set-Dword $mm "NonPagedPoolQuota" ([uint32]::MaxValue) | Out-Null
  Set-Dword $mm "PagedPoolQuota"    ([uint32]::MaxValue) | Out-Null
  Set-Dword $mm "SystemPages"       ([uint32]::MaxValue) | Out-Null

  Set-Dword $fs "NtfsMemoryUsage"        2       | Out-Null
  Set-Dword $pf "EnablePrefetcher"       1       | Out-Null
  Set-Dword $pf "EnableSuperfetch"       0       | Out-Null
  Write-OK ("RAM/I-O registry tuned (IoPageLockLimit = {0} MB)" -f $ioMB)

  # B) GPU scheduling + MPO off
  Write-Step "Configuring GPU scheduling + MPO"
  $gfx = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
  $dwm = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"
  Set-Dword $gfx "HwSchMode" 2 | Out-Null            # HAGS ON
  Set-Dword $dwm "OverlayTestMode" 5 | Out-Null      # MPO OFF
  Write-OK "HAGS on; MPO off"

  # C) Game Mode / Xbox DVR
  Write-Step "Enforcing Game Mode / disabling Xbox DVR (current user)"
  $gb  = "HKCU:\Software\Microsoft\GameBar"
  $gcs = "HKCU:\System\GameConfigStore"
  Set-Dword $gb  "AllowAutoGameMode" 1 | Out-Null
  Set-Dword $gcs "GameDVR_Enabled" 0 | Out-Null
  Set-Dword $gcs "GameDVR_FSEBehaviorMode" 2 | Out-Null
  Set-Dword $gcs "GameDVR_HonorUserFSEBehaviorMode" 1 | Out-Null
  Set-Dword $gcs "GameDVR_DXGIHonorFSEWindowsCompatible" 1 | Out-Null
  Set-Dword $gcs "GameDVR_EFSEFeatureFlags" 0 | Out-Null
  Set-Dword $gcs "GameDVR_FSEBehavior" 2 | Out-Null
  Set-Dword $gcs "GameDVR_HonorFSEWindowsCompatible" 1 | Out-Null
  Write-OK "Game Mode/DVR set for current user"

  # D) (Optional) Network low-latency TCP
  if (-not $SkipNetwork) {
    Write-Step "Applying TCP low-latency tweaks"
    $tcp = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
    Set-Dword $tcp "TcpNoDelay" 1 | Out-Null
    Set-Dword $tcp "TcpAckFrequency" 1 | Out-Null
    Set-Dword $tcp "TcpDelAckTicks" 0 | Out-Null
    Write-OK "TCP tweaks applied"
  } else {
    Write-Info "Skipping network tweaks (user requested)"
  }

  # E) VRAM budgeting hint (DedicatedSegmentSize) for dGPU(s) only
  Write-Step "Setting VRAM budgeting hint (DedicatedSegmentSize) on dGPU(s)"
  if ($maxDgpuVramMB -le 0) {
    Write-Warn2 "Could not determine dGPU VRAM; skipping VRAM hint."
  } else {
    $dispNodes = Get-DisplayRegNodes
    $targetNodes = $dispNodes | Where-Object { $_.Vendor -in @("NVIDIA","AMD") }
    if ($targetNodes.Count -eq 0) {
      Write-Warn2 "No dGPU registry nodes found; skipping."
    } else {
      foreach ($n in $targetNodes) {
        try {
          Ensure-RegKey $n.Path
          # DWORD in MB; e.g., 24 GB => 24576
          New-ItemProperty -Path $n.Path -Name "DedicatedSegmentSize" -PropertyType DWord -Value ([uint32]$maxDgpuVramMB) -Force | Out-Null
          Write-OK ("DedicatedSegmentSize set at {0} -> {1} MB ({2})" -f $n.Path,$maxDgpuVramMB,$n.Desc)
        } catch {
          Write-Warn2 "Failed at $($n.Path) : $($_.Exception.Message)"
        }
      }
    }
  }

  # F) Pagefile: force fixed 1–2 GB on system drive (robust, typed)
  Write-Step "Configuring pagefile (fixed 1024–2048 MB on system drive)"
  try {
    $sysDrive = $env:SystemDrive
    $pfPath   = Join-Path $sysDrive "pagefile.sys"
    $mmKey    = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    $pagingVal = "$pfPath 1024 2048"

    # 1) Registry side
    Set-MultiSZ $mmKey "PagingFiles"       @($pagingVal) | Out-Null
    Set-MultiSZ $mmKey "ExistingPageFiles" @($pfPath)    | Out-Null
    Set-Dword   $mmKey "TempPageFile" 0 | Out-Null

    # 2) Turn off automatic management
    $cs2 = Get-CimInstance -ClassName Win32_ComputerSystem
    if ($cs2.AutomaticManagedPagefile) {
      Set-CimInstance -InputObject $cs2 -Property @{ AutomaticManagedPagefile = $false } | Out-Null
    }

    # 3) WMI pagefile settings: remove existing, then create typed instance
    $existing = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue
    if ($existing) {
      foreach ($e in $existing) { Remove-CimInstance -InputObject $e -ErrorAction SilentlyContinue }
    }

    New-CimInstance -ClassName Win32_PageFileSetting -Property @{
      Name        = $pfPath
      InitialSize = [UInt32]1024
      MaximumSize = [UInt32]2048
    } | Out-Null

    # 4) Fallback via WMIC if needed
    $pfCheck = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object {$_.Name -ieq $pfPath}
    if (-not $pfCheck) {
      & wmic pagefileset where "name='$($pfPath -replace '\\','\\\\')'" set InitialSize=1024,MaximumSize=2048 | Out-Null
    }

    Write-OK "Pagefile pinned at $pfPath (1024 → 2048 MB) and auto-management disabled"
  } catch {
    Write-Warn2 "Pagefile configuration failed: $($_.Exception.Message)"
  }

  # G) Disable Memory Compression
  Write-Step "Disabling Memory Compression (MMAgent)"
  try {
    Disable-MMAgent -mc -ErrorAction SilentlyContinue
    $mma = $null; try { $mma = Get-MMAgent } catch {}
    if ($mma) { Write-OK ("MemoryCompression: " + $mma.MemoryCompression) } else { Write-OK "MemoryCompression: False" }
  } catch { Write-Warn2 "Could not change Memory Compression." }

  Write-Host "`nAll changes queued. **Reboot required** to fully apply." -ForegroundColor Magenta
}

# ----------------------- Actions: Revert -----------------------------#
function Revert-Tweaks {
  Write-Step "Reverting registry changes to defaults/common-safe values"

  $mm  = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
  $fs  = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
  $pfk = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
  $gfx = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
  $dwm = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"
  $gb  = "HKCU:\Software\Microsoft\GameBar"
  $gcs = "HKCU:\System\GameConfigStore"
  $tcp = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"

  Set-Dword $mm "DisablePagingExecutive" 0 | Out-Null
  Set-Dword $mm "LargeSystemCache" 0 | Out-Null
  Set-Dword $mm "ClearPageFileAtShutdown" 0 | Out-Null
  Set-Dword $mm "IoPageLockLimit" 0 | Out-Null
  Set-Dword $mm "NonPagedPoolQuota" 0 | Out-Null
  Set-Dword $mm "PagedPoolQuota" 0 | Out-Null
  Set-Dword $mm "SystemPages" 0 | Out-Null
  Set-Dword $fs "NtfsMemoryUsage" 1 | Out-Null
  Set-Dword $pfk "EnablePrefetcher" 3 | Out-Null
  Set-Dword $pfk "EnableSuperfetch" 3 | Out-Null

  Set-Dword $gfx "HwSchMode" 0 | Out-Null
  Set-Dword $dwm "OverlayTestMode" 0 | Out-Null

  Set-Dword $gb  "AllowAutoGameMode" 1 | Out-Null
  Set-Dword $gcs "GameDVR_Enabled" 1 | Out-Null
  Set-Dword $gcs "GameDVR_FSEBehaviorMode" 0 | Out-Null
  Set-Dword $gcs "GameDVR_HonorUserFSEBehaviorMode" 0 | Out-Null
  Set-Dword $gcs "GameDVR_DXGIHonorFSEWindowsCompatible" 0 | Out-Null
  Set-Dword $gcs "GameDVR_EFSEFeatureFlags" 0 | Out-Null
  Set-Dword $gcs "GameDVR_FSEBehavior" 0 | Out-Null
  Set-Dword $gcs "GameDVR_HonorFSEWindowsCompatible" 0 | Out-Null

  Set-Dword $tcp "TcpNoDelay" 0 | Out-Null
  Set-Dword $tcp "TcpAckFrequency" 0 | Out-Null
  Set-Dword $tcp "TcpDelAckTicks" 2 | Out-Null

  # Remove DedicatedSegmentSize from all adapter nodes
  Write-Step "Removing DedicatedSegmentSize from display registry nodes"
  $dispNodes = Get-DisplayRegNodes
  foreach ($n in $dispNodes) {
    Remove-Prop $n.Path "DedicatedSegmentSize"
  }
  Write-OK "VRAM hint removed"

  # Re-enable auto pagefile management
  Write-Step "Restoring automatic pagefile management"
  try {
    Set-MultiSZ $mm "PagingFiles"       @("") | Out-Null
    Set-MultiSZ $mm "ExistingPageFiles" @("") | Out-Null
    Set-Dword   $mm "TempPageFile" 0 | Out-Null

    $cs3 = Get-CimInstance Win32_ComputerSystem
    if (-not $cs3.AutomaticManagedPagefile) {
      Set-CimInstance -InputObject $cs3 -Property @{ AutomaticManagedPagefile = $true } | Out-Null
    }

    Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue |
      ForEach-Object { Remove-CimInstance -InputObject $_ -ErrorAction SilentlyContinue }

    Write-OK "Automatic pagefile restored (reboot recommended)"
  } catch {
    Write-Warn2 "Could not revert pagefile: $($_.Exception.Message)"
  }

  # Re-enable Memory Compression
  Write-Step "Re-enabling Memory Compression"
  try { Enable-MMAgent -mc | Out-Null } catch {}
  Write-OK "Revert complete. **Reboot recommended**."
}

# ----------------------- Actions: Report -----------------------------#
function Report-State {
  Write-Step "Current state report"

  $mm  = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
  $fs  = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
  $pfk = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"
  $gfx = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
  $dwm = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"
  $gcs = "HKCU:\System\GameConfigStore"

  $mma = $null; try { $mma = Get-MMAgent } catch {}

  $vals = [ordered]@{
    "RAM (GB)"                                   = $totalRAM_GB
    "Max dGPU VRAM for hint (MB)"                = $maxDgpuVramMB
    "DisablePagingExecutive"                     = (Get-ItemProperty -Path $mm -Name DisablePagingExecutive -ErrorAction SilentlyContinue).DisablePagingExecutive
    "LargeSystemCache"                           = (Get-ItemProperty -Path $mm -Name LargeSystemCache -ErrorAction SilentlyContinue).LargeSystemCache
    "IoPageLockLimit (bytes)"                    = (Get-ItemProperty -Path $mm -Name IoPageLockLimit -ErrorAction SilentlyContinue).IoPageLockLimit
    "NtfsMemoryUsage"                            = (Get-ItemProperty -Path $fs -Name NtfsMemoryUsage -ErrorAction SilentlyContinue).NtfsMemoryUsage
    "EnablePrefetcher"                           = (Get-ItemProperty -Path $pfk -Name EnablePrefetcher -ErrorAction SilentlyContinue).EnablePrefetcher
    "EnableSuperfetch"                           = (Get-ItemProperty -Path $pfk -Name EnableSuperfetch -ErrorAction SilentlyContinue).EnableSuperfetch
    "HAGS (HwSchMode)"                           = (Get-ItemProperty -Path $gfx -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
    "MPO (OverlayTestMode)"                      = (Get-ItemProperty -Path $dwm -Name OverlayTestMode -ErrorAction SilentlyContinue).OverlayTestMode
    "GameDVR_Enabled"                            = (Get-ItemProperty -Path $gcs -Name GameDVR_Enabled -ErrorAction SilentlyContinue).GameDVR_Enabled
    "MemoryCompression (MMAgent)"                = if ($mma) { $mma.MemoryCompression } else { "unknown" }
  }

  $vals.GetEnumerator() | ForEach-Object { Write-Info (" - {0} : {1}" -f $_.Key,$_.Value) }

  # Pagefile
  try {
    $cs4 = Get-CimInstance Win32_ComputerSystem
    $pf  = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
    Write-Info (" - AutomaticManagedPagefile : " + $cs4.AutomaticManagedPagefile)
    if ($pf) {
      foreach ($p in $pf) {
        Write-Info (" - PagefileSetting : {0}  Init={1}  Max={2}" -f $p.Name,$p.InitialSize,$p.MaximumSize)
      }
    } else { Write-Info " - PagefileSetting : (none / auto)" }
  } catch {}
}

# ----------------------- Main ---------------------------------------#
if (-not ($Apply -or $Revert -or $Report)) { $Apply = $true }  # default to Apply if unspecified

if ($Apply)  { Apply-Tweaks;  Report-State }
if ($Revert) { Revert-Tweaks; Report-State }
if ($Report) { Report-State }
