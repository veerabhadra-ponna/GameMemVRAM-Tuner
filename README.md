# GameMemVRAM-Tuner

GameMemVRAM-Tuner is a single PowerShell script that tunes Windows 10/11 into a RAM-first / VRAM-first configuration to reduce paging and smooth out gameplay. It auto-detects RAM and dGPU VRAM, applies reversible OS tweaks, and provides Apply / Revert / Report modes with color output.

Note: Games and engines ultimately control RAM/VRAM use. This script removes common OS bottlenecks and encourages VRAM/RAM usage; it cannot override game-enforced limits.

---

## What It Does

- RAM/I-O: increases cache usage and raises I/O page lock limit based on total RAM.
- GPU: enables HAGS and disables MPO; disables Xbox Game DVR and enforces Game Mode.
- VRAM hint: sets `DedicatedSegmentSize` for NVIDIA/AMD dGPUs (skips Intel iGPU).
- Pagefile: pins a small, fixed pagefile (1024–2048 MB) on the system drive.
- Network (optional): applies low-latency TCP registry knobs, or skip with `-SkipNetwork`.
- Modes: `-Apply`, `-Revert`, and `-Report` with clear, colored output.

---

## Requirements

- Windows 10/11
- PowerShell (run as Administrator)
- NVIDIA or AMD dGPU recommended for VRAM hint (Intel iGPU is intentionally skipped)

Optional detection helpers:
- `nvidia-smi` on NVIDIA systems (the script falls back to registry, dxdiag, and WMI)

---

## Quick Start

Run from the `scripts/` folder in an elevated PowerShell.

```powershell
cd .\scripts
.\GameMemVRAM-Tuner.ps1 -Apply       # Applies tweaks; prompts to reboot
.\GameMemVRAM-Tuner.ps1 -Report      # Shows current state
.\GameMemVRAM-Tuner.ps1 -Revert      # Restores defaults/common-safe values
```

Useful options:
- `-SkipNetwork` to avoid applying TCP tweaks
- `-ForceVramMB <int>` to override detected dGPU VRAM for the budgeting hint

---

## Changes Applied (Apply)

- Memory/I-O
  - `DisablePagingExecutive=1`, `LargeSystemCache=1`
  - `IoPageLockLimit` ≈ 2 MB per GB RAM (clamped 64–256 MB)
  - `NtfsMemoryUsage=2`
  - Prefetch: `EnablePrefetcher=1`, `EnableSuperfetch=0`
- GPU/UI
  - HAGS: `GraphicsDrivers\HwSchMode=2`
  - MPO off: `Dwm\OverlayTestMode=5`
- Game DVR / Game Mode (current user)
  - Enables Game Mode and disables Xbox DVR keys under `GameConfigStore`
- Network (unless `-SkipNetwork`)
  - `TcpNoDelay=1`, `TcpAckFrequency=1`, `TcpDelAckTicks=0`
- VRAM budgeting hint (dGPU only)
  - Sets `DedicatedSegmentSize` (MB) on AMD/NVIDIA adapter registry nodes
- Pagefile
  - Disables auto-management, creates typed `Win32_PageFileSetting` for `pagefile.sys`
  - InitialSize=1024, MaximumSize=2048 (with WMIC fallback)
- Memory Compression
  - Disables Memory Compression (MMAgent)

Reboot is recommended after Apply to fully activate changes.

---

## Revert Behavior (Revert)

- Restores Memory/I-O and Prefetch parameters to default/common-safe values
- HAGS to `0`, MPO overlay test mode to `0`
- Re-enables Game DVR defaults and keeps Game Mode allowed
- Network: resets TCP keys to defaults (`TcpNoDelay=0`, etc.)
- Removes `DedicatedSegmentSize` from all display adapter nodes
- Restores automatic pagefile management and removes explicit pagefile settings
- Re-enables Memory Compression

---

## Disclaimer

- Changes are system-level and at your own risk.
- Always back up your system/registry before applying tweaks.
- A revert path is provided, but not all system states are guaranteed recoverable.

If you are not comfortable with these risks, do not use this software.
