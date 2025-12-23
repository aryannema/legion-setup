#requires -Version 5.1
<#
Prerequisites
- Windows 11
- Windows PowerShell 5.1
- Internet access
- D:\dev exists (script will create minimal structure if missing)

Usage
  setup-aryan install-python-toolchain-windows -Help
  setup-aryan install-python-toolchain-windows
  setup-aryan install-python-toolchain-windows -Force

What it does (idempotent)
- Installs Miniconda to: D:\dev\tools\miniconda3
- Configures Conda to store:
  - pkgs: D:\dev\cache\conda\pkgs
  - envs: D:\dev\envs\conda
- Disables base auto-activation
- Installs uv to: D:\dev\tools\uv
- Pins uv cache to: D:\dev\cache\uv
- Adds Miniconda + uv to USER PATH (safe, idempotent)
- Writes state-file (NO JSON):
  D:\aryan-setup\state-files\install-python-toolchain-windows.state

Notes (TODO #1: toolchain reliability)
- This script intentionally avoids "conda init" side-effects. Instead, it adds a small marker block to
  your PowerShell profile that enables `conda activate` reliably.
- For VS Code: project generators will create .vscode/settings.json that points to the per-project conda env.

#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [switch]$Force,

  [Parameter(Mandatory=$false)]
  [string]$DevRoot = "D:\dev",

  [Parameter(Mandatory=$false)]
  [string]$CondaPrefix = "D:\dev\tools\miniconda3",

  [Parameter(Mandatory=$false)]
  [string]$UvDir = "D:\dev\tools\uv",

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

# ---------------------------
# Identity / dirs
# ---------------------------
$ActionName = "install-python-toolchain-windows"
$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$LogFile    = Join-Path $LogsRoot  "$ActionName.log"
$StateFile  = Join-Path $StateRoot "$ActionName.state"

function Show-Help { Get-Help -Detailed $MyInvocation.MyCommand.Path }
if ($Help) { Show-Help; exit 0 }

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Get-ISTStamp {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
  $nowIst = [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz)
  return "IST " + $nowIst.ToString("dd-MM-yyyy HH:mm:ss")
}

function Write-Log {
  param([ValidateSet("Error","Warning","Info","Debug")] [string]$Level, [string]$Message)
  Ensure-Dir -Path $LogsRoot
  $line = "$(Get-ISTStamp) $Level $Message"
  Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
  switch ($Level) {
    "Error"   { Write-Error   $Message -ErrorAction Continue }
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
    $idx = $ln.IndexOf("=")
    if ($idx -lt 1) { continue }
    $k = $ln.Substring(0, $idx).Trim()
    $v = $ln.Substring($idx + 1).Trim()
    if ($k.Length -gt 0) { $map[$k] = $v }
  }
  return $map
}

function Write-State {
  param(
    [Parameter(Mandatory=$true)][string]$Status,
    [Parameter(Mandatory=$true)][int]$Rc,
    [Parameter(Mandatory=$true)][string]$StartedAt,
    [Parameter(Mandatory=$true)][string]$FinishedAt
  )
  Ensure-Dir -Path $StateRoot
  $user = [Environment]::UserName
  $hostName = $env:COMPUTERNAME
  $version = Get-Version
  $content = @()
  $content += "action=$ActionName"
  $content += "status=$Status"
  $content += "rc=$Rc"
  $content += "started_at=$StartedAt"
  $content += "finished_at=$FinishedAt"
  $content += "user=$user"
  $content += "host=$hostName"
  $content += "log_path=$LogFile"
  $content += "version=$version"

  $tmp = "$StateFile.tmp"
  Set-Content -LiteralPath $tmp -Value $content -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $StateFile -Force
}

function Add-ToUserPath {
  param([Parameter(Mandatory=$true)][string]$DirToAdd)

  $current = [Environment]::GetEnvironmentVariable("Path","User")
  if ([string]::IsNullOrWhiteSpace($current)) { $current = "" }

  $parts = $current.Split(";") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  foreach ($p in $parts) {
    if ($p.TrimEnd("\") -ieq $DirToAdd.TrimEnd("\")) { return }
  }

  $new = if ($current.Trim().EndsWith(";") -or $current.Trim().Length -eq 0) { "$current$DirToAdd" } else { "$current;$DirToAdd" }
  [Environment]::SetEnvironmentVariable("Path","$new","User")
}

function Set-Tls12 {
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
}

function Download-File {
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][string]$OutFile
  )

  Set-Tls12
  Write-Log Info "Downloading: $Url"

  try {
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
    return
  } catch {
    Write-Log Warning "Invoke-WebRequest failed: $($_.Exception.Message)"
  }

  $curl = Join-Path $env:SystemRoot "System32\curl.exe"
  if (Test-Path -LiteralPath $curl) {
    $p = Start-Process -FilePath $curl -ArgumentList @("-L", $Url, "-o", $OutFile) -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "curl.exe failed with exit code: $($p.ExitCode)" }
    return
  }

  throw "Download failed and curl.exe not available."
}

function Ensure-Miniconda {
  $condaExe = Join-Path $CondaPrefix "Scripts\conda.exe"
  if (Test-Path -LiteralPath $condaExe) {
    Write-Log Info "Miniconda already present: $CondaPrefix"
    return $condaExe
  }

  Ensure-Dir -Path (Split-Path -Parent $CondaPrefix)

  $installer = Join-Path $env:TEMP "Miniconda3-latest-Windows-x86_64.exe"
  if (Test-Path -LiteralPath $installer) { Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue }

  Download-File -Url "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe" -OutFile $installer

  Write-Log Info "Installing Miniconda to: $CondaPrefix"
  $args = @(
    "/InstallationType=JustMe",
    "/AddToPath=0",
    "/RegisterPython=0",
    "/S",
    "/D=$CondaPrefix"
  )

  $p = Start-Process -FilePath $installer -ArgumentList $args -Wait -PassThru
  if ($p.ExitCode -ne 0) {
    throw "Miniconda installer failed with exit code: $($p.ExitCode)"
  }

  if (-not (Test-Path -LiteralPath $condaExe)) {
    throw "Miniconda install completed but conda.exe not found at: $condaExe"
  }

  Write-Log Info "Miniconda installed."
  return $condaExe
}

function Ensure-CondaConfig {
  param([Parameter(Mandatory=$true)][string]$CondaExePath)

  $pkgs = Join-Path $DevRoot "cache\conda\pkgs"
  $envs = Join-Path $DevRoot "envs\conda"

  Ensure-Dir -Path $pkgs
  Ensure-Dir -Path $envs

  Write-Log Info "Configuring conda pkgs_dirs/envs_dirs under D:\dev (idempotent)."
  & $CondaExePath config --set auto_activate_base false | Out-Null
  & $CondaExePath config --set changeps1 false | Out-Null

  & $CondaExePath config --add pkgs_dirs $pkgs | Out-Null
  & $CondaExePath config --add envs_dirs $envs | Out-Null

  Write-Log Info "Conda config set: pkgs_dirs=$pkgs envs_dirs=$envs auto_activate_base=false"
}

function Upsert-ProfileBlock {
  param(
    [Parameter(Mandatory=$true)][string]$ProfilePath,
    [Parameter(Mandatory=$true)][string]$Begin,
    [Parameter(Mandatory=$true)][string]$End,
    [Parameter(Mandatory=$true)][string]$Block
  )

  if (-not (Test-Path -LiteralPath $ProfilePath)) {
    Ensure-Dir -Path (Split-Path -Parent $ProfilePath)
    New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
  }

  $text = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction Stop

  if ($text -match [regex]::Escape($Begin)) {
    $pattern = [regex]::Escape($Begin) + "(.|\r|\n)*?" + [regex]::Escape($End)
    $updated = [regex]::Replace($text, $pattern, $Block)
    Set-Content -LiteralPath $ProfilePath -Value $updated -Encoding UTF8
  } else {
    Add-Content -LiteralPath $ProfilePath -Value "`r`n$Block`r`n" -Encoding UTF8
  }
}

function Ensure-CondaHookInProfile {
  $profilePath = $PROFILE.CurrentUserAllHosts

  $begin = "# >>> setup-aryan conda BEGIN >>>"
  $end   = "# <<< setup-aryan conda END <<<"

  $condaExe = Join-Path $CondaPrefix "Scripts\conda.exe"
  $uvPath   = $UvDir

  # IMPORTANT: escape `$env:Path` and `$_` so they don't expand while writing the profile.
  $block = @"
$begin
# Conda PowerShell hook (idempotent). Required for reliable `conda activate` in PS 5.1.
if (Test-Path -LiteralPath "$condaExe") {
  (& "$condaExe" "shell.powershell" "hook") | Out-String | Invoke-Expression
}

# Ensure uv is reachable (installed by setup-aryan)
if (Test-Path -LiteralPath "$uvPath") {
  if (-not (`$env:Path -split ';' | Where-Object { `$_ -ieq "$uvPath" })) {
    `$env:Path = "$uvPath;`$env:Path"
  }
}
$end
"@

  Upsert-ProfileBlock -ProfilePath $profilePath -Begin $begin -End $end -Block $block
  Write-Log Info "Updated PowerShell profile hook: $profilePath"
}

function Ensure-Uv {
  $uvExe = Join-Path $UvDir "uv.exe"
  if (Test-Path -LiteralPath $uvExe) {
    Write-Log Info "uv already present: $uvExe"
    return $uvExe
  }

  Ensure-Dir -Path $UvDir

  $zip = Join-Path $env:TEMP "uv-x86_64-pc-windows-msvc.zip"
  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }

  Download-File -Url "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip" -OutFile $zip

  Write-Log Info "Extracting uv to: $UvDir"
  Add-Type -AssemblyName System.IO.Compression.FileSystem

  try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $UvDir)
  } catch {
    # If partial extraction happened, try again with overwrite semantics by extracting to temp and copying.
    $tmp = Join-Path $env:TEMP "uv-extract"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    Ensure-Dir -Path $tmp
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
    Copy-Item -Path (Join-Path $tmp "*") -Destination $UvDir -Recurse -Force
  }

  if (-not (Test-Path -LiteralPath $uvExe)) {
    $found = Get-ChildItem -LiteralPath $UvDir -Recurse -Filter "uv.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { Copy-Item -LiteralPath $found.FullName -Destination $uvExe -Force }
  }

  if (-not (Test-Path -LiteralPath $uvExe)) {
    throw "uv.exe not found after extract. Check: $UvDir"
  }

  Write-Log Info "uv installed: $uvExe"
  return $uvExe
}

function Ensure-UserEnvVar {
  param([Parameter(Mandatory=$true)][string]$Name, [Parameter(Mandatory=$true)][string]$Value)
  $cur = [Environment]::GetEnvironmentVariable($Name, "User")
  if ($cur -ne $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Write-Log Info "Set USER env var: $Name=$Value"
  } else {
    Write-Log Debug "USER env var already set: $Name"
  }
}

# ---------------------------
# Main
# ---------------------------
if (-not (Test-Path -LiteralPath "D:\")) {
  Write-Error "D:\ drive not found. Repo policy expects dev/log/state on D:\."
  exit 1
}

Ensure-Dir -Path $LogsRoot
Ensure-Dir -Path $StateRoot

$startedAt = Get-ISO8601

# Idempotency via state-file
try {
  $prev = Read-State
  if ($prev -ne $null -and -not $Force) {
    if ($prev.ContainsKey("status") -and $prev["status"] -eq "success") {
      Write-Log Info "State indicates previous success; skipping. Use -Force to re-run."
      Write-State -Status "skipped" -Rc 0 -StartedAt $startedAt -FinishedAt (Get-ISO8601)
      exit 0
    }
  }
} catch {
  Write-Log Warning "Could not read prior state (continuing): $($_.Exception.Message)"
}

$rc = 0
$status = "success"

try {
  Ensure-Dir -Path $DevRoot
  Ensure-Dir -Path (Join-Path $DevRoot "tools")
  Ensure-Dir -Path (Join-Path $DevRoot "cache")
  Ensure-Dir -Path (Join-Path $DevRoot "envs")

  $condaExe = Ensure-Miniconda
  Ensure-CondaConfig -CondaExePath $condaExe

  $uvExe = Ensure-Uv

  Ensure-UserEnvVar -Name "UV_CACHE_DIR" -Value (Join-Path $DevRoot "cache\uv")
  Ensure-Dir -Path (Join-Path $DevRoot "cache\uv")

  Add-ToUserPath -DirToAdd (Join-Path $CondaPrefix "Scripts")
  Add-ToUserPath -DirToAdd (Join-Path $CondaPrefix "condabin")
  Add-ToUserPath -DirToAdd $UvDir

  Ensure-CondaHookInProfile

  Write-Log Info "Verification checks"
  & $condaExe --version | Out-Null
  & $uvExe --version | Out-Null

  Write-Log Info "Python toolchain ready."
  Write-Log Info "Open a NEW PowerShell for PATH/profile changes to apply."
} catch {
  $rc = 1
  $status = "failed"
  Write-Log Error $_.Exception.Message
}

$finishedAt = Get-ISO8601
try { Write-State -Status $status -Rc $rc -StartedAt $startedAt -FinishedAt $finishedAt } catch {}

exit $rc
