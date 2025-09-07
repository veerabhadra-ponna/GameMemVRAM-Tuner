#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    GameMemVRAM-Tuner Ultimate v3.0 - Launcher Script

.DESCRIPTION
    Convenience launcher for GameMemVRAM-Tuner Ultimate from the root directory.
    This script simply calls the main script in the scripts folder.

.EXAMPLE
    .\GameMemVRAM-Tuner-Ultimate.ps1
    # Launches interactive UI

.EXAMPLE
    .\GameMemVRAM-Tuner-Ultimate.ps1 -Mode Apply -Profile Gaming
    # Apply gaming profile optimizations
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("UI", "Apply", "Rollback", "Report", "Backup", "Restore")]
    [string]$Mode = "UI",
    
    [Parameter()]
    [ValidateSet("Gaming", "Balanced", "Conservative", "Custom")]
    [string]$Profile = "Gaming",
    
    [Parameter()]
    [string]$ConfigFile,
    
    [Parameter()]
    [string]$BackupPath,
    
    [Parameter()]
    [ValidateSet('Error', 'Warn', 'Info', 'Debug')]
    [string]$LogLevel = 'Info',
    
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [switch]$WhatIf
)

# Forward all parameters to the main script
$scriptPath = Join-Path $PSScriptRoot "scripts\GameMemVRAM-Tuner-Ultimate.ps1"

if (Test-Path $scriptPath) {
    $params = @{}
    if ($Mode) { $params.Mode = $Mode }
    if ($Profile) { $params.Profile = $Profile }
    if ($ConfigFile) { $params.ConfigFile = $ConfigFile }
    if ($BackupPath) { $params.BackupPath = $BackupPath }
    if ($LogLevel) { $params.LogLevel = $LogLevel }
    if ($Force) { $params.Force = $true }
    if ($WhatIf) { $params.WhatIf = $true }
    
    & $scriptPath @params
}
else {
    Write-Error "Main script not found: $scriptPath"
    Write-Host "Please ensure you're running this from the GameMemVRAM-Tuner root directory." -ForegroundColor Yellow
}