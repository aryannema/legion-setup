#requires -Version 5.1
<#
.SYNOPSIS
Ensures Node.js LTS + pnpm (via Corepack) with Linux parity (nvm-first) on Windows PowerShell 5.1.

.DESCRIPTION
Linux installs Node via nvm; for Windows parity this action expects **nvm-windows** to be present.
This action:
- Ensures Node.js LTS is installed via nvm-windows (if Node is not already present).
- Enables Corepack and activates pnpm.
- Pins caches/stores to D:\dev\cache\* and PNPM_HOME to D:\dev\tools\pnpm.

Logging + state (repo standard):
- Logs:  D:\aryan-setup\logs\install-node-toolchain-windows.log
- State: D:\aryan-setup\state-files\install-node-toolchain-windows.state   (INI-style key=value, UTF-8; NO JSON)

Force semantics:
- Default: if prior state is success, skip safely
- -Force: re-run and refresh configuration

.PREREQUISITES
- Windows 11
- Windows PowerShell 5.1
- D:\ drive present (repo layout)
- Internet access (only if Node LTS must be installed)
- nvm-windows installed and available as `nvm` (one-time manual install; this repo avoids winget)

.PARAMETER Force
Re-run even if state indicates previous success.

.PARAMETER DevRoot
Root of the dev volume (default: D:\dev)

.PARAMETER Help
Show detailed help.

.EXAMPLE
setup-aryan install-node-toolchain-windows

.EXAMPLE
setup-aryan install-node-toolchain-windows -Force
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

$ActionName = "install-node-toolchain-windows"
$Version    = "1.1.1"

$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$LogFile    = Join-Path $LogsRoot  "$ActionName.log"
$StateFile  = Join-Path $StateRoot "$ActionName.state"

function Show-Help { Get-Help -Detailed $MyInvocation.MyCommand.Path }
if ($Help) { Show-Help; exit 0 }

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Get-ISTStamp {
  try {
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
    $dt = [System.TimeZoneInfo]::ConvertTime((Get-Date), $tz)
    return ("IST {0}" -f $dt.ToString("dd-MM-yyyy HH:mm:ss"))
  } catch {
    return ("IST {0}" -f (Get-Date).ToString("dd-MM-yyyy HH:mm:ss"))
  }
}

function Write-Log {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("Error","Warning","Info","Debug")][string]$Level,
    [Parameter(Mandatory=$true)][string]$Message
  )
  Ensure-Dir -Path $LogsRoot
  Ensure-Dir -Path $StateRoot
  Add-Content -LiteralPath $LogFile -Value "$(Get-ISTStamp) $Level $Message" -Encoding UTF8
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
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Value
  )
  $cur = [Environment]::GetEnvironmentVariable($Name, "User")
  if ($cur -ne $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Write-Log Info "Set USER env var: $Name=$Value"
  } else {
    Write-Log Debug "USER env var already set: $Name=$Value"
  }
}

function Add-ToUserPath {
  param([Parameter(Mandatory=$true)][string]$DirToAdd)

  $current = [Environment]::GetEnvironmentVariable("Path", "User")
  if ([string]::IsNullOrWhiteSpace($current)) { $current = "" }

  $parts = $current.Split(";") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  foreach ($p in $parts) {
    if ($p.TrimEnd("\") -ieq $DirToAdd.TrimEnd("\")) {
      Write-Log Debug "USER PATH already contains: $DirToAdd"
      return
    }
  }

  $new = if ($current.Trim().Length -eq 0) { $DirToAdd } else { "$current;$DirToAdd" }
  [Environment]::SetEnvironmentVariable("Path", $new, "User")
  Write-Log Info "Added to USER PATH: $DirToAdd"
  Write-Log Info "Open a new terminal for PATH changes to take effect."
}

function Ensure-Node {
  if (Get-Command node -ErrorAction SilentlyContinue) {
    $ver = (& node -v) 2>$null
    if ($ver) {
      Write-Log Info "Node already present: $ver"
      return
    }
  }

  $nvm = Get-Command nvm -ErrorAction SilentlyContinue
  if (-not $nvm) {
    throw "Node not found and nvm-windows is not installed. Install nvm-windows (one-time), open a NEW terminal, then re-run this action."
  }

  Write-Log Info "Installing Node.js LTS via nvm-windows..."
  & nvm install lts | Out-Null
  & nvm use lts | Out-Null

  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "nvm reported success but 'node' is still not on PATH in this session. Open a new terminal and re-run."
  }

  Write-Log Info "Node ready: $((& node -v) 2>$null)"
}

function Ensure-CorepackPnpm {
  if (-not (Get-Command corepack -ErrorAction SilentlyContinue)) {
    throw "corepack not found. Ensure Node.js is installed correctly."
  }

  Write-Log Info "Enabling Corepack..."
  & corepack enable | Out-Null

  Write-Log Info "Activating pnpm via Corepack..."
  & corepack prepare pnpm@latest --activate | Out-Null

  if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    throw "pnpm not found after corepack activation."
  }
  Write-Log Info "pnpm ready: $((& pnpm -v) 2>$null)"
}

function Pin-Caches {
  Ensure-Dir -Path $DevRoot

  $pnpmStore = Join-Path $DevRoot "cache\pnpm-store"
  $npmCache  = Join-Path $DevRoot "cache\npm-cache"
  $pnpmHome  = Join-Path $DevRoot "tools\pnpm"

  Ensure-Dir -Path $pnpmStore
  Ensure-Dir -Path $npmCache
  Ensure-Dir -Path $pnpmHome

  Ensure-UserEnvVar -Name "PNPM_HOME" -Value $pnpmHome
  Add-ToUserPath -DirToAdd $pnpmHome

  Write-Log Info "Pinning pnpm store dir -> $pnpmStore"
  & pnpm config set store-dir $pnpmStore --global | Out-Null

  Write-Log Info "Pinning npm cache -> $npmCache"
  & npm config set cache $npmCache --global | Out-Null
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
  if (-not (Test-Path -LiteralPath "D:\")) { throw "D:\ drive not found. Repo policy expects logs/state on D:\." }

  Ensure-Node
  Ensure-CorepackPnpm
  Pin-Caches

  Write-Log Info "Done. Open a new terminal if PATH changes were applied."
} catch {
  $rc = 1
  $status = "failed"
  Write-Log Error $_.Exception.Message
}

$finishedAt = Get-ISO8601
try { Write-State -Status $status -Rc $rc -StartedAt $startedAt -FinishedAt $finishedAt } catch { Write-Log Warning "Failed to write state file: $($_.Exception.Message)" }

exit $rc
