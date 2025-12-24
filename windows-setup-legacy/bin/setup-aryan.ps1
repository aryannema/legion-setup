#requires -Version 5.1
[CmdletBinding(PositionalBinding=$true)]
param(
  [Parameter(Position=0)] [string]$Command = "help",
  [Parameter(Position=1)] [string]$Action = "",
  [switch]$Force,
  [Parameter(ValueFromRemainingArguments=$true)] [string[]]$Rest
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$ActionsDir = "C:\Tools\aryan-setup\actions"

function Invoke-Action {
    param([string]$ActionName)
    $path = Join-Path $ActionsDir ($ActionName + ".ps1")
    if (!(Test-Path $path)) { Write-Error "Action not found: $ActionName"; exit 1 }

    Write-Host "Running: $ActionName" -ForegroundColor Cyan

    # THE HARDENED CALL:
    # We explicitly check the Force switch and call the script WITHOUT splatting 'Rest'.
    # This prevents the $null positional parameter error entirely.
    try {
        if ($Force) {
            & $path -Force
        } else {
            & $path
        }
        exit $LASTEXITCODE
    } catch {
        Write-Error "Action Failed: $($_.Exception.Message)"
        exit 1
    }
}

if ($Command -eq "list") { 
    Get-ChildItem $ActionsDir -Filter "*.ps1" | ForEach-Object { Write-Host "  - $($_.BaseName)" }
    exit 0
}

$target = if ($Command -eq "run") { $Action } else { $Command }
Invoke-Action -ActionName $target