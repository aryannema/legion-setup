#requires -Version 5.1
<#
stage-aryan-setup.ps1

Purpose:
  Idempotently stage Windows "setup-aryan" framework from this repo into:
    - C:\Tools\aryan-setup\
    - D:\aryan-setup\logs\
    - D:\aryan-setup\state\

Prerequisites:
  - Windows 11
  - PowerShell 5.1+ (built-in) or PowerShell 7
  - Admin recommended (to create C:\Tools)
  - D: drive present (for logs/state as per repo policy)

Usage:
  powershell -ExecutionPolicy Bypass -File .\windows-setup\stage-aryan-setup.ps1
  powershell -ExecutionPolicy Bypass -File .\windows-setup\stage-aryan-setup.ps1 -Help

Notes:
  - Safe to run multiple times (idempotent).
  - Adds a user profile block (idempotent) to define:
      setup-aryan
      setup-aryan-log
    and tab completion for action names.
#>

param(
  [switch]$Help
)

$TZ = "India Standard Time"

function Get-TimeStamp {
  try {
    $now = Get-Date
    $tz  = [System.TimeZoneInfo]::FindSystemTimeZoneById($TZ)
    $local = [System.TimeZoneInfo]::ConvertTime($now, $tz)
    $abbr = "IST"
    return "{0} {1}" -f $abbr, $local.ToString("dd-MM-yyyy HH:mm:ss")
  } catch {
    return (Get-Date).ToString("dd-MM-yyyy HH:mm:ss")
  }
}

function Log-Info($msg)  { Write-Host "$(Get-TimeStamp) INFO stage-aryan-setup: $msg" }
function Log-Warn($msg)  { Write-Warning "$(Get-TimeStamp) WARNING stage-aryan-setup: $msg" }
function Log-Err($msg)   { Write-Error "$(Get-TimeStamp) ERROR stage-aryan-setup: $msg" }

function Is-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($Help) {
  @"
stage-aryan-setup.ps1

Usage:
  powershell -ExecutionPolicy Bypass -File .\windows-setup\stage-aryan-setup.ps1

Stages to:
  C:\Tools\aryan-setup\
  D:\aryan-setup\logs\
  D:\aryan-setup\state\

"@ | Write-Host
  exit 0
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$srcBin = Join-Path $repoRoot "windows-setup\bin"
$srcActions = Join-Path $repoRoot "windows-setup\actions"

$dstRoot = "C:\Tools\aryan-setup"
$dstBin = Join-Path $dstRoot "bin"
$dstActions = Join-Path $dstRoot "actions"

$logRoot = "D:\aryan-setup\logs"
$stateRoot = "D:\aryan-setup\state"

Log-Info "Repo root: $repoRoot"
Log-Info "Staging to: $dstRoot"
Log-Info "Logs to: $logRoot"
Log-Info "State to: $stateRoot"

if (-not (Test-Path "D:\")) {
  Log-Err "D: drive not found. This repo expects logs/state on D:. Create/mount D: then re-run."
  exit 1
}

if (-not (Is-Admin)) {
  Log-Warn "Not running as Admin. Creating C:\Tools may fail. Run elevated PowerShell if this fails."
}

# Ensure directories
New-Item -ItemType Directory -Force -Path $dstRoot, $dstBin, $dstActions | Out-Null
New-Item -ItemType Directory -Force -Path $logRoot, $stateRoot | Out-Null

# Copy files (idempotent overwrite)
if (Test-Path $srcBin) {
  Copy-Item -Force -Recurse -Path (Join-Path $srcBin "*") -Destination $dstBin
} else {
  Log-Warn "Missing repo folder: $srcBin"
}

if (Test-Path $srcActions) {
  Copy-Item -Force -Recurse -Path (Join-Path $srcActions "*") -Destination $dstActions
} else {
  # It's ok if empty for now
  Log-Info "No actions folder yet (ok): $srcActions"
}

# Profile integration (idempotent)
$profilePath = $PROFILE.CurrentUserAllHosts
$markerBegin = "# >>> aryan-setup BEGIN >>>"
$markerEnd   = "# <<< aryan-setup END <<<"

$block = @"
$markerBegin
`$env:Path = "$dstBin;`$env:Path"

function setup-aryan {
  param(
    [Parameter(Position=0)]
    [string]`$Action = "list",
    [Parameter(ValueFromRemainingArguments=`$true)]
    [string[]]`$Args
  )
  & "$dstBin\setup-aryan.ps1" -Action `$Action -Args `$Args
}

function setup-aryan-log {
  param(
    [Parameter(Position=0)]
    [string]`$Action = "list",
    [switch]`$Follow
  )
  & "$dstBin\setup-aryan-log.ps1" -Action `$Action -Follow:`$Follow
}

Register-ArgumentCompleter -CommandName setup-aryan -ScriptBlock {
  param(`$commandName, `$parameterName, `$wordToComplete, `$commandAst, `$fakeBoundParameters)
  `$actionsDir = "$dstActions"
  `$items = @("list")
  if (Test-Path `$actionsDir) {
    `$items += (Get-ChildItem -Path `$actionsDir -Filter "*.ps1" -File | ForEach-Object { `$_.BaseName })
  }
  `$items | Where-Object { `$_ -like "`$wordToComplete*" } | ForEach-Object {
    [System.Management.Automation.CompletionResult]::new(`$_, `$_, 'ParameterValue', `$_)
  }
}
$markerEnd
"@

# Ensure profile file exists
if (-not (Test-Path $profilePath)) {
  New-Item -ItemType File -Force -Path $profilePath | Out-Null
}

$profileText = Get-Content -Raw -Path $profilePath

if ($profileText -match [regex]::Escape($markerBegin)) {
  # Replace existing block
  $pattern = [regex]::Escape($markerBegin) + "(.|\r|\n)*?" + [regex]::Escape($markerEnd)
  $profileText = [regex]::Replace($profileText, $pattern, $block)
  Set-Content -Path $profilePath -Value $profileText -Encoding UTF8
  Log-Info "Updated existing profile block: $profilePath"
} else {
  Add-Content -Path $profilePath -Value "`r`n$block`r`n" -Encoding UTF8
  Log-Info "Added profile block: $profilePath"
}

Log-Info "Staging complete."
Log-Info "Open a new PowerShell and run: setup-aryan list"
