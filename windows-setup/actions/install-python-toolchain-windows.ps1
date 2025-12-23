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
- Adds Miniconda + uv to USER PATH
- Writes logs/state in repo-standard locations
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [switch]$Force,

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ActionName = "install-python-toolchain-windows"
$Version    = "1.1.2"

$DevRoot     = "D:\dev"
$ToolsRoot   = Join-Path $DevRoot "tools"
$CacheRoot   = Join-Path $DevRoot "cache"
$EnvsRoot    = Join-Path $DevRoot "envs"

$CondaPrefix = Join-Path $ToolsRoot "miniconda3"
$UvDir       = Join-Path $ToolsRoot "uv"
$UvCache     = Join-Path $CacheRoot "uv"

$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$LogFile    = Join-Path $LogsRoot  "$ActionName.log"
$StateFile  = Join-Path $StateRoot "$ActionName.state"

function Show-Help {
@"
$ActionName (version=$Version)

Usage:
  setup-aryan $ActionName -Help
  setup-aryan $ActionName
  setup-aryan $ActionName -Force
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

function Get-ISTStamp {
  try {
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
    $dt = [System.TimeZoneInfo]::ConvertTime((Get-Date), $tz)
    return ("IST {0}" -f $dt.ToString("dd-MM-yyyy HH:mm:ss"))
  } catch {
    return ("IST {0}" -f (Get-Date).ToString("dd-MM-yyyy HH:mm:ss"))
  }
}

function Write-Log {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("Error","Warning","Info","Debug")][string]$Level,
    [Parameter(Mandatory=$true)][string]$Message
  )
  Ensure-Dir -Path $LogsRoot
  Ensure-Dir -Path $StateRoot
  Add-Content -LiteralPath $LogFile -Value "$(Get-ISTStamp) $Level $Message" -Encoding UTF8

  switch ($Level) {
    "Error"   { Write-Error   $Message -ErrorAction Continue }
    "Warning" { Write-Warning $Message }
    "Info"    { Write-Host    $Message }
    "Debug"   { Write-Host    $Message }
  }
}

function Get-ISO8601 { (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK") }

function Read-State {
  if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
  $map = @{}
  $lines = Get-Content -LiteralPath $StateFile -ErrorAction Stop
  foreach ($ln in $lines) {
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    if ($ln.TrimStart().StartsWith("#")) { continue }
    $idx = $ln.IndexOf("=")
    if ($idx -lt 1) { continue }
    $k = $ln.Substring(0, $idx).Trim()
    $v = $ln.Substring($idx + 1).Trim()
    if ($k) { $map[$k] = $v }
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
  $content = @(
    "status=$Status",
    "rc=$Rc",
    "action=$ActionName",
    "version=$Version",
    "started_at=$StartedAt",
    "finished_at=$FinishedAt",
    "force=$Force",
    "dev_root=$DevRoot"
  )
  Set-Content -LiteralPath $StateFile -Value $content -Encoding UTF8
}

function Ensure-UserEnvVar {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Value
  )
  $cur = [Environment]::GetEnvironmentVariable($Name, "User")
  if ($cur -ne $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Write-Log Info "Set USER env var: $Name=$Value"
  } else {
    Write-Log Debug "USER env var already set: $Name=$Value"
  }
}

function Add-ToUserPath {
  param([Parameter(Mandatory=$true)][string]$DirToAdd)

  $current = [Environment]::GetEnvironmentVariable("Path", "User")
  if ([string]::IsNullOrWhiteSpace($current)) { $current = "" }

  $parts = $current.Split(";") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
  foreach ($p in $parts) {
    if ($p.TrimEnd("\") -ieq $DirToAdd.TrimEnd("\")) {
      Write-Log Debug "USER PATH already contains: $DirToAdd"
      return
    }
  }

  $new = if ($current.Trim().Length -eq 0) { $DirToAdd } else { "$current;$DirToAdd" }
  [Environment]::SetEnvironmentVariable("Path", $new, "User")
  Write-Log Info "Added to USER PATH: $DirToAdd"
  Write-Log Info "Open a new terminal for PATH changes to take effect."
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

function Upsert-ProfileLoaderBlock {
  param(
    [Parameter(Mandatory=$true)][string]$ProfilePath,
    [Parameter(Mandatory=$true)][string]$Begin,
    [Parameter(Mandatory=$true)][string]$End,
    [Parameter(Mandatory=$true)][string]$LoaderBlock
  )

  Ensure-Dir -Path (Split-Path -Parent $ProfilePath)
  if (-not (Test-Path -LiteralPath $ProfilePath)) {
    New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
  }

  $text = ""
  try { $text = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction Stop } catch { $text = "" }

  # Purge ALL occurrences (handles duplicates + nested blocks safely)
  $pattern = [regex]::Escape($Begin) + "(.|\r|\n)*?" + [regex]::Escape($End)
  $clean = [regex]::Replace($text, $pattern, "", [System.Text.RegularExpressions.RegexOptions]::Singleline)

  if (-not [string]::IsNullOrWhiteSpace($clean) -and -not $clean.EndsWith("`r`n")) { $clean += "`r`n" }
  Set-Content -LiteralPath $ProfilePath -Value ($clean + $LoaderBlock + "`r`n") -Encoding UTF8
}




function Ensure-SetupAryanProfileHook {
  $profilePath = $PROFILE.CurrentUserAllHosts

  $begin = "# >>> setup-aryan BEGIN >>>"
  $end   = "# <<< setup-aryan END <<<"

  $managed = "C:\Tools\aryan-setup\bin\setup-aryan-profile.ps1"
  Ensure-Dir -Path (Split-Path -Parent $managed)

  $condaExe = (Join-Path $CondaPrefix "Scripts\conda.exe")
  $uvDir    = $UvDir

  # Managed hook content: overwrite each run (deterministic)
  $managedContent = @"
# setup-aryan managed profile hook (generated). Safe to overwrite.

# Conda PowerShell hook (idempotent).
`$__condaExe = "$condaExe"
if (Test-Path -LiteralPath `$__condaExe) {
  (& `$__condaExe "shell.powershell" "hook") | Out-String | Invoke-Expression
}

# Ensure uv is on PATH for this session.
`$__uvDir = "$uvDir"
if (Test-Path -LiteralPath `$__uvDir) {
  `$parts = `$env:Path -split ';'
  `$found = `$false
  foreach (`$p in `$parts) {
    if (`$p.TrimEnd('\') -ieq `$__uvDir.TrimEnd('\')) { `$found = `$true; break }
  }
  if (-not `$found) { `$env:Path = "`$__uvDir;`$env:Path" }
}
"@

  Set-Content -LiteralPath $managed -Value $managedContent -Encoding UTF8
  Write-Log Info "Wrote managed profile hook: $managed"

  # Profile loader block only (boring = robust)
  $loader = @"
$begin
# Loader only. Keep the profile boring and stable.
`$__setupAryanManaged = "$managed"
if (Test-Path -LiteralPath `$__setupAryanManaged) { . `$__setupAryanManaged }
$end
"@

  Upsert-ProfileLoaderBlock -ProfilePath $profilePath -Begin $begin -End $end -LoaderBlock $loader
  Write-Log Info "Updated PowerShell profile loader: $profilePath"
}

function Ensure-BaseDirs {
  Ensure-Dir -Path $DevRoot
  Ensure-Dir -Path $ToolsRoot
  Ensure-Dir -Path $CacheRoot
  Ensure-Dir -Path $EnvsRoot

  Ensure-Dir -Path (Join-Path $CacheRoot "conda\pkgs")
  Ensure-Dir -Path (Join-Path $EnvsRoot  "conda")
  Ensure-Dir -Path $UvCache
}

function Ensure-Miniconda {
  $condaExe = Join-Path $CondaPrefix "Scripts\conda.exe"
  if (Test-Path -LiteralPath $condaExe) {
    Write-Log Info "Miniconda already present: $condaExe"
    return $condaExe
  }

  Ensure-Dir -Path $CondaPrefix

  $installer = Join-Path $env:TEMP "Miniconda3-latest-Windows-x86_64.exe"
  if (Test-Path -LiteralPath $installer) { Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue }

  $url = "https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
  Write-Log Info "Downloading: $url"
  Download-File -Url $url -OutFile $installer
  try { Unblock-File -LiteralPath $installer -ErrorAction SilentlyContinue } catch { }

  Write-Log Info "Installing Miniconda (quiet) to: $CondaPrefix"
  $p = Start-Process -FilePath $installer -ArgumentList @(
    "/InstallationType=JustMe",
    "/RegisterPython=0",
    "/AddToPath=0",
    "/S",
    "/D=$CondaPrefix"
  ) -NoNewWindow -Wait -PassThru

  if ($p.ExitCode -ne 0) { throw "Miniconda installer failed with exit code: $($p.ExitCode)" }

  if (-not (Test-Path -LiteralPath $condaExe)) {
    throw "Miniconda install finished but conda.exe not found at: $condaExe"
  }

  Write-Log Info "Miniconda installed: $condaExe"
  return $condaExe
}

function Configure-Conda {
  $condaExe = Join-Path $CondaPrefix "Scripts\conda.exe"
  if (-not (Test-Path -LiteralPath $condaExe)) { throw "conda.exe not found at: $condaExe" }

  $pkgsDir = Join-Path $CacheRoot "conda\pkgs"
  $envsDir = Join-Path $EnvsRoot  "conda"

  Write-Log Info "Configuring conda directories..."
  & $condaExe config --set pkgs_dirs $pkgsDir | Out-Null
  & $condaExe config --set envs_dirs $envsDir | Out-Null
  & $condaExe config --set auto_activate_base false | Out-Null
  Write-Log Info "Conda configured: pkgs=$pkgsDir, envs=$envsDir, auto_activate_base=false"
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

  $url = "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip"
  Write-Log Info "Downloading uv ZIP: $url"
  Download-File -Url $url -OutFile $zip
  try { Unblock-File -LiteralPath $zip -ErrorAction SilentlyContinue } catch { }

  $tmp = Join-Path $env:TEMP "setup-aryan-uv"
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
  Ensure-Dir -Path $tmp

  Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force

  $found = Get-ChildItem -LiteralPath $tmp -Recurse -File -Filter "uv.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $found) { throw "uv.exe not found inside extracted archive." }

  Copy-Item -LiteralPath $found.FullName -Destination $uvExe -Force

  if (-not (Test-Path -LiteralPath $uvExe)) { throw "Failed to install uv.exe to: $uvExe" }

  Write-Log Info "uv installed: $uvExe"
  return $uvExe
}

function Pin-UvCache {
  Ensure-UserEnvVar -Name "UV_CACHE_DIR" -Value $UvCache
  Write-Log Info "Pinned UV_CACHE_DIR=$UvCache"
}

function Pin-Paths {
  Add-ToUserPath -DirToAdd (Join-Path $CondaPrefix "Scripts")
  Add-ToUserPath -DirToAdd (Join-Path $CondaPrefix "condabin")
  Add-ToUserPath -DirToAdd $UvDir
}

# ---------------------------
# Main
# ---------------------------
$startedAt = Get-ISO8601
$rc = 0
$status = "success"

Write-Log Info "Starting: $ActionName (version=$Version, Force=$Force)"

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

try {
  if (-not (Test-Path -LiteralPath "D:\")) { throw "D:\ drive not found. Repo policy expects tools on D:\" }

  Ensure-BaseDirs
  Ensure-Miniconda | Out-Null
  Configure-Conda
  Ensure-Uv | Out-Null
  Pin-UvCache
  Pin-Paths
  #Ensure-CondaHookInProfile
  Ensure-SetupAryanProfileHook

  Write-Log Info "Done. Open a NEW terminal and run: conda --version ; uv --version"
} catch {
  $rc = 1
  $status = "failed"
  Write-Log Error $_.Exception.Message
}

$finishedAt = Get-ISO8601
try { Write-State -Status $status -Rc $rc -StartedAt $startedAt -FinishedAt $finishedAt } catch { Write-Log Warning "Failed to write state file: $($_.Exception.Message)" }

exit $rc
