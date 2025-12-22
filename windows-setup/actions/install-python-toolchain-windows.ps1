<#
Prerequisites
- Windows 11
- PowerShell 5.1+
- Internet access

Usage
  powershell -File .\install-python-toolchain-windows.ps1 -Help
  powershell -File .\install-python-toolchain-windows.ps1

What it does (idempotent)
- Installs Miniconda to D:\dev\tools\miniconda3 (user-managed location)
- Configures Conda to store:
  - pkgs: D:\dev\cache\conda\pkgs
  - envs: D:\dev\envs\conda\envs
- Disables base auto-activation
- Installs uv and pins UV_CACHE_DIR to D:\dev\cache\uv
- Logs:  D:\aryan-setup\logs\install-python-toolchain-windows.log
- State: D:\aryan-setup\state\install-python-toolchain-windows.state.json
#>

[CmdletBinding()]
param(
  [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ISTTimestamp {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
  $nowIst = [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz)
  return "IST " + $nowIst.ToString("dd-MM-yyyy HH:mm:ss")
}

function Write-Log {
  param([ValidateSet("Error","Warning","Info","Debug")] [string]$Level, [string]$Message)
  $line = "$(Get-ISTTimestamp) $Level $Message"
  Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
  Write-Host $line
}

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Set-UserEnvVar([string]$Name, [string]$Value) {
  [Environment]::SetEnvironmentVariable($Name, $Value, "User")
}

function Save-State([hashtable]$State) {
  $json = $State | ConvertTo-Json -Depth 6
  Set-Content -Path $script:StateFile -Value $json -Encoding UTF8
}

function Show-Help {
@"
install-python-toolchain-windows.ps1

Installs Miniconda + uv in an idempotent, disk-safe layout.

Outputs:
  Logs : D:\aryan-setup\logs\install-python-toolchain-windows.log
  State: D:\aryan-setup\state\install-python-toolchain-windows.state.json
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }

# Paths
$LogRoot   = "D:\aryan-setup\logs"
$StateRoot = "D:\aryan-setup\state"
Ensure-Dir $LogRoot
Ensure-Dir $StateRoot

$script:LogFile   = Join-Path $LogRoot "install-python-toolchain-windows.log"
$script:StateFile = Join-Path $StateRoot "install-python-toolchain-windows.state.json"

Write-Log -Level Info -Message "=== START install-python-toolchain-windows ==="

# Layout
$DevRoot     = "D:\dev"
$ToolsRoot   = Join-Path $DevRoot "tools"
$CacheRoot   = Join-Path $DevRoot "cache"
$EnvsRoot    = Join-Path $DevRoot "envs"

$CondaRoot   = Join-Path $ToolsRoot "miniconda3"
$CondaPkgs   = Join-Path $CacheRoot "conda\pkgs"
$CondaEnvs   = Join-Path $EnvsRoot  "conda\envs"

$UvCache     = Join-Path $CacheRoot "uv"

Ensure-Dir $ToolsRoot
Ensure-Dir $CacheRoot
Ensure-Dir $EnvsRoot
Ensure-Dir $CondaPkgs
Ensure-Dir $CondaEnvs
Ensure-Dir $UvCache

# Install Miniconda if missing
$condaExe = Join-Path $CondaRoot "Scripts\conda.exe"
if (-not (Test-Path -LiteralPath $condaExe)) {
  Write-Log -Level Info -Message "Miniconda not detected. Installing to $CondaRoot ..."

  $tmp = Join-Path $env:TEMP "miniconda-installer.exe"
  $url = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"

  Write-Log -Level Info -Message "Downloading Miniconda -> $tmp"
  Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing

  # Silent install (/S) + JustMe. Use /D= for target dir.
  # Note: /D must be last and without quotes.
  $args = @(
    "/InstallationType=JustMe",
    "/AddToPath=0",
    "/RegisterPython=0",
    "/S",
    "/D=$CondaRoot"
  )

  Write-Log -Level Info -Message "Running Miniconda installer silently..."
  $p = Start-Process -FilePath $tmp -ArgumentList $args -Wait -PassThru
  Write-Log -Level Info -Message "Installer exit code: $($p.ExitCode)"

  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $condaExe)) {
  Write-Log -Level Error -Message "Conda still not found after install attempt: $condaExe"
  Save-State @{ status="error"; step="install_miniconda"; at=(Get-ISTTimestamp) }
  exit 1
}

Write-Log -Level Info -Message "Conda detected: $condaExe"

# Configure .condarc deterministically (idempotent overwrite)
$condarcPath = Join-Path $env:USERPROFILE ".condarc"
$condarc = @"
# Managed by install-python-toolchain-windows.ps1 (idempotent)
auto_activate_base: false

pkgs_dirs:
  - $CondaPkgs

envs_dirs:
  - $CondaEnvs
"@
Set-Content -Path $condarcPath -Value $condarc -Encoding UTF8
Write-Log -Level Info -Message "Wrote $condarcPath (pkgs/envs redirected to D:\dev)"

# Make sure conda sees config + initialize minimal (do not force profile edits here)
# We only validate conda can run.
try {
  $v = & $condaExe --version 2>&1
  Write-Log -Level Info -Message "Conda version: $v"
} catch {
  Write-Log -Level Error -Message "Failed to run conda: $($_.Exception.Message)"
  Save-State @{ status="error"; step="conda_run"; at=(Get-ISTTimestamp) }
  exit 1
}

# Install uv (official installer)
# Docs commonly use: powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
# We run it inline and then locate uv.exe.
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uvCmd) {
  Write-Log -Level Info -Message "uv not detected. Installing uv (user scope) using official installer..."
  try {
    powershell -ExecutionPolicy ByPass -NoProfile -Command "irm https://astral.sh/uv/install.ps1 | iex" | Out-Null
  } catch {
    Write-Log -Level Error -Message "uv install failed: $($_.Exception.Message)"
    Save-State @{ status="error"; step="install_uv"; at=(Get-ISTTimestamp) }
    exit 1
  }
}

# Re-detect uv
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uvCmd) {
  # Common fallback paths (best-effort)
  $fallbacks = @(
    Join-Path $env:USERPROFILE ".local\bin\uv.exe",
    Join-Path $env:LOCALAPPDATA "uv\bin\uv.exe"
  )
  $uvExe = $fallbacks | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if ($uvExe) {
    Write-Log -Level Warning -Message "uv not in PATH yet; found at $uvExe"
  } else {
    Write-Log -Level Error -Message "uv not found after install."
    Save-State @{ status="error"; step="detect_uv"; at=(Get-ISTTimestamp) }
    exit 1
  }
} else {
  $uvExe = $uvCmd.Source
  Write-Log -Level Info -Message "uv detected: $uvExe"
}

# Pin UV_CACHE_DIR (User)
Set-UserEnvVar -Name "UV_CACHE_DIR" -Value $UvCache
Write-Log -Level Info -Message "Set User env: UV_CACHE_DIR=$UvCache"

# Quick sanity check
try {
  $uvV = & $uvExe --version 2>&1
  Write-Log -Level Info -Message "uv version: $uvV"
} catch {
  Write-Log -Level Warning -Message "uv version check failed in current session (may need new shell)."
}

Save-State @{
  status="ok"
  conda_root=$CondaRoot
  condarc=$condarcPath
  conda_pkgs=$CondaPkgs
  conda_envs=$CondaEnvs
  uv_exe=$uvExe
  uv_cache=$UvCache
  at=(Get-ISTTimestamp)
}

Write-Log -Level Info -Message "=== DONE install-python-toolchain-windows ==="
exit 0
