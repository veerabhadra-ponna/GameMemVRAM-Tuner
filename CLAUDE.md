# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GameMemVRAM-Tuner is a production-grade Windows system optimization tool designed to enhance gaming performance through intelligent memory management, GPU optimization, and advanced system tuning. The project consists of PowerShell scripts that make registry modifications to optimize Windows 10/11 systems for gaming.

## Architecture & Components

### Core Scripts

- **`scripts/GameMemVRAM-Tuner-Production.ps1`**: Main optimization script with comprehensive functionality including:
  - Hardware detection (RAM, GPU, VRAM)
  - Registry modifications for memory, graphics, gaming, and network optimizations
  - Backup/restore functionality
  - Configuration file support
  - Comprehensive error handling and logging

- **`scripts/Install-GameMemVRAMTuner.ps1`**: Installation script that:
  - Sets up scheduled tasks for automatic optimization
  - Creates shortcuts and Start Menu entries
  - Configures performance monitoring
  - Validates system compatibility

- **`scripts/Gaming_Performance_Optimizer.ps1`**: Additional optimization script focusing on:
  - ETW (Event Tracing for Windows) cleanup
  - Telemetry service management
  - System verification and rollback capabilities

### Configuration System

- **`config/default-config.json`**: JSON-based configuration with sections for:
  - Memory management settings
  - Graphics/GPU optimizations
  - Gaming-specific tweaks
  - Network latency optimizations
  - Pagefile configuration
  - Multiple optimization profiles (Gaming, Balanced, Conservative)

## Common Commands

### Primary Operations
```powershell
# Apply optimizations (most common command)
.\scripts\GameMemVRAM-Tuner-Production.ps1 -Apply

# Preview changes without applying
.\scripts\GameMemVRAM-Tuner-Production.ps1 -Apply -WhatIf

# Generate system report
.\scripts\GameMemVRAM-Tuner-Production.ps1 -Report

# Revert all changes
.\scripts\GameMemVRAM-Tuner-Production.ps1 -Revert
```

### Backup & Recovery
```powershell
# Create system backup
.\scripts\GameMemVRAM-Tuner-Production.ps1 -Backup -BackupPath "C:\Backup"

# Restore from backup
.\scripts\GameMemVRAM-Tuner-Production.ps1 -Restore -BackupPath "C:\Backup"
```

### Installation
```powershell
# Full installation with all features
.\scripts\Install-GameMemVRAMTuner.ps1 -CreateScheduledTask -CreateShortcuts -EnableMonitoring
```

### Advanced Usage
```powershell
# Apply with custom VRAM override and skip network optimizations
.\scripts\GameMemVRAM-Tuner-Production.ps1 -Apply -ForceVramMB 8192 -SkipNetwork

# Use custom configuration profile
.\scripts\GameMemVRAM-Tuner-Production.ps1 -Apply -ConfigFile ".\config\custom-config.json"

# Debug logging
.\scripts\GameMemVRAM-Tuner-Production.ps1 -Apply -LogLevel Debug
```

## Key Technical Details

### Script Requirements
- Windows 10/11 with PowerShell 5.1+
- Administrator privileges (enforced via `#Requires -RunAsAdministrator`)
- Scripts use advanced parameter validation and comprehensive error handling

### Optimization Categories
1. **Memory Management**: DisablePagingExecutive, LargeSystemCache, IoPageLockLimit optimization
2. **Graphics**: Hardware GPU Scheduling (HAGS), Multi-Plane Overlay (MPO) control, VRAM budgeting
3. **Gaming**: Game Mode enhancement, Xbox Game DVR disabling
4. **Network**: TCP low-latency tweaks for competitive gaming
5. **Storage**: Dynamic pagefile sizing, memory compression management

### Safety Features
- Automatic registry backup before changes
- Transaction-like operations with rollback capabilities
- System compatibility validation
- WhatIf mode for previewing changes
- Comprehensive logging with multiple levels (Error/Warn/Info/Debug)

## Development Notes

When working with this codebase:
- All scripts require Administrator elevation
- Configuration changes are JSON-based and validated
- The tool supports multiple deployment scenarios (desktop, enterprise, automation)
- Logging is comprehensive and follows structured patterns
- Registry modifications are carefully validated and backed up
- Hardware detection uses multiple fallback methods (nvidia-smi, registry, dxdiag)

## File Structure Context
- `scripts/` contains the main PowerShell scripts
- `config/` contains JSON configuration files with optimization profiles
- All scripts follow enterprise-grade patterns with comprehensive error handling
- The project emphasizes safety through backup/restore functionality and system validation