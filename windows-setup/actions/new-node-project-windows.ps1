#requires -Version 5.1
<#
Creates a new Node.js project scaffold aligned with the Aryan workstation toolchain.

Toolchain expectations:
- Node.js installed
- pnpm available (recommended via: setup-aryan install-node-toolchain-windows)
  (This installs Node LTS and activates pnpm via corepack.)

Layout:
D:\dev\projects\<Name>\
  src\index.js
  scripts\dev.ps1
  scripts\run.ps1
  README.md
  package.json

Usage:
  setup-aryan new-node-project-windows -Name myapp
  setup-aryan new-node-project-windows -Name myapp -Force

Notes:
- This is a minimal "node app" scaffold (not Next/Vite). We keep it dependency-light.
- If you want templates (Next.js, Vite, Express API) we can add flags later.

State (NO JSON):
  D:\aryan-setup\state-files\new-node-project-windows.state
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidatePattern("^[a-zA-Z0-9][a-zA-Z0-9\-_]+$")]
  [string]$Name,

  [Parameter(Mandatory=$false)]
  [string]$ProjectsRoot = "D:\dev\projects",

  [Parameter(Mandatory=$false)]
  [switch]$Force,

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

$ActionName = "new-node-project-windows"
$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$LogFile    = Join-Path $LogsRoot  "$ActionName.log"
$StateFile  = Join-Path $StateRoot "$ActionName.state"

function Show-Help { Get-Help -Detailed $MyInvocation.MyCommand.Path }
if ($Help) { Show-Help; exit 0 }

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-ISTStamp {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
  $nowIst = [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz)
  return "IST " + $nowIst.ToString("dd-MM-yyyy HH:mm:ss")
}

function Write-Log([ValidateSet("Error","Warning","Info","Debug")] [string]$Level, [string]$Message) {
  Ensure-Dir $LogsRoot
  Add-Content -LiteralPath $LogFile -Value "$(Get-ISTStamp) $Level $Message" -Encoding UTF8
  switch ($Level) {
    "Error"   { Write-Error   $Message }
    "Warning" { Write-Warning $Message }
    "Info"    { Write-Host    $Message }
    "Debug"   { Write-Host    $Message }
  }
}

function Get-ISO8601 { (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK") }
function Get-Version { return "1.1.0" }

function Write-State([string]$Status, [int]$Rc, [string]$StartedAt, [string]$FinishedAt, [string]$ProjectDir) {
  Ensure-Dir $StateRoot
  $content = @(
    "action=$ActionName",
    "status=$Status",
    "rc=$Rc",
    "started_at=$StartedAt",
    "finished_at=$FinishedAt",
    "user=$([Environment]::UserName)",
    "host=$env:COMPUTERNAME",
    "log_path=$LogFile",
    "version=$(Get-Version)",
    "project=$Name",
    "project_dir=$ProjectDir"
  )
  $tmp = "$StateFile.tmp"
  Set-Content -LiteralPath $tmp -Value $content -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}

function Write-Text([string]$Path, [string]$Content) {
  Ensure-Dir (Split-Path -Parent $Path)
  Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Assert-Toolchain {
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "node not found. Install Node.js LTS (or run: setup-aryan install-node-toolchain-windows)."
  }
  if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    throw "pnpm not found. Run: setup-aryan install-node-toolchain-windows (corepack + pnpm)."
  }
}

# ---------------------------
# Main
# ---------------------------
if (-not (Test-Path -LiteralPath "D:\")) { Write-Error "D:\ drive not found." ; exit 1 }
Ensure-Dir $LogsRoot
Ensure-Dir $StateRoot

$startedAt = Get-ISO8601
$rc = 0
$status = "success"
$ProjectDir = Join-Path $ProjectsRoot $Name

try {
  Assert-Toolchain

  Ensure-Dir $ProjectsRoot

  if (-not (Test-Path -LiteralPath $ProjectDir)) {
    New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null
  } else {
    $items = Get-ChildItem -LiteralPath $ProjectDir -Force -ErrorAction SilentlyContinue
    if ($items.Count -gt 0 -and -not $Force) {
      throw "Project directory exists and is not empty: $ProjectDir. Re-run with -Force to overwrite scaffold files."
    }
  }

  Ensure-Dir (Join-Path $ProjectDir "src")
  Ensure-Dir (Join-Path $ProjectDir "scripts")

  $pkg = @"
{
  "name": "$Name",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node src/index.js",
    "dev": "node --watch src/index.js",
    "lint": "echo \"(add eslint later if needed)\"",
    "test": "echo \"(add tests later)\""
  }
}
"@
  Write-Text -Path (Join-Path $ProjectDir "package.json") -Content $pkg

  $main = @"
console.log("Hello from $Name!");
console.log("Node:", process.version);
"@
  Write-Text -Path (Join-Path $ProjectDir "src\index.js") -Content $main

  $devPs = @"
#requires -Version 5.1
param([switch]`$Reinstall)

`$ErrorActionPreference = "Stop"
Set-Location `"$ProjectDir`"

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  throw "pnpm not found. Run: setup-aryan install-node-toolchain-windows"
}

if (`$Reinstall -or -not (Test-Path -LiteralPath (Join-Path `"$ProjectDir`" "node_modules"))) {
  Write-Host "Installing deps with pnpm..."
  pnpm install
}

Write-Host "Starting dev (node --watch)..."
pnpm dev
"@
  Write-Text -Path (Join-Path $ProjectDir "scripts\dev.ps1") -Content $devPs

  $runPs = @"
#requires -Version 5.1
`$ErrorActionPreference = "Stop"
Set-Location `"$ProjectDir`"

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  throw "pnpm not found. Run: setup-aryan install-node-toolchain-windows"
}

pnpm start
"@
  Write-Text -Path (Join-Path $ProjectDir "scripts\run.ps1") -Content $runPs

  $readme = @"
# $Name

Minimal Node.js scaffold created by \`new-node-project-windows.ps1\`.

## Requirements
- Node.js (LTS)
- pnpm (via corepack) — recommended: \`setup-aryan install-node-toolchain-windows\`

## Quick start (PowerShell)
Install deps + run in watch mode:
```powershell
.\scripts\dev.ps1
"@
Write-Text -Path (Join-Path $ProjectDir "README.md") -Content $readme

optional: initialize pnpm lockfile; safe even with no deps

try {
Set-Location $ProjectDir
pnpm install | Out-Null
} catch {
Write-Log Warning "pnpm install step failed (scaffold still created). Details: $($_.Exception.Message)"
}

Write-Log Info "Node project created: $ProjectDir"
} catch {
$rc = 1
$status = "failed"
Write-Log Error $_.Exception.Message
}

$finishedAt = Get-ISO8601
try { Write-State $status $rc $startedAt $finishedAt $ProjectDir } catch {}
exit $rc