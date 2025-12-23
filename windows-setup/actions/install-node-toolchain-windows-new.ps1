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

Windows parity notes:
- nvm-windows installed and available as `nvm` (one-time manual install; this repo avoids winget)
- Open a NEW terminal after initial nvm install so PATH/env vars propagate.

Force semantics:
- Default: if prior state is success, skip safely
- -Force: re-run and refresh the installation + state

.PREREQUISITES
- Windows 11
- Windows PowerShell 5.1
- Internet access (to download Temurin JDK)
- D:\ drive present (repo layout)

.PARAMETER Force
Re-run even if state indicates previous success.

.PARAMETER DevRoot
Root of the dev volume (default: D:\dev)
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [switch]$Force,

  [Parameter(Mandatory=$false)]
  [string]$DevRoot = "D:\dev"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ActionName = "install-node-toolchain-windows"
$Version    = "1.1.1"

$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$LogFile    = Join-Path $LogsRoot  "install-node-toolchain-windows.log"
$StateFile  = Join-Path $StateRoot "install-node-toolchain-windows.state"

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Get-ISTStamp {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
  $nowIst = [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz)
  return ("IST {0}" -f $nowIst.ToString("dd-MM-yyyy HH:mm:ss"))
  return ("IST {0}" -f (Get-Date).ToString("dd-MM-yyyy HH:mm:ss"))
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
    "Error"   { Write-Error   $Message -ErrorAction Continue }
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
    if ($k) { $map[$k] = $v }
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
  Ensure-Dir -Path $StateRoot
  $content = @(
    "status=$Status",
    "rc=$Rc",
    "action=$ActionName",
    "version=$Version",
    "started_at=$StartedAt",
    "finished_at=$FinishedAt",
    "force=$Force",
    "dev_root=$DevRoot"
  )
  Set-Content -LiteralPath $StateFile -Value $content -Encoding UTF8
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

function Set-Tls12 {
  # PS 5.1 needs TLS 1.2 for many modern HTTPS endpoints
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Download-File {
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$OutFile
  )

  Set-Tls12
  try {
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
    return
  } catch {
    Write-Log Warning "Invoke-WebRequest failed: $($_.Exception.Message)"
  }

  $curl = Join-Path $env:SystemRoot "System32\curl.exe"
  if (Test-Path -LiteralPath $curl) {
    $p = Start-Process -FilePath $curl -ArgumentList @("-L", $Url, "-o", $OutFile) -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "curl.exe failed with exit code: $($p.ExitCode)" }
    return
  }

  throw "Download failed and curl.exe not available."
}

function Ensure-NvmWindows {
  $nvmRoot = Join-Path $DevRoot "tools\nvm-windows"
  $nvmHome = Join-Path $nvmRoot "current"
  $nodeLink = Join-Path $DevRoot "tools\nodejs"
  $nvmExe = Join-Path $nvmHome "nvm.exe"

  Ensure-Dir -Path $nvmRoot
  Ensure-Dir -Path $nodeLink

  # Always ensure env vars + PATH entries (idempotent)
  Ensure-UserEnvVar -Name "NVM_HOME" -Value $nvmHome
  Ensure-UserEnvVar -Name "NVM_SYMLINK" -Value $nodeLink
  Add-ToUserPath -DirToAdd $nvmHome
  Add-ToUserPath -DirToAdd $nodeLink

  # Make available in this session too (no restart requirement for the action itself)
  if (-not ($env:Path -split ';' | Where-Object { $_ -ieq $nvmHome })) { $env:Path = "$nvmHome;$env:Path" }
  if (-not ($env:Path -split ';' | Where-Object { $_ -ieq $nodeLink })) { $env:Path = "$nodeLink;$env:Path" }
  $env:NVM_HOME = $nvmHome
  $env:NVM_SYMLINK = $nodeLink

  if (Get-Command nvm -ErrorAction SilentlyContinue) {
    return
  }

  if (Test-Path -LiteralPath $nvmExe) {
    return
  }

  Write-Log Info "Installing nvm-windows (no-install) into: $nvmHome"

  $tmp = Join-Path $env:TEMP "setup-aryan-nvm"
  Ensure-Dir -Path $tmp
  $zip = Join-Path $tmp "nvm-noinstall.zip"

  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }

  # Official release asset (no-install; avoids UAC prompts)
  Download-File -Url "https://github.com/coreybutler/nvm-windows/releases/latest/download/nvm-noinstall.zip" -OutFile $zip

  try { Unblock-File -LiteralPath $zip -ErrorAction SilentlyContinue } catch { }

  # Recreate install dir
  if (Test-Path -LiteralPath $nvmHome) {
    if ($Force) {
      Remove-Item -LiteralPath $nvmHome -Recurse -Force -ErrorAction Stop
    }
  }
  Ensure-Dir -Path $nvmHome

  Expand-Archive -LiteralPath $zip -DestinationPath $nvmHome -Force

  if (-not (Test-Path -LiteralPath $nvmExe)) {
    throw "nvm.exe not found after extract at: $nvmExe"
  }

  # Manual install requires settings.txt
  $settings = Join-Path $nvmHome "settings.txt"
  $arch = "64"
  $content = @(
    "root: $nvmHome",
    "path: $nodeLink",
    "arch: $arch",
    "proxy: none"
  )
  Set-Content -LiteralPath $settings -Value $content -Encoding ASCII

  # Validate
  $ver = (& $nvmExe version) 2>$null
  if (-not $ver) {
    Write-Log Warning "nvm installed but version command did not return output in this session."
  } else {
    Write-Log Info "nvm ready: $ver"
  }
}

function Ensure-Node {
  if (Get-Command node -ErrorAction SilentlyContinue) {
    $ver = (& node -v) 2>$null
    if ($ver) {
      Write-Log Info "Node already present: $ver"
      return
    }
  }

  Ensure-NvmWindows

  Write-Log Info "Installing Node.js LTS via nvm-windows..."
  try { & nvm install lts | Out-Null } catch { throw "nvm install lts failed: $($_.Exception.Message)" }

  try { & nvm use lts | Out-Null } catch {
    throw "nvm use lts failed (this often needs symlink permissions). Try running an elevated terminal or enable Windows Developer Mode for non-admin symlinks. Details: $($_.Exception.Message)"
  }

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

  Ensure-UserEnvVar -Name "NPM_CONFIG_CACHE" -Value $npmCache
  Ensure-UserEnvVar -Name "PNPM_STORE_PATH" -Value $pnpmStore

  # Make these effective in current session too
  $env:PNPM_HOME = $pnpmHome
  $env:NPM_CONFIG_CACHE = $npmCache
  $env:PNPM_STORE_PATH = $pnpmStore
}

# ---------------------------
# Main
# ---------------------------
$startedAt = Get-ISO8601
$rc = 0
$status = "success"

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

try {
  if (-not (Test-Path -LiteralPath "D:\")) { throw "D:\ drive not found. Repo policy expects tools on D:\." }

  Pin-Caches
  Ensure-Node
  Ensure-CorepackPnpm

} catch {
  $rc = 1
  $status = "failed"
  Write-Log Error $_.Exception.Message
}

$finishedAt = Get-ISO8601
try { Write-State -Status $status -Rc $rc -StartedAt $startedAt -FinishedAt $finishedAt } catch { Write-Log Warning "Failed to write state file: $($_.Exception.Message)" }

exit $rc
