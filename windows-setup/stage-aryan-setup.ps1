#requires -Version 5.1
<#
.SYNOPSIS
Stages the Windows "setup-aryan" framework from this repo into C:\Tools\aryan-setup\ and prepares logging + state directories on D:\.

.DESCRIPTION
- Copies windows-setup\bin and windows-setup\actions into C:\Tools\aryan-setup\ (idempotent).
- Ensures logs directory exists: D:\aryan-setup\logs\
- Ensures state-files directory exists: D:\aryan-setup\state-files\
- Writes a state file for this action (NO JSON): D:\aryan-setup\state-files\stage-windows-setup.state
- Creates convenience launchers in C:\Tools\aryan-setup\bin\ :
  - setup-aryan.cmd
  - setup-aryan-log.cmd
- Optionally adds C:\Tools\aryan-setup\bin to USER PATH (safe + idempotent).

.PREREQUISITES
- Windows PowerShell 5.1
- Run from within the cloned repo.
- D:\ drive present (repo storage policy).

.PARAMETER Force
Re-run staging even if the state-file indicates a previous success.

.PARAMETER TargetRoot
Where to stage the framework (default: C:\Tools\aryan-setup).

.PARAMETER LogsRoot
Where logs live (default: D:\aryan-setup\logs).

.PARAMETER StateRoot
Where state-files live (default: D:\aryan-setup\state-files).

.PARAMETER NoPathUpdate
Do not attempt to add the staged bin directory to the USER PATH.

.PARAMETER Help
Show help.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\windows-setup\stage-aryan-setup.ps1

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\windows-setup\stage-aryan-setup.ps1 -Force

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\windows-setup\stage-aryan-setup.ps1 -NoPathUpdate
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [switch]$Force,

  [Parameter(Mandatory=$false)]
  [string]$TargetRoot = "C:\Tools\aryan-setup",

  [Parameter(Mandatory=$false)]
  [string]$LogsRoot = "D:\aryan-setup\logs",

  [Parameter(Mandatory=$false)]
  [string]$StateRoot = "D:\aryan-setup\state-files",

  [Parameter(Mandatory=$false)]
  [switch]$NoPathUpdate,

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

function Show-Help { Get-Help -Detailed $MyInvocation.MyCommand.Path }
if ($Help) { Show-Help; exit 0 }

# ---------------------------
# Action identity + paths
# ---------------------------
$ActionName = "stage-windows-setup"
$StateFile  = Join-Path $StateRoot "$ActionName.state"
$LogPath    = Join-Path $LogsRoot  "$ActionName.log"

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-ISTStamp {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
  $nowIst = [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz)
  return "IST " + $nowIst.ToString("dd-MM-yyyy HH:mm:ss")
}

function Write-Log {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("Error","Warning","Info","Debug")][string]$Level,
    [Parameter(Mandatory=$true)][string]$Message
  )
  Ensure-Dir -Path $LogsRoot
  $line = "{0} {1} {2}" -f (Get-ISTStamp), $Level, $Message
  Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
  switch ($Level) {
    "Error"   { Write-Error   $Message }
    "Warning" { Write-Warning $Message }
    "Info"    { Write-Host    $Message }
    "Debug"   { Write-Host    $Message }
  }
}

function Get-ISO8601 { (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK") }

function Get-RepoVersion {
  param([Parameter(Mandatory=$true)][string]$RepoRoot)
  try {
    $git = Get-Command git -ErrorAction Stop
    $hash = & $git.Source -C $RepoRoot rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $hash) { return "git-$hash" }
  } catch { }
  return "unknown"
}

function Read-State {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $map = @{}
  $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
  foreach ($ln in $lines) {
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    if ($ln.TrimStart().StartsWith("#")) { continue }
    $idx = $ln.IndexOf("=")
    if ($idx -lt 1) { continue }
    $k = $ln.Substring(0, $idx).Trim()
    $v = $ln.Substring($idx + 1).Trim()
    if ($k.Length -gt 0) { $map[$k] = $v }
  }
  return $map
}

function Write-State {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][hashtable]$Fields
  )
  Ensure-Dir -Path (Split-Path -Parent $Path)
  $content = @()
  $content += "action=$($Fields.action)"
  $content += "status=$($Fields.status)"
  $content += "rc=$($Fields.rc)"
  $content += "started_at=$($Fields.started_at)"
  $content += "finished_at=$($Fields.finished_at)"
  $content += "user=$($Fields.user)"
  $content += "host=$($Fields.host)"
  $content += "log_path=$($Fields.log_path)"
  $content += "version=$($Fields.version)"

  $tmp = "$Path.tmp"
  Set-Content -LiteralPath $tmp -Value $content -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Copy-Tree {
  param(
    [Parameter(Mandatory=$true)][string]$SourceDir,
    [Parameter(Mandatory=$true)][string]$DestDir
  )
  if (-not (Test-Path -LiteralPath $SourceDir)) { throw "Source directory not found: $SourceDir" }
  Ensure-Dir -Path $DestDir
  Copy-Item -Path (Join-Path $SourceDir "*") -Destination $DestDir -Recurse -Force -ErrorAction Stop
}

function Write-TextFileIfDifferent {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Content
  )
  $needWrite = $true
  if (Test-Path -LiteralPath $Path) {
    try {
      $existing = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
      if ($existing -eq $Content) { $needWrite = $false }
    } catch { $needWrite = $true }
  }
  if ($needWrite) {
    Ensure-Dir -Path (Split-Path -Parent $Path)
    Set-Content -LiteralPath $Path -Value $Content -Encoding ASCII
  }
}

function Add-ToUserPath {
  param([Parameter(Mandatory=$true)][string]$DirToAdd)

  $current = [Environment]::GetEnvironmentVariable("Path","User")
  if ([string]::IsNullOrWhiteSpace($current)) { $current = "" }

  $parts = $current.Split(";") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  $exists = $false
  foreach ($p in $parts) {
    if ($p.TrimEnd("\") -ieq $DirToAdd.TrimEnd("\")) { $exists = $true; break }
  }

  if (-not $exists) {
    $new = if ($current.Trim().EndsWith(";") -or $current.Trim().Length -eq 0) { "$current$DirToAdd" } else { "$current;$DirToAdd" }
    [Environment]::SetEnvironmentVariable("Path","$new","User")
    Write-Log -Level Info -Message "Added to USER PATH: $DirToAdd"
    Write-Log -Level Info -Message "Open a new terminal for PATH changes to take effect."
  } else {
    Write-Log -Level Debug -Message "USER PATH already contains: $DirToAdd"
  }
}

# ---------------------------
# Main
# ---------------------------
if (-not (Test-Path -LiteralPath "D:\")) {
  Write-Error "D:\ drive not found. Repo policy expects logs/state on D:\."
  exit 1
}

Ensure-Dir -Path $LogsRoot
Ensure-Dir -Path $StateRoot

$StartedAt = Get-ISO8601
$UserName  = [Environment]::UserName
$HostName  = $env:COMPUTERNAME
$RepoRoot  = Resolve-Path (Join-Path $PSScriptRoot "..") | Select-Object -ExpandProperty Path
$Version   = Get-RepoVersion -RepoRoot $RepoRoot

Write-Log -Level Info -Message "Starting: $ActionName"
Write-Log -Level Info -Message "RepoRoot: $RepoRoot"
Write-Log -Level Info -Message "TargetRoot: $TargetRoot"
Write-Log -Level Info -Message "LogsRoot: $LogsRoot"
Write-Log -Level Info -Message "StateRoot: $StateRoot"
Write-Log -Level Info -Message "Version: $Version"
Write-Log -Level Info -Message "Force: $Force"

# Idempotency gate: if previous success and no -Force, skip
try {
  $prev = Read-State -Path $StateFile
  if ($prev -ne $null -and -not $Force) {
    if ($prev.ContainsKey("status") -and $prev["status"] -eq "success") {
      Write-Log -Level Info -Message "State indicates previous success; skipping staging. Use -Force to re-run."
      $FinishedAt = Get-ISO8601
      Write-State -Path $StateFile -Fields @{
        action      = $ActionName
        status      = "skipped"
        rc          = 0
        started_at  = $StartedAt
        finished_at = $FinishedAt
        user        = $UserName
        host        = $HostName
        log_path    = $LogPath
        version     = $Version
      }
      exit 0
    }
  }
} catch {
  Write-Log -Level Warning -Message "Failed to read previous state (continuing): $($_.Exception.Message)"
}

$rc = 0
$status = "success"

try {
  Ensure-Dir -Path $TargetRoot
  $stagedBin     = Join-Path $TargetRoot "bin"
  $stagedActions = Join-Path $TargetRoot "actions"

  Ensure-Dir -Path $stagedBin
  Ensure-Dir -Path $stagedActions

  $srcWinSetup = Join-Path $RepoRoot "windows-setup"
  $srcBin      = Join-Path $srcWinSetup "bin"
  $srcActions  = Join-Path $srcWinSetup "actions"

  if (Test-Path -LiteralPath $srcBin) {
    Write-Log -Level Info -Message "Copying bin -> $stagedBin"
    Copy-Tree -SourceDir $srcBin -DestDir $stagedBin
  } else {
    Write-Log -Level Warning -Message "No windows-setup\bin found at: $srcBin (continuing)"
  }

  if (Test-Path -LiteralPath $srcActions) {
    Write-Log -Level Info -Message "Copying actions -> $stagedActions"
    Copy-Tree -SourceDir $srcActions -DestDir $stagedActions
  } else {
    Write-Log -Level Warning -Message "No windows-setup\actions found at: $srcActions (continuing)"
  }

  # CMD shims (optional convenience)
  $cmdSetupAryan = @"
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-aryan.ps1" %*
endlocal
"@
  $cmdSetupAryanLog = @"
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-aryan-log.ps1" %*
endlocal
"@

  Write-Log -Level Info -Message "Ensuring CMD shims in staged bin"
  Write-TextFileIfDifferent -Path (Join-Path $stagedBin "setup-aryan.cmd") -Content $cmdSetupAryan
  Write-TextFileIfDifferent -Path (Join-Path $stagedBin "setup-aryan-log.cmd") -Content $cmdSetupAryanLog

  if (-not $NoPathUpdate) {
    Add-ToUserPath -DirToAdd $stagedBin
  } else {
    Write-Log -Level Info -Message "NoPathUpdate set; skipping PATH modification."
  }

  Write-Log -Level Info -Message "Staging complete."
  Write-Log -Level Info -Message "Try: setup-aryan list"
} catch {
  $rc = 1
  $status = "failed"
  Write-Log -Level Error -Message "Staging failed: $($_.Exception.Message)"
}

$FinishedAt = Get-ISO8601
try {
  Write-State -Path $StateFile -Fields @{
    action      = $ActionName
    status      = $status
    rc          = $rc
    started_at  = $StartedAt
    finished_at = $FinishedAt
    user        = $UserName
    host        = $HostName
    log_path    = $LogPath
    version     = $Version
  }
} catch {
  Write-Log -Level Warning -Message "Failed to write state file: $($_.Exception.Message)"
}

exit $rc
