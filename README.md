# GameMemVRAM-Tuner

**GameMemVRAM-Tuner** is a set of PowerShell scripts that push Windows into a **RAM-first / VRAM-first mode** and offload junk writes onto a **volatile RAM disk**, giving smoother gaming, reduced stutter, and longer SSD life.  

- 🎮 **GameMemVRAM-Tuner.ps1** — auto-detects system RAM & dGPU VRAM, sets VRAM budgeting hints, enables **HAGS**, disables **MPO/Xbox DVR**, tunes pagefile & cache, and favors RAM over paging.  
- 🖴 **Setup-VolatileIO.ps1** — creates a **4 GB RAM disk (T:)** at boot, redirects TEMP/TMP, Downloads, and browser caches into RAM, with optional **ephemeral browser profiles** for fully volatile sessions.  
- 🔁 Both scripts support **Apply / Revert / Report** modes with verbose, colorized output and safe state tracking so changes can be rolled back cleanly.  

> ⚠️ **Note:** Games ultimately decide how much VRAM/RAM they use. These scripts remove Windows bottlenecks and encourage VRAM/RAM use, but some engines enforce their own limits.

🔁 Both scripts support Apply / Revert / Report modes with verbose, colorized output and safe state tracking.

Two practical Windows scripts to make games lean on **VRAM/RAM** and cut **SSD I/O**:

1) `GameMemVRAM-Tuner.ps1` — tunes Windows to be RAM-first and VRAM-first:
   - Auto-detects RAM & dGPU **VRAM** (skips Intel iGPU)
   - Sets VRAM budgeting hint per dGPU (`DedicatedSegmentSize`)
   - Enables **HAGS**, disables **MPO**, disables **Xbox DVR**
   - Expands I/O page lock limit based on RAM, increases NTFS cache
   - Pins a small, fixed **pagefile (1–2 GB)** to prevent boot warnings
   - Optional low-latency TCP tweaks
   - `-Apply`, `-Revert`, `-Report` modes with colorized, verbose output

2) `Setup-VolatileIO.ps1` — offloads “junk writes” to a **non-persistent RAM disk**:
   - Creates **T:** (4 GB, NTFS) via **ImDisk**, recreates at **boot** (Scheduled Task)
   - Redirects **TEMP/TMP** (system + user) → `T:\Temp`
   - Moves **Downloads** (user known folder) → `T:\Download`
   - Redirects major **browser caches** (Chrome/Edge/Brave/Opera/Firefox) → `T:\cache`
   - Optional **Ephemeral** browser shortcuts (entire profile on T:) for fully volatile sessions
   - `-Apply`, `-Revert`, `-CreateEphemeralBrowserShortcuts`

> **Why this repo?**  
> - Reduce stutter/spikes due to paging & metadata I/O  
> - Push textures/shaders to VRAM (when game/engine allows it)  
> - Dramatically cut random SSD writes from temp/caches  
> - Keep it reversible and transparent

---

## Requirements

- Windows 10/11, **Administrator** rights
- For `Setup-VolatileIO.ps1`: installs **ImDisk** (via winget → choco fallback)
- At least one **NVIDIA/AMD** dGPU for VRAM hints (Intel iGPU is skipped on purpose)

---

## 🚀 Quick Start

Clone or download this repo, open **PowerShell as Administrator**, and run from the `scripts/` folder.

### 1) RAM/VRAM tuning
```powershell
cd .\scripts
.\GameMemVRAM-Tuner.ps1 -Apply
# Reboot when asked
.\GameMemVRAM-Tuner.ps1 -Report
```

### 2) Volatile I/O (Temp/Downloads/Cache on RAM)
```powershell
# Run from repo root (Admin)
cd .\scripts
.\Setup-VolatileIO.ps1 -Apply
# Sign out/in or reboot for Explorer to pick up Downloads path
```

### Optional: Ephemeral browser profiles
```powershell
.\Setup-VolatileIO.ps1 -CreateEphemeralBrowserShortcuts
# Launch via the new shortcuts (profiles + cache live on T:, wiped on reboot)
```

### Safe revert
```powershell
# RAM/VRAM tweaks
.\GameMemVRAM-Tuner.ps1 -Revert

# Volatile I/O / RAM disk, caches, Downloads
.\Setup-VolatileIO.ps1 -Revert
```

## Disclaimer

⚠️ **Important:** These scripts make registry and system-level changes, redirect
folders to volatile storage, and may affect how Windows and your applications
behave. By using them, you accept that:

- All modifications are **at your own risk**.  
- The authors and contributors are **not responsible** for data loss, corruption,
  crashes, or any other damage.  
- Always back up your registry, system, and data before applying.  
- Revert scripts are provided, but not all states may be fully recoverable.

If you are not comfortable with these risks, do **not** use this software.
