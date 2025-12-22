#requires -Version 5.1
<#
setup-aryan.ps1

Purpose:
  Windows wrapper that runs actions staged in:
    C:\Tools\aryan-setup\actions\

Prerequisites:
  - Staged via windows-setup\stage-aryan-setup.ps1

Usage:
  setup-aryan list
  setup-aryan <action> [args...]

Logging:
  - D:\aryan-setup\logs\<action>.log
  - Format: "<TZ dd-mm-yyyy HH:MM:ss> <LEVEL> <message>"
#>

param(
  [string]$Action = "list",
  [string[]]$Args = @()
)

$TZ = "India Standard Time"
$Root = "C:\Tools\aryan-setup"
$ActionsDir = Join-Path $Root "actions"
$LogDir = "D:\aryan-setup\logs"

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

function Log-Line([string]$Level, [string]$Msg) {
  "{0} {1} {2}" -f (Get-TimeStamp), $Level, $Msg
}

function Ensure-Dirs {
  New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
  New-Item -ItemType Directory -Force -Path "D:\aryan-setup\state" | Out-Null
}

function List-Actions {
  if (-not (Test-Path $ActionsDir)) {
    Write-Host "No actions directory found: $ActionsDir"
    return
  }
  Get-ChildItem -Path $ActionsDir -Filter "*.ps1" -File | Sort-Object Name | ForEach-Object {
    $_.BaseName
  }
}

Ensure-Dirs

if ($Action -eq "list") {
  List-Actions
  exit 0
}

$actionPath = Join-Path $ActionsDir ($Action + ".ps1")
$logPath = Join-Path $LogDir ($Action + ".log")

if (-not (Test-Path $actionPath)) {
  Write-Host "Unknown action: $Action"
  Write-Host "Try: setup-aryan list"
  exit 2
}

$header = @(
  Log-Line "INFO"  "setup-aryan: action=$Action user=$env:USERNAME pwd=$(Get-Location)"
  Log-Line "INFO"  "setup-aryan: action_path=$actionPath"
  Log-Line "INFO"  "setup-aryan: log_path=$logPath"
  ""
) -join "`r`n"

$header | Tee-Object -FilePath $logPath -Append | Out-Null

# Run action and tee output
& powershell -ExecutionPolicy Bypass -File $actionPath @Args 2>&1 | Tee-Object -FilePath $logPath -Append
