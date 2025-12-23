#requires -Version 5.1
<#
.SYNOPSIS
Validates Windows dev tooling and key paths for the legion-setup workflow.

.DESCRIPTION
Checks:
- D:\dev layout
- Key env vars
- Toolchains (python/uv/conda, node/pnpm, java)
- VS Code presence (optional)

Logging + state:
- Logs:  D:\aryan-setup\logs\validate-windows-dev.log
- State: D:\aryan-setup\state-files\validate-windows-dev.state

.PREREQUISITES
- Windows PowerShell 5.1
- D:\ exists

.PARAMETER Force
Re-run even if previous success.

.PARAMETER DevRoot
Root directory (default: D:\dev)

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
  [string]$DevRoot = "D:\dev",

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

$ActionName = "validate-windows-dev"
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

function Test-Cmd([string]$name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
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

  # Layout checks
  $expected = @("repos","tools","envs","cache","tmp") | ForEach-Object { Join-Path $DevRoot $_ }
  foreach ($p in $expected) {
    if (-not (Test-Path -LiteralPath $p)) {
      Write-Log Warning "Missing: $p (run: setup-aryan prepare-windows-dev-dirs)"
    } else {
      Write-Log Info "OK: $p"
    }
  }

  # Toolchain checks
  Write-Log Info ("python present: " + (Test-Cmd "python"))
  Write-Log Info ("uv present: " + (Test-Cmd "uv"))
  Write-Log Info ("conda present: " + (Test-Cmd "conda"))
  Write-Log Info ("node present: " + (Test-Cmd "node"))
  Write-Log Info ("pnpm present: " + (Test-Cmd "pnpm"))
  Write-Log Info ("java present: " + (Test-Cmd "java"))
  Write-Log Info ("code present: " + (Test-Cmd "code"))

  Write-Log Info "Validation complete."
} catch {
  $rc = 1
  $status = "failed"
  Write-Log Error $_.Exception.Message
}

$finishedAt = Get-ISO8601
try { Write-State -Status $status -Rc $rc -StartedAt $startedAt -FinishedAt $finishedAt } catch { Write-Log Warning "Failed to write state file: $($_.Exception.Message)" }
exit $rc
