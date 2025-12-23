#requires -Version 5.1
<#
.SYNOPSIS
Shows logs for setup-aryan (Windows PowerShell 5.1)

.DESCRIPTION
Reads logs from:
  D:\aryan-setup\logs\

Supports:
- list (default): shows most recent log files
- tail: shows the last N lines of a log file
- show: prints an entire log file
- grep: simple substring filter (case-insensitive)

This script does NOT modify system state.

.PREREQUISITES
- Windows PowerShell 5.1
- Logs directory exists (created by staging/actions): D:\aryan-setup\logs\

.PARAMETER Help
Show help.

.PARAMETER Command
One of: list, tail, show, grep

.PARAMETER Name
Log file name (e.g., stage-windows-setup.log). If not provided, uses setup-aryan.log.

.PARAMETER Lines
For tail: number of last lines to show (default 200)

.PARAMETER Contains
For grep: substring to match (case-insensitive)

.EXAMPLE
setup-aryan-log list

.EXAMPLE
setup-aryan-log tail -Name stage-windows-setup.log -Lines 200

.EXAMPLE
setup-aryan-log show -Name setup-aryan.log

.EXAMPLE
setup-aryan-log grep -Name setup-aryan.log -Contains "Error"
#>

[CmdletBinding(PositionalBinding=$true)]
param(
  [Parameter(Position=0, Mandatory=$false)]
  [ValidateSet("list","tail","show","grep","help")]
  [string]$Command = "list",

  [Parameter(Mandatory=$false)]
  [string]$Name = "",

  [Parameter(Mandatory=$false)]
  [int]$Lines = 200,

  [Parameter(Mandatory=$false)]
  [string]$Contains = "",

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

function Show-Help { Get-Help -Detailed $MyInvocation.MyCommand.Path }

if ($Help -or $Command -eq "help") { Show-Help; exit 0 }

$LogsRoot = "D:\aryan-setup\logs"

function Ensure-LogsRoot {
  if (-not (Test-Path -LiteralPath $LogsRoot)) {
    throw "Logs directory not found: $LogsRoot"
  }
}

function Resolve-LogPath {
  param([Parameter(Mandatory=$false)][string]$LogName)
  if ([string]::IsNullOrWhiteSpace($LogName)) { $LogName = "setup-aryan.log" }
  $p = Join-Path $LogsRoot $LogName
  if (-not (Test-Path -LiteralPath $p)) { throw "Log not found: $p" }
  return $p
}

function Cmd-List {
  Ensure-LogsRoot
  $files = Get-ChildItem -LiteralPath $LogsRoot -Filter "*.log" -File | Sort-Object LastWriteTime -Descending
  if ($files.Count -eq 0) {
    Write-Host "No log files found in: $LogsRoot"
    return
  }
  Write-Host "Logs in $LogsRoot (newest first):"
  foreach ($f in ($files | Select-Object -First 50)) {
    $sz = "{0:n0}" -f $f.Length
    Write-Host ("  {0,-34}  {1}  {2,12} bytes" -f $f.Name, $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"), $sz)
  }
}

function Cmd-Show {
  Ensure-LogsRoot
  $p = Resolve-LogPath -LogName $Name
  Get-Content -LiteralPath $p -ErrorAction Stop
}

function Cmd-Tail {
  Ensure-LogsRoot
  $p = Resolve-LogPath -LogName $Name
  if ($Lines -lt 1) { $Lines = 200 }
  Get-Content -LiteralPath $p -Tail $Lines -ErrorAction Stop
}

function Cmd-Grep {
  Ensure-LogsRoot
  if ([string]::IsNullOrWhiteSpace($Contains)) { throw "grep requires -Contains <substring>" }
  $p = Resolve-LogPath -LogName $Name
  $needle = $Contains.ToLowerInvariant()
  $lines = Get-Content -LiteralPath $p -ErrorAction Stop
  foreach ($ln in $lines) {
    if ($ln.ToLowerInvariant().Contains($needle)) { $ln }
  }
}

try {
  switch ($Command) {
    "list" { Cmd-List; exit 0 }
    "show" { Cmd-Show; exit 0 }
    "tail" { Cmd-Tail; exit 0 }
    "grep" { Cmd-Grep; exit 0 }
    default { Show-Help; exit 1 }
  }
} catch {
  Write-Error $_.Exception.Message
  exit 1
}
