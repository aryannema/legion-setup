#requires -Version 5.1
<#
.SYNOPSIS
Installs Temurin JDK 21 (portable) under D:\dev\tools\jdk\temurin-21\current and pins JAVA_HOME.

.DESCRIPTION
- Downloads the latest Temurin JDK 21 ZIP for Windows x64 from Adoptium.
- Extracts into: D:\dev\tools\jdk\temurin-21\current
- Sets USER env var: JAVA_HOME
- Adds JAVA_HOME\bin to USER PATH
- Writes state file: D:\aryan-setup\state-files\install-java-windows.state

Logging + state (repo standard):
- Logs:  D:\aryan-setup\logs\install-java-windows.log
- State: D:\aryan-setup\state-files\install-java-windows.state (INI-style key=value; UTF-8; NO JSON)

Force semantics:
- Default: if state indicates previous success, skip safely
- -Force: re-run and refresh the installation + state

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

$ActionName = "install-java-windows"
$Version    = "1.1.0"

$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$LogFile    = Join-Path $LogsRoot  "install-java-windows.log"
$StateFile  = Join-Path $StateRoot "install-java-windows.state"

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Get-ISTStamp {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
  $nowIst = [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz)
  return ("IST {0}" -f $nowIst.ToString("dd-MM-yyyy HH:mm:ss"))
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

function Test-Java21Present {
  param([Parameter(Mandatory=$true)][string]$JavaExe)
  if (-not (Test-Path -LiteralPath $JavaExe)) { return $false }
  try {
    $out = & $JavaExe -version 2>&1
    $txt = ($out | Out-String)
    return ($txt -match 'version "21\.')
  } catch {
    return $false
  }
}

function Remove-IfExists {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
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
  if (-not (Test-Path -LiteralPath "D:\")) { throw "D:\ drive not found. Repo policy expects tools on D:\" }

  Ensure-Dir -Path $DevRoot

  $jdkRoot     = Join-Path $DevRoot "tools\jdk\temurin-21"
  $currentRoot = Join-Path $jdkRoot "current"
  $javaExe     = Join-Path $currentRoot "bin\java.exe"

  Ensure-Dir -Path $jdkRoot

  if (-not $Force -and (Test-Java21Present -JavaExe $javaExe)) {
    Write-Log Info "Temurin JDK 21 already present at: $currentRoot"
  } else {
    Write-Log Info "Ensuring Temurin JDK 21 (portable) in: $currentRoot"

    $tmp = Join-Path $env:TEMP "setup-aryan-jdk21"
    Ensure-Dir -Path $tmp

    $zipPath = Join-Path $tmp "temurin-jdk21.zip"

    $uri = "https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"

    Write-Log Info "Downloading Temurin JDK 21 ZIP..."
    Invoke-WebRequest -Uri $uri -OutFile $zipPath -UseBasicParsing

    $extract = Join-Path $tmp "extract"
    Remove-IfExists -Path $extract
    Ensure-Dir -Path $extract

    Write-Log Info "Extracting..."
    try { Unblock-File -LiteralPath $zipPath -ErrorAction SilentlyContinue } catch { }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force

    $candidates = Get-ChildItem -LiteralPath $extract -Directory -ErrorAction Stop
    $picked = $null
    foreach ($d in $candidates) {
      $c = Join-Path $d.FullName "bin\java.exe"
      if (Test-Path -LiteralPath $c) { $picked = $d.FullName; break }
    }
    if ($null -eq $picked) {
      throw "Extracted archive did not contain an expected JDK directory (bin\java.exe not found)."
    }

    $staging = Join-Path $jdkRoot "_staging"
    Remove-IfExists -Path $staging
    Ensure-Dir -Path $staging

    Copy-Item -Path (Join-Path $picked "*") -Destination $staging -Recurse -Force

    Remove-IfExists -Path $currentRoot
    Move-Item -LiteralPath $staging -Destination $currentRoot -Force

    if (-not (Test-Java21Present -JavaExe $javaExe)) {
      throw "JDK install completed but Java 21 validation failed at: $javaExe"
    }

    Write-Log Info "Installed Temurin JDK 21 at: $currentRoot"
  }

  Ensure-UserEnvVar -Name "JAVA_HOME" -Value $currentRoot
  Add-ToUserPath -DirToAdd (Join-Path $currentRoot "bin")

  Write-Log Info "Done. Open a new terminal and run: java -version"
} catch {
  $rc = 1
  $status = "failed"
  Write-Log Error $_.Exception.Message
}

$finishedAt = Get-ISO8601
try { Write-State -Status $status -Rc $rc -StartedAt $startedAt -FinishedAt $finishedAt } catch { Write-Log Warning "Failed to write state file: $($_.Exception.Message)" }

exit $rc
