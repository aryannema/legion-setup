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
  [string]$DevRoot = "D:\dev",

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

# Defensive: if -Force accidentally bound into DevRoot (wrapper/args issue), normalize.
if ($DevRoot -like "-*") {
  $Force = $true
  $DevRoot = "D:\dev"
}

$ActionName = "install-node-toolchain-windows"
$Version    = "1.1.1"

$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$LogFile    = Join-Path $LogsRoot  "$ActionName.log"
$StateFile  = Join-Path $StateRoot "$ActionName.state"

function Show-Help {
@"
$ActionName (version=$Version)

Usage:
  setup-aryan install-node-toolchain-windows-new
  setup-aryan install-node-toolchain-windows-new -Force
"@ | Write-Host
}

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

  # IMPORTANT: $ErrorActionPreference="Stop" makes Write-Error terminating unless we force Continue.
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
  param([Parameter(Mandatory=$false)][switch]$ForceInstall)

  $nvmRoot  = Join-Path $DevRoot "tools\nvm-windows"
  $nvmHome  = Join-Path $nvmRoot "current"
  $nodeLink = Join-Path $DevRoot "tools\nodejs"
  $nvmExe   = Join-Path $nvmHome "nvm.exe"

  Ensure-Dir -Path $nvmRoot
  Ensure-Dir -Path $nvmHome

  # IMPORTANT:
  # Do NOT create $nodeLink as a normal folder.
  # nvm-windows expects NVM_SYMLINK to be a junction/symlink it can create/replace.
  Ensure-Dir -Path (Split-Path -Parent $nodeLink)

  Ensure-UserEnvVar -Name "NVM_HOME" -Value $nvmHome
  Ensure-UserEnvVar -Name "NVM_SYMLINK" -Value $nodeLink
  Add-ToUserPath -DirToAdd $nvmHome
  Add-ToUserPath -DirToAdd $nodeLink

  # Make it usable in this session too
  $env:NVM_HOME    = $nvmHome
  $env:NVM_SYMLINK = $nodeLink
  if (-not ($env:Path -split ';' | Where-Object { $_ -ieq $nvmHome }))  { $env:Path = "$nvmHome;$env:Path" }
  if (-not ($env:Path -split ';' | Where-Object { $_ -ieq $nodeLink })) { $env:Path = "$nodeLink;$env:Path" }

  if ((Test-Path -LiteralPath $nvmExe) -and -not $ForceInstall) { return $nvmExe }

  Write-Log Info "Installing nvm-windows (no-install) into: $nvmHome"

  $tmp = Join-Path $env:TEMP "setup-aryan-nvm"
  Ensure-Dir -Path $tmp
  $zip = Join-Path $tmp "nvm-noinstall.zip"
  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }

  Download-File -Url "https://github.com/coreybutler/nvm-windows/releases/latest/download/nvm-noinstall.zip" -OutFile $zip
  try { Unblock-File -LiteralPath $zip -ErrorAction SilentlyContinue } catch { }

  if ($ForceInstall -and (Test-Path -LiteralPath $nvmHome)) {
    Remove-Item -LiteralPath $nvmHome -Recurse -Force -ErrorAction Stop
    Ensure-Dir -Path $nvmHome
  }

  Expand-Archive -LiteralPath $zip -DestinationPath $nvmHome -Force

  if (-not (Test-Path -LiteralPath $nvmExe)) {
    throw "nvm.exe not found after extract at: $nvmExe"
  }

  $settings = Join-Path $nvmHome "settings.txt"
  $content = @(
    "root: $nvmHome",
    "path: $nodeLink",
    "arch: 64",
    "proxy: none"
  )
  Set-Content -LiteralPath $settings -Value $content -Encoding ASCII

  try {
    $v = (& $nvmExe version) 2>$null
    if ($v) { Write-Log Info "nvm ready: $v" } else { Write-Log Warning "nvm installed but version did not print in this session." }
  } catch {
    Write-Log Warning "nvm installed but version check failed in this session: $($_.Exception.Message)"
  }

  return $nvmExe
}

function Pin-Caches {
  Ensure-Dir -Path $DevRoot

  $pnpmHome  = Join-Path $DevRoot "tools\pnpm"
  $pnpmStore = Join-Path $DevRoot "cache\pnpm-store"
  $npmCache  = Join-Path $DevRoot "cache\npm-cache"

  Ensure-Dir -Path $pnpmHome
  Ensure-Dir -Path $pnpmStore
  Ensure-Dir -Path $npmCache

  Ensure-UserEnvVar -Name "PNPM_HOME" -Value $pnpmHome
  Add-ToUserPath -DirToAdd $pnpmHome

  Ensure-UserEnvVar -Name "NPM_CONFIG_CACHE" -Value $npmCache
  Ensure-UserEnvVar -Name "PNPM_STORE_PATH" -Value $pnpmStore

  # current session too
  $env:PNPM_HOME = $pnpmHome
  if (-not ($env:Path -split ';' | Where-Object { $_ -ieq $pnpmHome })) { $env:Path = "$pnpmHome;$env:Path" }
}

function Ensure-Node {
  if (Get-Command node -ErrorAction SilentlyContinue) {
    $ver = (& node -v) 2>$null
    if ($ver) {
      Write-Log Info "Node already present: $ver"
      return
    }
  }

  $nvmExe = Ensure-NvmWindows

  $nodeLink = $env:NVM_SYMLINK
  if ([string]::IsNullOrWhiteSpace($nodeLink)) { $nodeLink = (Join-Path $DevRoot "tools\nodejs") }

  # If nodeLink exists as a normal directory, nvm cannot create the junction. Remove only if empty.
  if (Test-Path -LiteralPath $nodeLink) {
    $item = Get-Item -LiteralPath $nodeLink -ErrorAction SilentlyContinue
    $isReparse = $false
    if ($item -ne $null) {
      try { $isReparse = (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) } catch { $isReparse = $false }
    }
    if (-not $isReparse) {
      $children = @(Get-ChildItem -LiteralPath $nodeLink -Force -ErrorAction SilentlyContinue)
      if ($children.Count -eq 0) {
        Write-Log Warning "NVM_SYMLINK exists as a normal empty folder. Removing so nvm-windows can create a junction: $nodeLink"
        Remove-Item -LiteralPath $nodeLink -Force -Recurse -ErrorAction Stop
      } else {
        Write-Log Warning "NVM_SYMLINK exists as a normal folder with contents. nvm-windows may be blocked from creating a junction at: $nodeLink"
      }
    }
  }

  Write-Log Info "Installing Node.js LTS via nvm-windows..."
  & $nvmExe install lts | Out-Null
  & $nvmExe use lts | Out-Null

  # Ensure current session can resolve node if link exists
  if (-not ($env:Path -split ';' | Where-Object { $_ -ieq $nodeLink })) { $env:Path = "$nodeLink;$env:Path" }

  $nodeExe = Join-Path $nodeLink "node.exe"
  if (Test-Path -LiteralPath $nodeExe) {
    if (Get-Command node -ErrorAction SilentlyContinue) {
      Write-Log Info "Node ready: $((& node -v) 2>$null)"
    } else {
      $ver = (& $nodeExe -v) 2>$null
      Write-Log Warning "node.exe exists but PowerShell could not resolve 'node' in this session. Continuing with direct path."
      Write-Log Info "Node ready: $ver"
    }
    return
  }

  # Fallback: junction blocked. Use the installed vX.Y.Z directory directly.
  $nvmHome = $env:NVM_HOME
  if ([string]::IsNullOrWhiteSpace($nvmHome)) { $nvmHome = (Join-Path $DevRoot "tools\nvm-windows\current") }

  $nvmCurrent = ""
  try { $nvmCurrent = (& $nvmExe current) 2>$null } catch { $nvmCurrent = "" }
  $nvmCurrent = ($nvmCurrent | Out-String).Trim()

  $directDir = $null
  if ($nvmCurrent -match '(\d+\.\d+\.\d+)') {
    $ver = $matches[1]
    $candidate = Join-Path $nvmHome ("v{0}" -f $ver)
    if (Test-Path -LiteralPath (Join-Path $candidate "node.exe")) { $directDir = $candidate }
  }

  if (-not $directDir) {
    # Best-effort pick: newest v* directory with node.exe
    $dirs = Get-ChildItem -LiteralPath $nvmHome -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "v*" }
    foreach ($d in ($dirs | Sort-Object Name -Descending)) {
      if (Test-Path -LiteralPath (Join-Path $d.FullName "node.exe")) { $directDir = $d.FullName; break }
    }
  }

  if ($directDir) {
    Write-Log Warning "nvm configured Node but junction at NVM_SYMLINK was not created. Using direct node directory on PATH: $directDir"
    Ensure-UserEnvVar -Name "SETUP_ARYAN_NODE_DIR" -Value $directDir
    Add-ToUserPath -DirToAdd $directDir
    if (-not ($env:Path -split ';' | Where-Object { $_ -ieq $directDir })) { $env:Path = "$directDir;$env:Path" }

    $ver2 = (& (Join-Path $directDir "node.exe") -v) 2>$null
    Write-Log Info "Node ready (direct): $ver2"
    Write-Log Warning "To make nvm-windows fully functional, enable Windows Developer Mode (or ensure junction creation is allowed) so NVM_SYMLINK can be created."
    return
  }

  throw "nvm reported success but '$nodeExe' does not exist (nvm current=$nvmCurrent). This usually means Windows blocked creating the node symlink/junction. Run an elevated terminal OR enable Windows Developer Mode, then run: nvm use lts and re-run this action."
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
