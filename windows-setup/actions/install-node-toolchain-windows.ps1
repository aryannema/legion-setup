<#
Prerequisites
- Windows 11
- PowerShell 5.1+
- Internet access

Usage
  powershell -File .\install-node-toolchain-windows.ps1 -Help
  powershell -File .\install-node-toolchain-windows.ps1

What it does (idempotent)
- Ensures Node.js is installed (prefers winget; falls back to portable zip from nodejs.org index.json)
- Enables Corepack and installs pnpm
- Pins caches/stores to D:\dev\cache\...
  - npm cache:   D:\dev\cache\npm-cache
  - npm prefix:  D:\dev\tools\npm-global
  - pnpm store:  D:\dev\cache\pnpm-store
- Logs:  D:\aryan-setup\logs\install-node-toolchain-windows.log
- State: D:\aryan-setup\state\install-node-toolchain-windows.state.json
#>

[CmdletBinding()]
param([switch]$Help)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ISTTimestamp {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
  $nowIst = [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz)
  return "IST " + $nowIst.ToString("dd-MM-yyyy HH:mm:ss")
}

function Write-Log {
  param([ValidateSet("Error","Warning","Info","Debug")] [string]$Level, [string]$Message)
  $line = "$(Get-ISTTimestamp) $Level $Message"
  Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
  Write-Host $line
}

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Save-State([hashtable]$State) {
  $json = $State | ConvertTo-Json -Depth 7
  Set-Content -Path $script:StateFile -Value $json -Encoding UTF8
}

function Show-Help {
@"
install-node-toolchain-windows.ps1

Ensures Node.js + npm + pnpm (via corepack) with caches pinned to D:\dev\cache.

Outputs:
  Logs : D:\aryan-setup\logs\install-node-toolchain-windows.log
  State: D:\aryan-setup\state\install-node-toolchain-windows.state.json
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }

$LogRoot   = "D:\aryan-setup\logs"
$StateRoot = "D:\aryan-setup\state"
Ensure-Dir $LogRoot
Ensure-Dir $StateRoot

$script:LogFile   = Join-Path $LogRoot "install-node-toolchain-windows.log"
$script:StateFile = Join-Path $StateRoot "install-node-toolchain-windows.state.json"

Write-Log -Level Info -Message "=== START install-node-toolchain-windows ==="

# Layout
$DevRoot   = "D:\dev"
$ToolsRoot = Join-Path $DevRoot "tools"
$CacheRoot = Join-Path $DevRoot "cache"

$NpmCache  = Join-Path $CacheRoot "npm-cache"
$NpmGlobal = Join-Path $ToolsRoot "npm-global"
$PnpmStore = Join-Path $CacheRoot "pnpm-store"

Ensure-Dir $ToolsRoot
Ensure-Dir $CacheRoot
Ensure-Dir $NpmCache
Ensure-Dir $NpmGlobal
Ensure-Dir $PnpmStore

function Ensure-Node {
  $node = Get-Command node -ErrorAction SilentlyContinue
  if ($node) {
    Write-Log -Level Info -Message "Node already present: $($node.Source)"
    return $node.Source
  }

  # Try winget first (best UX)
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if ($winget) {
    Write-Log -Level Info -Message "Node missing. Attempting winget install (OpenJS.NodeJS.LTS, user scope)..."
    try {
      & winget install --id OpenJS.NodeJS.LTS -e --scope user --accept-package-agreements --accept-source-agreements | Out-Null
    } catch {
      Write-Log -Level Warning -Message "winget install failed: $($_.Exception.Message)"
    }

    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
      Write-Log -Level Info -Message "Node installed via winget: $($node.Source)"
      return $node.Source
    }
  } else {
    Write-Log -Level Warning -Message "winget not found; falling back to portable Node zip."
  }

  # Portable fallback using nodejs.org index.json (no hardcoded version)
  Write-Log -Level Info -Message "Installing portable Node (latest LTS) to D:\dev\tools\nodejs\current ..."
  $indexUrl = "https://nodejs.org/dist/index.json"
  $index = Invoke-RestMethod -Uri $indexUrl

  $lts = $index | Where-Object { $_.lts -and $_.lts -ne $false } | Select-Object -First 1
  if (-not $lts) { throw "Could not determine latest LTS from $indexUrl" }

  $ver = $lts.version  # like "v20.12.2"
  $zipName = "node-$ver-win-x64.zip"
  $zipUrl  = "https://nodejs.org/dist/$ver/$zipName"

  $nodeRoot = "D:\dev\tools\nodejs"
  $current  = Join-Path $nodeRoot "current"
  Ensure-Dir $nodeRoot

  $tmpZip = Join-Path $env:TEMP $zipName
  Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing

  # Reset current dir (safe, minimal)
  if (Test-Path -LiteralPath $current) {
    Remove-Item -LiteralPath $current -Recurse -Force
  }
  Ensure-Dir $current

  Expand-Archive -Path $tmpZip -DestinationPath $nodeRoot -Force
  Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue

  # The extracted folder is node-vX.Y.Z-win-x64
  $extracted = Join-Path $nodeRoot ("node-" + $ver + "-win-x64")
  if (-not (Test-Path -LiteralPath $extracted)) { throw "Expected extracted folder missing: $extracted" }

  Move-Item -LiteralPath $extracted -Destination $current -Force

  # Add current to USER PATH if missing
  $userPath = [Environment]::GetEnvironmentVariable("Path","User")
  if ($userPath -notlike "*$current*") {
    [Environment]::SetEnvironmentVariable("Path", ($userPath.TrimEnd(";") + ";" + $current), "User")
    Write-Log -Level Info -Message "Added to USER PATH: $current (new shells will see it)"
  } else {
    Write-Log -Level Debug -Message "USER PATH already contains: $current"
  }

  $nodeExe = Join-Path $current "node.exe"
  if (-not (Test-Path -LiteralPath $nodeExe)) { throw "Portable node.exe missing at $nodeExe" }

  Write-Log -Level Info -Message "Portable Node installed: $nodeExe"
  return $nodeExe
}

$nodeExe = Ensure-Node

# Locate npm/corepack (portable installs include them, winget/msi does too)
function Resolve-Cmd([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

$npmExe = Resolve-Cmd "npm"
$corepackExe = Resolve-Cmd "corepack"

if (-not $npmExe) {
  Write-Log -Level Warning -Message "npm not found in PATH in this session. New shell may be needed."
}
if (-not $corepackExe) {
  Write-Log -Level Warning -Message "corepack not found in PATH in this session. New shell may be needed."
}

# Configure npm cache + prefix (idempotent)
try {
  if ($npmExe) {
    & $npmExe config set cache $NpmCache | Out-Null
    & $npmExe config set prefix $NpmGlobal | Out-Null
    Write-Log -Level Info -Message "npm cache set to: $NpmCache"
    Write-Log -Level Info -Message "npm prefix set to: $NpmGlobal"
  }
} catch {
  Write-Log -Level Warning -Message "npm config set failed (may need new shell): $($_.Exception.Message)"
}

# Enable pnpm via corepack (preferred) and set pnpm store-dir
try {
  if ($corepackExe) {
    & $corepackExe enable | Out-Null
    & $corepackExe prepare pnpm@latest --activate | Out-Null
    Write-Log -Level Info -Message "corepack enabled + pnpm activated"
  }
} catch {
  Write-Log -Level Warning -Message "corepack/pnpm activation failed: $($_.Exception.Message)"
}

$pnpmExe = Resolve-Cmd "pnpm"
try {
  if ($pnpmExe) {
    & $pnpmExe config set store-dir $PnpmStore | Out-Null
    Write-Log -Level Info -Message "pnpm store-dir set to: $PnpmStore"
  } else {
    Write-Log -Level Warning -Message "pnpm not detected in PATH in this session. New shell may be needed."
  }
} catch {
  Write-Log -Level Warning -Message "pnpm config set failed: $($_.Exception.Message)"
}

Save-State @{
  status="ok"
  node_exe=$nodeExe
  npm_cache=$NpmCache
  npm_prefix=$NpmGlobal
  pnpm_store=$PnpmStore
  at=(Get-ISTTimestamp)
}

Write-Log -Level Info -Message "=== DONE install-node-toolchain-windows ==="
exit 0
