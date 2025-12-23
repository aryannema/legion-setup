#requires -Version 5.1
<#
Creates a new Python project scaffold aligned with the Aryan workstation toolchain.

Key points
- Uses Conda env prefix (per-project) under: D:\dev\envs\conda\<project>
- Uses uv for dependency install (uv pip install -r requirements.txt)
- Writes VS Code settings pointing to the env interpreter
- Supports BOTH flags (can co-exist):
  -Ai
  -TensorFlow

Usage
  setup-aryan new-python-project-windows -Name myproj
  setup-aryan new-python-project-windows -Name myproj -Ai
  setup-aryan new-python-project-windows -Name myproj -TensorFlow
  setup-aryan new-python-project-windows -Name myproj -Ai -TensorFlow
  setup-aryan new-python-project-windows -Name myproj -Force

Notes
- This action does not install the toolchain. Run:
    setup-aryan install-python-toolchain-windows
  first.

State (NO JSON)
  D:\aryan-setup\state-files\new-python-project-windows.state
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidatePattern("^[a-zA-Z0-9][a-zA-Z0-9\-_]+$")]
  [string]$Name,

  [Parameter(Mandatory=$false)]
  [string]$ProjectsRoot = "D:\dev\projects",

  [Parameter(Mandatory=$false)]
  [string]$DevRoot = "D:\dev",

  [Parameter(Mandatory=$false)]
  [switch]$Ai,

  [Parameter(Mandatory=$false)]
  [switch]$TensorFlow,

  [Parameter(Mandatory=$false)]
  [switch]$Force,

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

$ActionName = "new-python-project-windows"
$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$LogFile    = Join-Path $LogsRoot  "$ActionName.log"
$StateFile  = Join-Path $StateRoot "$ActionName.state"

function Show-Help { Get-Help -Detailed $MyInvocation.MyCommand.Path }
if ($Help) { Show-Help; exit 0 }

function Ensure-Dir([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }

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

function Read-State {
  if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
  $map = @{}
  foreach ($ln in (Get-Content -LiteralPath $StateFile -ErrorAction Stop)) {
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    if ($ln.TrimStart().StartsWith("#")) { continue }
    $idx = $ln.IndexOf("="); if ($idx -lt 1) { continue }
    $k = $ln.Substring(0, $idx).Trim()
    $v = $ln.Substring($idx + 1).Trim()
    if ($k.Length -gt 0) { $map[$k] = $v }
  }
  return $map
}

function Write-State([string]$Status, [int]$Rc, [string]$StartedAt, [string]$FinishedAt) {
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
    "version=$(Get-Version)"
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
  if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
    throw "conda not found. Run: setup-aryan install-python-toolchain-windows"
  }
  if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "uv not found. Run: setup-aryan install-python-toolchain-windows"
  }
}

function Ensure-CondaActivated {
  # In PS 5.1, conda activation usually needs the shell hook.
  $condaExe = (Get-Command conda -ErrorAction SilentlyContinue).Source
  if (-not $condaExe) { return }
  try { (& $condaExe "shell.powershell" "hook") | Out-String | Invoke-Expression } catch {}
}

# ---------------------------
# Main
# ---------------------------
if (-not (Test-Path -LiteralPath "D:\")) { Write-Error "D:\ drive not found." ; exit 1 }

Ensure-Dir $LogsRoot
Ensure-Dir $StateRoot

$startedAt = Get-ISO8601

try {
  $prev = Read-State
  if ($prev -ne $null -and -not $Force) {
    if ($prev.ContainsKey("status") -and $prev["status"] -eq "success") {
      Write-Log Info "State indicates previous success; skipping. Use -Force to re-run."
      Write-State "skipped" 0 $startedAt (Get-ISO8601)
      exit 0
    }
  }
} catch { }

$rc = 0
$status = "success"

try {
  Assert-Toolchain
  Ensure-CondaActivated

  Ensure-Dir $ProjectsRoot
  $ProjectDir = Join-Path $ProjectsRoot $Name
  $EnvDir     = Join-Path (Join-Path $DevRoot "envs\conda") $Name

  if (-not (Test-Path -LiteralPath $ProjectDir)) {
    New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null
  } else {
    # If directory exists and not -Force, refuse if it looks non-empty (to avoid clobber)
    $items = Get-ChildItem -LiteralPath $ProjectDir -Force -ErrorAction SilentlyContinue
    if ($items.Count -gt 0 -and -not $Force) {
      throw "Project directory already exists and is not empty: $ProjectDir. Re-run with -Force to overwrite scaffold files."
    }
  }

  Ensure-Dir (Join-Path $ProjectDir "src")
  Ensure-Dir (Join-Path $ProjectDir "scripts")
  Ensure-Dir (Join-Path $ProjectDir ".vscode")

  # requirements (minimal; heavy libs only when flags enabled)
  $req = @()
  $req += "pytest"
  $req += "ruff"
  if ($Ai) {
    $req += "numpy"
    $req += "pandas"
    $req += "scikit-learn"
    $req += "matplotlib"
  }
  if ($TensorFlow) {
    $req += "tensorflow"
  }
  $requirementsTxt = ($req | Sort-Object -Unique) -join "`r`n"
  Write-Text -Path (Join-Path $ProjectDir "requirements.txt") -Content $requirementsTxt

  # project config
  $cfg = @"
name: $Name
language: python
paths:
  project_root: $ProjectDir
  conda_env_prefix: $EnvDir
flags:
  ai_ml: $($Ai.ToString().ToLowerInvariant())
  tensorflow: $($TensorFlow.ToString().ToLowerInvariant())
toolchain:
  conda: true
  uv: true
"@
  Write-Text -Path (Join-Path $ProjectDir "project_config.yaml") -Content $cfg

  # VS Code settings -> point to env python
  $vscode = @"
{
  "python.defaultInterpreterPath": "D:\\dev\\envs\\conda\\$Name\\python.exe",
  "python.terminal.activateEnvironment": true,
  "python.analysis.typeCheckingMode": "basic",
  "python.analysis.diagnosticSeverityOverrides": {
    "reportMissingImports": "warning"
  }
}
"@
  Write-Text -Path (Join-Path $ProjectDir ".vscode\settings.json") -Content $vscode

  # Main source
  $main = @"
def main() -> None:
    print("Hello from $Name!")

if __name__ == "__main__":
    main()
"@
  Write-Text -Path (Join-Path $ProjectDir "src\main.py") -Content $main

  # dev script (create/activate env + install deps)
  $dev = @"
#requires -Version 5.1
param(
  [switch]`$Reinstall
)

`$ErrorActionPreference = "Stop"

function Ensure-CondaHook {
  if (Get-Command conda -ErrorAction SilentlyContinue) {
    (`& (Get-Command conda).Source "shell.powershell" "hook") | Out-String | Invoke-Expression
  } else {
    throw "conda not found"
  }
}

Ensure-CondaHook

`$EnvDir = "D:\dev\envs\conda\$Name"
if (-not (Test-Path -LiteralPath `$EnvDir)) {
  Write-Host "Creating conda env: `$EnvDir"
  conda create -y -p `$EnvDir python=3.11
}

conda activate `$EnvDir

if (`$Reinstall) {
  Write-Host "Reinstall requested; upgrading pip"
  python -m pip install -U pip
}

Write-Host "Installing deps with uv (requirements.txt)"
uv pip install -r (Join-Path `"$ProjectDir`" "requirements.txt")

Write-Host ""
Write-Host "Ready."
Write-Host "Run:"
Write-Host "  python src\main.py"
"@
  Write-Text -Path (Join-Path $ProjectDir "scripts\dev.ps1") -Content $dev

  $run = @"
#requires -Version 5.1
`$ErrorActionPreference = "Stop"

# Activate env + run
if (Get-Command conda -ErrorAction SilentlyContinue) {
  (`& (Get-Command conda).Source "shell.powershell" "hook") | Out-String | Invoke-Expression
  conda activate "D:\dev\envs\conda\$Name"
} else {
  throw "conda not found"
}

python (Join-Path `"$ProjectDir`" "src\main.py")
"@
  Write-Text -Path (Join-Path $ProjectDir "scripts\run.ps1") -Content $run

  # TensorFlow validation (only if TensorFlow flag enabled)
  if ($TensorFlow) {
    $tfPy = @"
import os
import time

# Keep logs quieter
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "1")

import tensorflow as tf  # noqa: E402

def main() -> None:
    print("TensorFlow:", tf.__version__)
    gpus = tf.config.list_physical_devices("GPU")
    print("GPUs:", gpus)

    # Avoid grabbing all VRAM (helps notebooks too)
    for g in gpus:
        try:
            tf.config.experimental.set_memory_growth(g, True)
        except Exception as e:
            print("Could not set memory growth:", e)

    a = tf.random.uniform((2048, 2048))
    b = tf.random.uniform((2048, 2048))

    t0 = time.time()
    c = tf.linalg.matmul(a, b)
    _ = c.numpy()  # force execution
    t1 = time.time()

    print("Matmul OK. Seconds:", round(t1 - t0, 3))
    print("If this was your first run, slower time is normal due to CUDA/PTX/XLA warmup.")

if __name__ == "__main__":
    main()
"@
    Write-Text -Path (Join-Path $ProjectDir "src\validate_tf.py") -Content $tfPy

    $tfPs = @"
#requires -Version 5.1
`$ErrorActionPreference = "Stop"

if (Get-Command conda -ErrorAction SilentlyContinue) {
  (`& (Get-Command conda).Source "shell.powershell" "hook") | Out-String | Invoke-Expression
  conda activate "D:\dev\envs\conda\$Name"
} else {
  throw "conda not found"
}

python (Join-Path `"$ProjectDir`" "src\validate_tf.py")
"@
    Write-Text -Path (Join-Path $ProjectDir "scripts\validate_tf.ps1") -Content $tfPs
  }

  # README
  $flagsLine = "- AI/ML: " + ($Ai ? "enabled" : "disabled") + "`r`n- TensorFlow: " + ($TensorFlow ? "enabled" : "disabled")
  $readme = @"
# $Name

Scaffold created by `new-python-project-windows.ps1` (toolchain: conda + uv).

## Flags
$flagsLine

## Layout
- `src/` - app code
- `scripts/` - helper scripts (env/run/test)
- `requirements.txt` - Python deps (installed via `uv pip` inside the conda env)
- `project_config.yaml` - local metadata (includes flags)

## Quick start (PowerShell)
1) Create/activate env + install deps:
```powershell
.\scripts\dev.ps1
"@
Write-Text -Path (Join-Path $ProjectDir "README.md") -Content $readme

Write-Log Info "Project created: $ProjectDir"
Write-Log Info "Env prefix (to be created by scripts/dev.ps1): $EnvDir"
} catch {
$rc = 1
$status = "failed"
Write-Log Error $_.Exception.Message
}

Write-State $status $rc $startedAt (Get-ISO8601)
exit $rc