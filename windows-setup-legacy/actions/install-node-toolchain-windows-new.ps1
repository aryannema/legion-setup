#requires -Version 5.1
[CmdletBinding()]
param([switch]$Force)

$ActionName = "install-node-toolchain-windows"
$StateFile  = "D:\aryan-setup\state-files\$ActionName.state"

try {
    Write-Host "Configuring Node/pnpm Parity on D:..." -ForegroundColor Cyan

    # 1. Redirect pnpm Store/Cache
    if (Get-Command pnpm -ErrorAction SilentlyContinue) {
        pnpm config set store-dir D:\dev\cache\pnpm\store
        pnpm config set cache-dir D:\dev\cache\pnpm\cache
        Write-Host "pnpm storage redirected to D:\dev\cache"
    }

    # 2. Verify NVM Path Authority
    $nvmHome = [Environment]::GetEnvironmentVariable("NVM_HOME", "User")
    if ($nvmHome -notlike "D:\*") {
        Write-Warning "NVM is not on D: drive. Current: $nvmHome"
    }

    # 3. Write State
    "action=$ActionName`nstatus=success`nrc=0`nfinished_at=$(Get-Date -Format 'o')" | Set-Content -Path $StateFile
    Write-Host "Node/pnpm Parity Validated." -ForegroundColor Green
} catch {
    Write-Error $_.Exception.Message; exit 1
}