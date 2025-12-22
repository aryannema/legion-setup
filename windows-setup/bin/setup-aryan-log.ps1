#requires -Version 5.1
<#
setup-aryan-log.ps1

Purpose:
  View logs for a staged Windows action.

Prerequisites:
  - Logs stored in D:\aryan-setup\logs\

Usage:
  setup-aryan-log list
  setup-aryan-log <action>
  setup-aryan-log <action> -Follow
#>

param(
  [string]$Action = "list",
  [switch]$Follow
)

$LogDir = "D:\aryan-setup\logs"

if (-not (Test-Path $LogDir)) {
  Write-Host "No log directory found: $LogDir"
  exit 0
}

if ($Action -eq "list") {
  Get-ChildItem -Path $LogDir -Filter "*.log" -File | Sort-Object Name | ForEach-Object {
    $_.Name
  }
  exit 0
}

$path = Join-Path $LogDir ($Action + ".log")
if (-not (Test-Path $path)) {
  Write-Host "No log found: $path"
  Write-Host "Try: setup-aryan-log list"
  exit 2
}

if ($Follow) {
  Get-Content -Path $path -Tail 200 -Wait
} else {
  Get-Content -Path $path -Tail 200
}
