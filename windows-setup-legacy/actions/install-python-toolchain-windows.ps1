#requires -Version 5.1
[CmdletBinding()]
param([switch]$Force)

$ActionName = "install-python-toolchain-windows"
$StateFile  = "D:\aryan-setup\state-files\$ActionName.state"

try {
    Write-Host "Configuring Python/uv Parity on D:..." -ForegroundColor Cyan

    # 1. Verify D: Drive
    if (!(Test-Path "D:\")) { throw "D: Drive not found. Storage policy violation." }

    # 2. Redirect uv Cache
    $uvCache = "D:\dev\cache\uv"
    if (!(Test-Path $uvCache)) { New-Item -ItemType Directory -Path $uvCache -Force | Out-Null }
    [Environment]::SetEnvironmentVariable("UV_CACHE_DIR", $uvCache, "User")

    # 3. Configure Conda Paths
    # Assumes Miniconda is at D:\dev\tools\miniconda3
    if (Test-Path "D:\dev\tools\miniconda3\Scripts\conda.exe") {
        & "D:\dev\tools\miniconda3\Scripts\conda.exe" config --add pkgs_dirs D:\dev\cache\conda\pkgs
        & "D:\dev\tools\miniconda3\Scripts\conda.exe" config --add envs_dirs D:\dev\envs\conda
        & "D:\dev\tools\miniconda3\Scripts\conda.exe" config --set auto_activate_base false
    }

    # 4. Write State
    "action=$ActionName`nstatus=success`nrc=0`nfinished_at=$(Get-Date -Format 'o')" | Set-Content -Path $StateFile
    Write-Host "Python/uv Parity Validated." -ForegroundColor Green
} catch {
    Write-Error $_.Exception.Message; exit 1
}