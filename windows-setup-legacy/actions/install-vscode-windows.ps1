#requires -Version 5.1
<#
.SYNOPSIS
Installs/ensures VS Code (User Setup) on Windows (idempotent, no winget required).

.DESCRIPTION
- Checks for VS Code under:
  - %LocalAppData%\Programs\Microsoft VS Code\Code.exe
  - or `code` on PATH
- If missing (or -Force), downloads the latest stable "User Setup" installer and installs silently.
- Best-effort: enables "Add to PATH" installer task so `code` becomes available in new terminals.

Logging + state (repo standard):
- Logs:  D:\aryan-setup\logs\install-vscode-windows.log
- State: D:\aryan-setup\state-files\install-vscode-windows.state   (INI-style key=value, UTF-8; NO JSON)

Force semantics:
- Default: if prior state is success, skip safely
- -Force: re-run installer

.PREREQUISITES
- Windows 11
- Windows PowerShell 5.1
- Internet access (to download VS Code)
- D:\ drive present (repo layout)

.PARAMETER Force
Re-run even if state indicates previous success.

.PARAMETER Help
Show detailed help.

.EXAMPLE
setup-aryan install-vscode-windows

.EXAMPLE
setup-aryan install-vscode-windows -Force
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

$ActionName = "install-vscode-windows"
$Version    = "1.1.0"

$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$LogFile    = Join-Path $LogsRoot  "$ActionName.log"
$StateFile  = Join-Path $StateRoot "$ActionName.state"

function Show-Help { Get-Help -Detailed $MyInvocation.MyCommand.Path }
if ($Help) { Show-Help; exit 0 }

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
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

function Get-CodeExePath {
  $p = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\Code.exe"
  if (Test-Path -LiteralPath $p) { return $p }
  return $null
}

function Is-VSCodePresent {
  if (Get-Command code -ErrorAction SilentlyContinue) { return $true }
  if (Get-CodeExePath) { return $true }
  return $false
}

# ---------------------------
# Main
# ---------------------------
$startedAt = Get-ISO8601

Ensure-Dir -Path $LogsRoot
Ensure-Dir -Path $StateRoot

Write-Log Info "Starting: $ActionName (version=$Version, Force=$Force)"

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

  if (-not $Force -and (Is-VSCodePresent)) {
    Write-Log Info "VS Code already present. (code on PATH or Code.exe found)"
  } else {
    $tmp = Join-Path $env:TEMP "setup-aryan-vscode"
    Ensure-Dir -Path $tmp
    $installer = Join-Path $tmp "VSCodeUserSetup-x64.exe"

    $uri = "https://update.code.visualstudio.com/latest/win32-x64-user/stable"

    Write-Log Info "Downloading VS Code User Setup (stable)..."
    Invoke-WebRequest -Uri $uri -OutFile $installer -UseBasicParsing

    if (-not (Test-Path -LiteralPath $installer)) {
      throw "Download failed: $installer"
    }

    Write-Log Info "Installing VS Code (silent user setup)..."
    $args = "/VERYSILENT /NORESTART /MERGETASKS=addtopath,!runcode"
    $p = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru

    if ($p.ExitCode -ne 0) {
      throw "VS Code installer returned non-zero exit code: $($p.ExitCode)"
    }

    if (-not (Is-VSCodePresent)) {
      Write-Log Warning "VS Code install completed, but 'code' may not be available in this terminal yet."
      Write-Log Warning "Open a new terminal and try: code --version"
    } else {
      Write-Log Info "VS Code installed/available. Open a new terminal if 'code' isn't recognized yet."
    }
  }
} catch {
  $rc = 1
  $status = "failed"
  Write-Log Error $_.Exception.Message
}

$finishedAt = Get-ISO8601
try { Write-State -Status $status -Rc $rc -StartedAt $startedAt -FinishedAt $finishedAt } catch { Write-Log Warning "Failed to write state file: $($_.Exception.Message)" }

exit $rc
