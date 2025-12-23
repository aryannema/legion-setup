#requires -Version 5.1
<#
.SYNOPSIS
setup-aryan command dispatcher (Windows PowerShell 5.1)

.DESCRIPTION
Stable, idempotent CLI wrapper that runs repo-defined action scripts staged under:
  C:\Tools\aryan-setup\actions\

Invariants (repo policy):
- Logs:  D:\aryan-setup\logs\
- State: D:\aryan-setup\state-files\   (NO JSON; key=value .state files)
- All actions should support -Force (wrapper forwards it unless already present)

.USAGE
  setup-aryan -Help
  setup-aryan list
  setup-aryan run <action-name> [action args...]
  setup-aryan <action-name> [action args...]

.EXAMPLES
  setup-aryan list
  setup-aryan run prepare-windows-dev-dirs -Force
  setup-aryan install-python-toolchain-windows
  setup-aryan new-python-project-windows -Name demo -Ai -TensorFlow
  setup-aryan validate-windows-dev
#>

[CmdletBinding(PositionalBinding=$true)]
param(
  [Parameter(Position=0, Mandatory=$false)]
  [string]$Command = "help",

  [Parameter(Position=1, Mandatory=$false)]
  [string]$Action = "",

  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Rest = @(),

  [Parameter(Mandatory=$false)]
  [switch]$Force,

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$LogsRoot  = "D:\aryan-setup\logs"
$StateRoot = "D:\aryan-setup\state-files"

$ThisScript = $MyInvocation.MyCommand.Path
$BinDir     = Split-Path -Parent $ThisScript
$RootDir    = Split-Path -Parent $BinDir
$ActionsDir = Join-Path $RootDir "actions"

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-ISTStamp {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
  $nowIst = [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz)
  return "IST " + $nowIst.ToString("dd-MM-yyyy HH:mm:ss")
}

function Write-LogLine {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("Error","Warning","Info","Debug")][string]$Level,
    [Parameter(Mandatory=$true)][string]$Message,
    [Parameter(Mandatory=$true)][string]$LogPath
  )
  $line = "{0} {1} {2}" -f (Get-ISTStamp), $Level, $Message
  Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Write-Log {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("Error","Warning","Info","Debug")][string]$Level,
    [Parameter(Mandatory=$true)][string]$Message
  )
  $wrapperLog = Join-Path $LogsRoot "setup-aryan.log"
  try { Ensure-Dir -Path $LogsRoot } catch {}
  try { Write-LogLine -Level $Level -Message $Message -LogPath $wrapperLog } catch {}

  switch ($Level) {
    "Error"   { Write-Error   $Message -ErrorAction Continue }
    "Warning" { Write-Warning $Message }
    "Info"    { Write-Host    $Message }
    "Debug"   { Write-Host    $Message }
  }
}

function Assert-Environment {
  Ensure-Dir -Path $LogsRoot
  Ensure-Dir -Path $StateRoot

  if (-not (Test-Path -LiteralPath $ActionsDir)) {
    throw "Actions directory not found: $ActionsDir. Re-run: .\windows-setup\stage-aryan-setup.ps1"
  }
}

function Show-Usage {
@"
setup-aryan (Windows PowerShell 5.1)

Usage:
  setup-aryan -Help
  setup-aryan list
  setup-aryan version
  setup-aryan run <action-name> [action args...]
  setup-aryan <action-name> [action args...]

Repo policy:
  - Logs : $LogsRoot
  - State: $StateRoot   (actions write <action>.state as key=value; NO JSON)
  - -Force is forwarded to actions (unless already present)

Examples:
  setup-aryan list
  setup-aryan run prepare-windows-dev-dirs -Force
  setup-aryan install-node-toolchain-windows
  setup-aryan new-python-project-windows -Name demo -Ai -TensorFlow
"@ | Write-Host
}

if ($Help -or $Command -eq "help" -or $Command -eq "-h" -or $Command -eq "--help") {
  Show-Usage
  exit 0
}

function Get-ActionNames {
  Assert-Environment
  $files = Get-ChildItem -LiteralPath $ActionsDir -Filter "*.ps1" -File -ErrorAction Stop
  $names = @()
  foreach ($f in $files) {
    $n = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    if (-not [string]::IsNullOrWhiteSpace($n)) { $names += $n }
  }
  return ($names | Sort-Object -Unique)
}

function Resolve-ActionPath {
  param([Parameter(Mandatory=$true)][string]$ActionName)
  Assert-Environment
  $p = Join-Path $ActionsDir ($ActionName + ".ps1")
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  return $p
}

function Cmd-List {
  $names = Get-ActionNames
  if ($names.Count -eq 0) {
    Write-Host "No actions found in: $ActionsDir"
    return
  }
  Write-Host "Actions (from $ActionsDir):"
  foreach ($n in $names) { Write-Host ("  - {0}" -f $n) }
}

function Cmd-Version {
  $versionFile = Join-Path $RootDir "VERSION"
  if (Test-Path -LiteralPath $versionFile) {
    $v = (Get-Content -LiteralPath $versionFile -ErrorAction Stop | Select-Object -First 1).Trim()
    if ($v) { Write-Host $v; return }
  }
  $ts = (Get-Item -LiteralPath $ThisScript).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
  Write-Host ("unknown (setup-aryan.ps1 last-write: {0})" -f $ts)
}

function Invoke-Action {
  param(
    [Parameter(Mandatory=$true)][string]$ActionName,
    [Parameter(Mandatory=$false)][string[]]$ActionArgs = @()
  )

  $path = Resolve-ActionPath -ActionName $ActionName
  if ($null -eq $path) {
    Show-Usage
    throw "Unknown action: $ActionName"
  }

  $finalArgs = @()
  if ($Force) {
    $hasForce = $false
    foreach ($a in $ActionArgs) {
      if ($a -ieq "-Force") { $hasForce = $true; break }
    }
    if (-not $hasForce) { $finalArgs += "-Force" }
  }
  $finalArgs += $ActionArgs

  Write-Log -Level Info -Message ("Running action: {0} {1}" -f $ActionName, ($finalArgs -join " "))
  Write-Log -Level Debug -Message ("Action path: {0}" -f $path)

  & $path @finalArgs
  $rc = $LASTEXITCODE

  if ($rc -ne 0) {
    Write-Log -Level Error -Message ("Action failed: {0} (rc={1})" -f $ActionName, $rc)
    exit $rc
  }

  Write-Log -Level Info -Message ("Action success: {0}" -f $ActionName)
  exit 0
}

try {
  switch ($Command.ToLowerInvariant()) {
    "list"    { Cmd-List; exit 0 }
    "version" { Cmd-Version; exit 0 }
    "run" {
      if ([string]::IsNullOrWhiteSpace($Action)) {
        Show-Usage
        throw "Missing action name. Usage: setup-aryan run <action-name> [args...]"
      }
      Invoke-Action -ActionName $Action -ActionArgs $Rest
    }
    default {
      $maybeAction = $Command
      $actionArgs = @()

      if (-not [string]::IsNullOrWhiteSpace($Action)) { $actionArgs += $Action }
      if ($Rest -and $Rest.Count -gt 0) { $actionArgs += $Rest }

      $path = Resolve-ActionPath -ActionName $maybeAction
      if ($null -ne $path) {
        Invoke-Action -ActionName $maybeAction -ActionArgs $actionArgs
      } else {
        Show-Usage
        throw "Unknown command or action: $Command"
      }
    }
  }
} catch {
  Write-Log -Level Error -Message $_.Exception.Message
  exit 1
}
