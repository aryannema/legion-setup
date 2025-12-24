#requires -Version 5.1
<#
.SYNOPSIS
Hardened Staging Script. Deploys the legion-setup framework to C:\Tools\aryan-setup\.
Enforces a clean staging area to prevent "ghost" files.
#>

[CmdletBinding()]
param(
  [switch]$Force,
  [string]$TargetRoot = "C:\Tools\aryan-setup",
  [string]$LogsRoot   = "D:\aryan-setup\logs",
  [string]$StateRoot  = "D:\aryan-setup\state-files"
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

# --- Action Identity ---
$ActionName = "stage-windows-setup"
$StateFile  = Join-Path $StateRoot "$ActionName.state"
$LogFile    = Join-Path $LogsRoot  "$ActionName.log"
$RepoRoot   = Resolve-Path (Join-Path $PSScriptRoot "..")
$StartedAt  = (Get-Date).ToString("o")

# --- Helper: IST Logging ---
function Write-StageLog {
    param([string]$Level, [string]$Message)
    if (!(Test-Path $LogsRoot)) { New-Item -ItemType Directory -Path $LogsRoot -Force | Out-Null }
    $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
    $stamp = "IST " + [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz).ToString("dd-MM-yyyy HH:mm:ss")
    Add-Content -LiteralPath $LogFile -Value "$stamp $Level $Message" -Encoding UTF8
    Write-Host "[$Level] $Message"
}

# --- Main Logic ---
try {
    Write-StageLog Info "Starting Staging: $ActionName (Force=$Force)"

    # 1. Drive Check
    if (!(Test-Path "D:\")) { throw "D: Drive not found. Storage policy requires D: for logs/state." }

    # 2. Cleanup Staged Folders (Prevent Ghost Files)
    # This mirrors the Linux 'rsync --delete' behavior.
    $stagedBin     = Join-Path $TargetRoot "bin"
    $stagedActions = Join-Path $TargetRoot "actions"

    foreach ($dir in @($stagedBin, $stagedActions)) {
        if (Test-Path $dir) {
            Write-StageLog Info "Cleaning old staged folder: $dir"
            Remove-Item -Path $dir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # 3. Copy Fresh Binaries and Actions
    $srcBin     = Join-Path $RepoRoot "windows-setup\bin"
    $srcActions = Join-Path $RepoRoot "windows-setup\actions"

    Write-StageLog Info "Staging fresh files from $RepoRoot"
    Copy-Item -Path (Join-Path $srcBin "*") -Destination $stagedBin -Force
    Copy-Item -Path (Join-Path $srcActions "*") -Destination $stagedActions -Force

    # 4. Write Aryan-Standard State (INI Format)
    $stateFields = @(
        "action=$ActionName",
        "status=success",
        "rc=0",
        "started_at=$StartedAt",
        "finished_at=$((Get-Date).ToString('o'))",
        "target_root=$TargetRoot",
        "user=$env:USERNAME"
    )
    Set-Content -LiteralPath $StateFile -Value $stateFields -Encoding UTF8

    Write-StageLog Info "Staging Complete. Framework ready at $TargetRoot."
}
catch {
    Write-StageLog Error "Staging Failed: $($_.Exception.Message)"
    exit 1
}