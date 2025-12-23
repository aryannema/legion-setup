#requires -Version 5.1
<#
.SYNOPSIS
Creates the recommended Windows dev directory layout on D:\ and sets key USER env vars (idempotent).

.DESCRIPTION
Creates (if missing) the repo’s preferred folder structure so C:\ stays clean:
- D:\dev\repos, tools, envs, cache, tmp
- D:\dev\datasets (optional placeholder)

Also creates:
- Logs:  D:\aryan-setup\logs\
- State: D:\aryan-setup\state-files\   (INI-style key=value .state files; NO JSON)

Writes:
- D:\aryan-setup\state-files\prepare-windows-dev-dirs.state

.PREREQUISITES
- Windows PowerShell 5.1
- D:\ drive exists

.PARAMETER Force
Re-run even if prior state indicates success.

.PARAMETER DevRoot
Root directory (default D:\dev).

.PARAMETER Help
Show help.

.EXAMPLE
setup-aryan prepare-windows-dev-dirs

.EXAMPLE
setup-aryan prepare-windows-dev-dirs -Force
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [switch]$Force,

  [Parameter(Mandatory=$false)]
  [string]$DevRoot = "D:\dev",

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

$ActionName = "prepare-windows-dev-dirs"
$Version    = "1.1.0"

$LogsRoot  = "D:\aryan-setup\logs"
$StateRoot = "D:\aryan-setup\state-files"
$LogFile   = Join-Path $LogsRoot  "$ActionName.log"
$StateFile = Join-Path $StateRoot "$ActionName.state"

function Show-Help { Get-Help -Detailed $MyInvocation.MyCommand.Path }
if ($Help) { Show-Help; exit 0 }

function Get-Stamp {
  try {
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
    $dt = [System.TimeZoneInfo]::ConvertTime((Get-Date), $tz)
    return ("IST {0}" -f $dt.ToString("dd-MM-yyyy HH:mm:ss"))
  } catch {
    return ("IST {0}" -f (Get-Date).ToString("dd-MM-yyyy HH:mm:ss"))
  }
}

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Log {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("Error","Warning","Info","Debug")][string]$Level,
    [Parameter(Mandatory=$true)][string]$Message
  )
  Ensure-Dir -Path $LogsRoot
  Ensure-Dir -Path $StateRoot
  Add-Content -LiteralPath $LogFile -Value "$(Get-Stamp) $Level $Message" -Encoding UTF8
  switch ($Level) {
    "Error"   { Write-Error   $Message }
    "Warning" { Write-Warning $Message }
    "Info"    { Write-Host    $Message }
    "Debug"   { Write-Host    $Message }
  }
}

function Get-ISO8601 { (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK") }

function Read-State {
  if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
  $map = @{}
  $lines = Get-Content -LiteralPath $StateFile -ErrorAction Stop
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
    [Parameter(Mandatory=$true)][string]$Status,
    [Parameter(Mandatory=$true)][int]$Rc,
    [Parameter(Mandatory=$true)][string]$StartedAt,
    [Parameter(Mandatory=$true)][string]$FinishedAt
  )

  $fields = @()
  $fields += "action=$ActionName"
  $fields += "status=$Status"
  $fields += "rc=$Rc"
  $fields += "started_at=$StartedAt"
  $fields += "finished_at=$FinishedAt"
  $fields += "user=$([Environment]::UserName)"
  $fields += "host=$($env:COMPUTERNAME)"
  $fields += "log_path=$LogFile"
  $fields += "version=$Version"

  $tmp = "$StateFile.tmp"
  Set-Content -LiteralPath $tmp -Value $fields -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}

function Ensure-UserEnvVar {
  param([Parameter(Mandatory=$true)][string]$Name, [Parameter(Mandatory=$true)][string]$Value)
  $cur = [Environment]::GetEnvironmentVariable($Name, "User")
  if ($cur -ne $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Write-Log Info "Set USER env var: $Name=$Value"
  } else {
    Write-Log Debug "USER env var already set: $Name=$Value"
  }
}

# ---------------------------
# Main
# ---------------------------
$startedAt = Get-ISO8601
Ensure-Dir -Path $LogsRoot
Ensure-Dir -Path $StateRoot

Write-Log Info "Starting: $ActionName (version=$Version, Force=$Force, DevRoot=$DevRoot)"

try {
  $prev = Read-State
  if ($prev -ne $null -and -not $Force) {
    if ($prev.ContainsKey("status") -and $prev["status"] -eq "success") {
      Write-Log Info "State indicates previous success; skipping. Use -Force to re-run."
      Write-State -Status "skipped" -Rc 0 -StartedAt $startedAt -FinishedAt (Get-ISO8601)
      exit 0
    }
  }
} catch {
  Write-Log Warning "Could not read prior state (continuing): $($_.Exception.Message)"
}

$rc = 0
$status = "success"

try {
  if (-not (Test-Path -LiteralPath "D:\")) { throw "D:\ drive not found." }

  Ensure-Dir -Path $DevRoot

  $dirs = @(
    (Join-Path $DevRoot "repos"),
    (Join-Path $DevRoot "tools"),
    (Join-Path $DevRoot "envs"),
    (Join-Path $DevRoot "cache"),
    (Join-Path $DevRoot "tmp"),
    (Join-Path $DevRoot "datasets")
  )

  foreach ($d in $dirs) { Ensure-Dir -Path $d }

  # Useful defaults for parity
  Ensure-UserEnvVar -Name "DEV_ROOT" -Value $DevRoot

  Write-Log Info "Created/verified dev dirs under: $DevRoot"
} catch {
  $rc = 1
  $status = "failed"
  Write-Log Error $_.Exception.Message
}

$finishedAt = Get-ISO8601
try { Write-State -Status $status -Rc $rc -StartedAt $startedAt -FinishedAt $finishedAt } catch { Write-Log Warning "Failed to write state file: $($_.Exception.Message)" }
exit $rc
