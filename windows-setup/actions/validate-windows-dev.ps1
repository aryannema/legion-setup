<#
.SYNOPSIS
Validates the Windows-side "legion-setup" dev workstation expectations (non-destructive).

.DESCRIPTION
Checks (best-effort):
- Running on Windows PowerShell 5.1 (version consistency rule)
- D:\ exists (repo policy: logs/state live on D:\)
- Required logging + state directories exist (creates them if missing; safe)
- Staged framework exists (C:\Tools\aryan-setup\bin + actions)
- Basic tooling presence (git, wsl) if available
- WSL config file existence and (optionally) shows configured memory limits

Writes:
- Log:   D:\aryan-setup\logs\validate-windows-dev.log
- State: D:\aryan-setup\state-files\validate-windows-dev.state   (INI key=value, NO JSON)

Idempotency:
- If previous state indicates success, script will SKIP unless -Force is provided.

.PREREQUISITES
- Windows PowerShell 5.1
- D:\ available (per repo storage layout)
- Prefer running after staging: .\windows-setup\stage-aryan-setup.ps1

.PARAMETER Force
Re-run validation even if last run succeeded.

.PARAMETER Help
Show help.

.EXAMPLE
setup-aryan validate-windows-dev

.EXAMPLE
setup-aryan validate-windows-dev -Force
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [switch]$Force,

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

function Show-Help {
  Get-Help -Detailed $MyInvocation.MyCommand.Path
}

if ($Help) { Show-Help; exit 0 }

# ---------------------------
# Constants
# ---------------------------
$ActionName = "validate-windows-dev"
$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$StateFile  = Join-Path $StateRoot "$ActionName.state"
$LogPath    = Join-Path $LogsRoot  "$ActionName.log"

$StagedRoot   = "C:\Tools\aryan-setup"
$StagedBin    = Join-Path $StagedRoot "bin"
$StagedActions= Join-Path $StagedRoot "actions"
$WslConfig    = Join-Path $env:USERPROFILE ".wslconfig"

# ---------------------------
# Logging helpers
# ---------------------------
function Get-TzOffsetString {
  $offset = [System.TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now)
  $sign = if ($offset.TotalMinutes -ge 0) { "+" } else { "-" }
  $hh = [Math]::Abs([int]$offset.Hours).ToString("00")
  $mm = [Math]::Abs([int]$offset.Minutes).ToString("00")
  return "$sign$hh`:$mm"
}

function Get-Stamp {
  $tz = Get-TzOffsetString
  $dt = Get-Date
  return ("{0} {1}" -f $tz, $dt.ToString("dd-MM-yyyy HH:mm:ss"))
}

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-LogLine {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("Error","Warning","Info","Debug")][string]$Level,
    [Parameter(Mandatory=$true)][string]$Message
  )
  $line = "{0} {1} {2}" -f (Get-Stamp), $Level, $Message
  Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
  switch ($Level) {
    "Error"   { Write-Error   $Message }
    "Warning" { Write-Warning $Message }
    "Info"    { Write-Host    $Message }
    "Debug"   { Write-Host    $Message }
  }
}

# ---------------------------
# State helpers (key=value; NO JSON)
# ---------------------------
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

function Get-ISO8601 {
  (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
}

function Get-Version {
  # Simple, stable string for now. If you add VERSION file later, this can read it.
  return "1.0.0"
}

# ---------------------------
# Begin
# ---------------------------
Ensure-Dir -Path $LogsRoot
Ensure-Dir -Path $StateRoot

$StartedAt = Get-ISO8601
$UserName  = [Environment]::UserName
$HostName  = $env:COMPUTERNAME
$Version   = Get-Version

Write-LogLine -Level Info -Message "Starting validation: $ActionName"
Write-LogLine -Level Info -Message "Force: $Force"
Write-LogLine -Level Info -Message "LogsRoot: $LogsRoot"
Write-LogLine -Level Info -Message "StateRoot: $StateRoot"

# Idempotency: if last success and not forced, skip
try {
  $prev = Read-State -Path $StateFile
  if ($prev -ne $null -and -not $Force) {
    if ($prev.ContainsKey("status") -and $prev["status"] -eq "success") {
      Write-LogLine -Level Info -Message "Previous state was success; skipping. Use -Force to re-run."
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
  Write-LogLine -Level Warning -Message "Could not read previous state (continuing): $($_.Exception.Message)"
}

$rc = 0
$status = "success"

try {
  # 1) D:\ presence
  if (-not (Test-Path -LiteralPath "D:\")) {
    throw "D:\ not found. Repo policy expects logs/state on D:\ (verify disk layout / drive letters)."
  }
  Write-LogLine -Level Info -Message "D:\ detected."

  # 2) PowerShell version (must be 5.1)
  $psv = $PSVersionTable.PSVersion
  $psStr = "{0}.{1}.{2}.{3}" -f $psv.Major, $psv.Minor, $psv.Build, $psv.Revision
  Write-LogLine -Level Info -Message "PowerShell version: $psStr"
  if (-not ($psv.Major -eq 5 -and $psv.Minor -eq 1)) {
    throw "PowerShell version mismatch. Expected Windows PowerShell 5.1, got: $psStr"
  }

  # 3) Staged framework
  if (-not (Test-Path -LiteralPath $StagedRoot)) {
    Write-LogLine -Level Warning -Message "Staged root not found: $StagedRoot (run windows-setup\stage-aryan-setup.ps1)"
  } else {
    Write-LogLine -Level Info -Message "Staged root present: $StagedRoot"
  }

  if (-not (Test-Path -LiteralPath $StagedBin)) {
    Write-LogLine -Level Warning -Message "Staged bin missing: $StagedBin"
  } else {
    Write-LogLine -Level Info -Message "Staged bin present: $StagedBin"
  }

  if (-not (Test-Path -LiteralPath $StagedActions)) {
    Write-LogLine -Level Warning -Message "Staged actions missing: $StagedActions"
  } else {
    Write-LogLine -Level Info -Message "Staged actions present: $StagedActions"
  }

  # 4) Tooling (best-effort)
  try {
    $git = Get-Command git -ErrorAction Stop
    Write-LogLine -Level Info -Message "git: OK ($($git.Source))"
  } catch {
    Write-LogLine -Level Warning -Message "git not found in PATH (recommended)."
  }

  try {
    $wsl = Get-Command wsl -ErrorAction Stop
    Write-LogLine -Level Info -Message "wsl: OK ($($wsl.Source))"
    # If WSL exists, try to show distro list (non-fatal)
    try {
      $out = & $wsl.Source --list --verbose 2>$null
      if ($LASTEXITCODE -eq 0 -and $out) {
        Write-LogLine -Level Info -Message "WSL distros (wsl --list --verbose):"
        foreach ($ln in $out) { Write-LogLine -Level Info -Message ("  " + $ln) }
      }
    } catch { }
  } catch {
    Write-LogLine -Level Warning -Message "wsl not found (if you plan WSL2, install/enable it)."
  }

  # 5) .wslconfig (informational)
  if (Test-Path -LiteralPath $WslConfig) {
    Write-LogLine -Level Info -Message ".wslconfig found: $WslConfig"
    try {
      $cfg = Get-Content -LiteralPath $WslConfig -ErrorAction Stop
      # Print a small subset for visibility (safe)
      Write-LogLine -Level Info -Message ".wslconfig (first 40 lines):"
      $i = 0
      foreach ($ln in $cfg) {
        $i++
        Write-LogLine -Level Info -Message ("  " + $ln)
        if ($i -ge 40) { break }
      }
    } catch {
      Write-LogLine -Level Warning -Message "Could not read .wslconfig: $($_.Exception.Message)"
    }
  } else {
    Write-LogLine -Level Warning -Message ".wslconfig not found at $WslConfig (optional, but recommended to cap WSL memory)."
  }

  Write-LogLine -Level Info -Message "Validation completed."
} catch {
  $rc = 1
  $status = "failed"
  Write-LogLine -Level Error -Message "Validation failed: $($_.Exception.Message)"
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
  Write-LogLine -Level Warning -Message "Failed to write state file: $($_.Exception.Message)"
}

exit $rc
