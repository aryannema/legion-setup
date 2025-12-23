#requires -Version 5.1
<#
Prerequisites
- Windows 11
- Windows PowerShell 5.1
- Internet access
- (Recommended) winget installed and working

Usage
  setup-aryan install-node-toolchain-windows -Help
  setup-aryan install-node-toolchain-windows
  setup-aryan install-node-toolchain-windows -Force

What it does (idempotent)
- Ensures Node.js LTS is installed (default via winget)
- Enables Corepack and activates pnpm
- Pins caches/stores to D:\dev\cache\
  - pnpm store: D:\dev\cache\pnpm-store
  - npm cache : D:\dev\cache\npm-cache
- Sets PNPM_HOME to D:\dev\tools\pnpm and adds it to USER PATH (for global pnpm bins)
- Writes state-file (NO JSON):
  D:\aryan-setup\state-files\install-node-toolchain-windows.state

Linux parity notes
- Linux uses nvm + corepack/pnpm; on Windows we keep a simpler default (winget Node LTS)
  because nvm-windows requires symlink/junction setup and can be policy-sensitive.
  If you want nvm-windows later, we can add an opt-in flag (-UseNvmWindows).

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
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
  $nowIst = [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz)
  return "IST " + $nowIst.ToString("dd-MM-yyyy HH:mm:ss")
}

function Write-Log {
  param([ValidateSet("Error","Warning","Info","Debug")] [string]$Level, [string]$Message)
  Ensure-Dir -Path $LogsRoot
  Add-Content -LiteralPath $LogFile -Value "$(Get-ISTStamp) $Level $Message" -Encoding UTF8
  switch ($Level) {
    "Error"   { Write-Error   $Message }
    "Warning" { Write-Warning $Message }
    "Info"    { Write-Host    $Message }
    "Debug"   { Write-Host    $Message }
  }
}

function Get-ISO8601 { (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK") }
function Get-Version { return "1.1.0" }

function Read-State {
  if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
  $map = @{}
  foreach ($ln in (Get-Content -LiteralPath $StateFile -ErrorAction Stop)) {
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
  param([string]$Status, [int]$Rc, [string]$StartedAt, [string]$FinishedAt)
  Ensure-Dir -Path $StateRoot
  $content = @(
    "action=$ActionName",
    "status=$Status",
    "rc=$Rc",
    "started_at=$StartedAt",
    "finished_at=$FinishedAt",
    "user=$([Environment]::UserName)",
    "host=$env:COMPUTERNAME",
    "log_path=$LogFile",
    "version=$(Get-Version)"
  )
  $tmp = "$StateFile.tmp"
  Set-Content -LiteralPath $tmp -Value $content -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}

function Add-ToUserPath {
  param([Parameter(Mandatory=$true)][string]$DirToAdd)

  $current = [Environment]::GetEnvironmentVariable("Path","User")
  if ([string]::IsNullOrWhiteSpace($current)) { $current = "" }

  $parts = $current.Split(";") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  foreach ($p in $parts) {
    if ($p.TrimEnd("\") -ieq $DirToAdd.TrimEnd("\")) { return }
  }

  $new = if ($current.Trim().EndsWith(";") -or $current.Trim().Length -eq 0) { "$current$DirToAdd" } else { "$current;$DirToAdd" }
  [Environment]::SetEnvironmentVariable("Path","$new","User")
}

function Ensure-UserEnvVar {
  param([Parameter(Mandatory=$true)][string]$Name, [Parameter(Mandatory=$true)][string]$Value)
  $cur = [Environment]::GetEnvironmentVariable($Name, "User")
  if ($cur -ne $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Write-Log Info "Set USER env var: $Name=$Value"
  } else {
    Write-Log Debug "USER env var already set: $Name"
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

  $wg = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $wg) {
    throw "winget not found and Node not installed. Install winget or install Node.js LTS manually."
  }

  Write-Log Info "Installing Node.js LTS via winget..."
  # Scope user first; if it fails, the user can rerun elevated or install manually.
  & winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --scope user | Out-Null

  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node install attempted but 'node' not found on PATH. Open a new terminal and re-run, or install Node manually."
  }
  Write-Log Info "Node installed: $((& node -v) 2>$null)"
}

function Ensure-CorepackPnpm {
  if (-not (Get-Command corepack -ErrorAction SilentlyContinue)) {
    throw "corepack not found. Ensure Node.js is installed correctly."
  }

  Write-Log Info "Enabling Corepack..."
  & corepack enable | Out-Null

  # Activate latest pnpm via corepack (idempotent)
  Write-Log Info "Activating pnpm via Corepack..."
  & corepack prepare pnpm@latest --activate | Out-Null

  if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    throw "pnpm not found after corepack activation."
  }
  Write-Log Info "pnpm ready: $((& pnpm -v) 2>$null)"
}

function Pin-Caches {
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
if (-not (Test-Path -LiteralPath "D:\")) {
  Write-Error "D:\ drive not found. Repo policy expects dev/log/state on D:\."
  exit 1
}

Ensure-Dir -Path $LogsRoot
Ensure-Dir -Path $StateRoot

$startedAt = Get-ISO8601

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
  Ensure-Dir -Path $DevRoot
  Ensure-Dir -Path (Join-Path $DevRoot "cache")
  Ensure-Dir -Path (Join-Path $DevRoot "tools")

  Ensure-Node
  Ensure-CorepackPnpm
  Pin-Caches

  Write-Log Info "Node toolchain ready."
  Write-Log Info "Open a NEW terminal for PATH changes to apply."
} catch {
  $rc = 1
  $status = "failed"
  Write-Log Error $_.Exception.Message
}

Write-State -Status $status -Rc $rc -StartedAt $startedAt -FinishedAt (Get-ISO8601)

exit $rc
