<#
.SYNOPSIS
Creates the recommended Windows dev directory layout on D:\ and sets key USER env vars (idempotent).

.DESCRIPTION
Creates (if missing) the repo’s preferred folder structure so C:\ stays clean:
- D:\dev\repos, tools, envs, cache, tmp
- D:\apps
- D:\profiles\Chrome\UserData and D:\profiles\Chrome\Cache
- (optional) D:\WSL\ and D:\DockerDesktop\ placeholders

Also sets USER environment variables (idempotent):
- GRADLE_USER_HOME = D:\dev\cache\gradle
- ANDROID_AVD_HOME = D:\dev\envs\Android\.android\avd

Optionally creates/updates .wslconfig under the user profile:
- If .wslconfig doesn't exist: it will be created with conservative defaults.
- If -Force is used: existing .wslconfig is backed up and then replaced.

Writes:
- Log:   D:\aryan-setup\logs\prepare-windows-dev-dirs.log
- State: D:\aryan-setup\state-files\prepare-windows-dev-dirs.state   (INI key=value, NO JSON)

Idempotency:
- If previous state indicates success, script will SKIP unless -Force is provided.

.PREREQUISITES
- Windows PowerShell 5.1
- D:\ drive exists (per repo storage layout)

.PARAMETER Force
Re-run even if last run succeeded. Also allows overwriting .wslconfig (with backup).

.PARAMETER CreateWslConfig
Create/ensure .wslconfig with recommended defaults (default: enabled).

.PARAMETER WslMemoryGB
Memory limit for WSL2 in GB (default: 6). Only used when creating/overwriting .wslconfig.

.PARAMETER WslProcessors
CPU cores limit for WSL2 (default: 6). Only used when creating/overwriting .wslconfig.

.PARAMETER WslSwapGB
Swap size for WSL2 in GB (default: 4). Only used when creating/overwriting .wslconfig.

.PARAMETER Help
Show help.

.EXAMPLE
setup-aryan prepare-windows-dev-dirs

.EXAMPLE
setup-aryan prepare-windows-dev-dirs -Force

.EXAMPLE
setup-aryan prepare-windows-dev-dirs -WslMemoryGB 8 -WslProcessors 8
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$false)]
  [switch]$Force,

  [Parameter(Mandatory=$false)]
  [switch]$CreateWslConfig = $true,

  [Parameter(Mandatory=$false)]
  [int]$WslMemoryGB = 6,

  [Parameter(Mandatory=$false)]
  [int]$WslProcessors = 6,

  [Parameter(Mandatory=$false)]
  [int]$WslSwapGB = 4,

  [Parameter(Mandatory=$false)]
  [switch]$Help
)

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"

function Show-Help { Get-Help -Detailed $MyInvocation.MyCommand.Path }
if ($Help) { Show-Help; exit 0 }

# ---------------------------
# Constants
# ---------------------------
$ActionName = "prepare-windows-dev-dirs"
$LogsRoot   = "D:\aryan-setup\logs"
$StateRoot  = "D:\aryan-setup\state-files"
$StateFile  = Join-Path $StateRoot "$ActionName.state"
$LogPath    = Join-Path $LogsRoot  "$ActionName.log"

# Recommended structure
$DirsToEnsure = @(
  "D:\dev\repos",
  "D:\dev\tools",
  "D:\dev\envs",
  "D:\dev\cache",
  "D:\dev\tmp",
  "D:\apps",
  "D:\profiles\Chrome\UserData",
  "D:\profiles\Chrome\Cache",
  "D:\WSL",
  "D:\WSL\backup",
  "D:\DockerDesktop"
)

# User env vars to ensure
$UserEnvTargets = @(
  @{ Name="GRADLE_USER_HOME"; Value="D:\dev\cache\gradle" },
  @{ Name="ANDROID_AVD_HOME"; Value="D:\dev\envs\Android\.android\avd" }
)

$WslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"

# ---------------------------
# Logging helpers
# ---------------------------
function Get-TzOffsetString {
  $offset = [System.TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now)
  $sign = if ($offset.TotalMinutes -ge 0) { "+" } else { "-" }
  $hh = [Math]::Abs([int]$offset.Hours).ToString("00")
  $mm = [Math]::Abs([int]$offset.Minutes).ToString("00")
  return "$sign$hh`:$mm"
}

function Get-Stamp {
  $tz = Get-TzOffsetString
  $dt = Get-Date
  return ("{0} {1}" -f $tz, $dt.ToString("dd-MM-yyyy HH:mm:ss"))
}

function Ensure-Dir {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Log {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("Error","Warning","Info","Debug")][string]$Level,
    [Parameter(Mandatory=$true)][string]$Message
  )
  $line = "{0} {1} {2}" -f (Get-Stamp), $Level, $Message
  Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
  switch ($Level) {
    "Error"   { Write-Error   $Message }
    "Warning" { Write-Warning $Message }
    "Info"    { Write-Host    $Message }
    "Debug"   { Write-Host    $Message }
  }
}

# ---------------------------
# State helpers (key=value; NO JSON)
# ---------------------------
function Read-State {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $map = @{}
  $lines = Get-Content -LiteralPath $Path -ErrorAction Stop
  foreach ($ln in $lines) {
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
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][hashtable]$Fields
  )
  $content = @()
  $content += "action=$($Fields.action)"
  $content += "status=$($Fields.status)"
  $content += "rc=$($Fields.rc)"
  $content += "started_at=$($Fields.started_at)"
  $content += "finished_at=$($Fields.finished_at)"
  $content += "user=$($Fields.user)"
  $content += "host=$($Fields.host)"
  $content += "log_path=$($Fields.log_path)"
  $content += "version=$($Fields.version)"

  $tmp = "$Path.tmp"
  Set-Content -LiteralPath $tmp -Value $content -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-ISO8601 { (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK") }
function Get-Version { return "1.0.0" }

# ---------------------------
# Helpers: env vars
# ---------------------------
function Ensure-UserEnvVar {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Value
  )
  $current = [Environment]::GetEnvironmentVariable($Name, "User")
  if ([string]::IsNullOrWhiteSpace($current)) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Write-Log -Level Info -Message "Set USER env var: $Name=$Value"
    return
  }

  if ($current -ne $Value) {
    if ($Force) {
      [Environment]::SetEnvironmentVariable($Name, $Value, "User")
      Write-Log -Level Info -Message "Updated USER env var (Force): $Name=$Value (was: $current)"
    } else {
      Write-Log -Level Warning -Message "USER env var differs (not changing without -Force): $Name (current: $current, desired: $Value)"
    }
  } else {
    Write-Log -Level Debug -Message "USER env var already set: $Name=$Value"
  }
}

# ---------------------------
# Helpers: .wslconfig
# ---------------------------
function Build-WslConfigContent {
  param(
    [Parameter(Mandatory=$true)][int]$MemGB,
    [Parameter(Mandatory=$true)][int]$Cpu,
    [Parameter(Mandatory=$true)][int]$SwapGBLocal
  )

  if ($MemGB -lt 1) { $MemGB = 6 }
  if ($Cpu -lt 1)   { $Cpu = 6 }
  if ($SwapGBLocal -lt 0) { $SwapGBLocal = 4 }

@"
[wsl2]
memory=${MemGB}GB
processors=$Cpu
swap=${SwapGBLocal}GB
"@
}

function Ensure-WslConfig {
  $content = Build-WslConfigContent -MemGB $WslMemoryGB -Cpu $WslProcessors -SwapGBLocal $WslSwapGB

  if (-not (Test-Path -LiteralPath $WslConfigPath)) {
    Set-Content -LiteralPath $WslConfigPath -Value $content -Encoding ASCII
    Write-Log -Level Info -Message "Created .wslconfig at $WslConfigPath"
    return
  }

  # Exists
  $existing = ""
  try { $existing = Get-Content -LiteralPath $WslConfigPath -Raw -ErrorAction Stop } catch { $existing = "" }

  if ($existing -eq $content) {
    Write-Log -Level Debug -Message ".wslconfig already matches desired content."
    return
  }

  if (-not $Force) {
    Write-Log -Level Warning -Message ".wslconfig exists and differs. Not changing without -Force. Path: $WslConfigPath"
    return
  }

  # Force overwrite with backup
  $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $bak = "$WslConfigPath.bak.$ts"
  Copy-Item -LiteralPath $WslConfigPath -Destination $bak -Force
  Set-Content -LiteralPath $WslConfigPath -Value $content -Encoding ASCII
  Write-Log -Level Info -Message "Backed up existing .wslconfig to: $bak"
  Write-Log -Level Info -Message "Overwrote .wslconfig (Force) with desired limits."
}

# ---------------------------
# Begin
# ---------------------------
if (-not (Test-Path -LiteralPath "D:\")) {
  Write-Error "D:\ drive not found. Repo policy expects logs/state on D:\."
  exit 1
}

Ensure-Dir -Path $LogsRoot
Ensure-Dir -Path $StateRoot

$StartedAt = Get-ISO8601
$UserName  = [Environment]::UserName
$HostName  = $env:COMPUTERNAME
$Version   = Get-Version

Write-Log -Level Info -Message "Starting: $ActionName"
Write-Log -Level Info -Message "Force: $Force"

# Idempotency: if last success and not forced, skip
try {
  $prev = Read-State -Path $StateFile
  if ($prev -ne $null -and -not $Force) {
    if ($prev.ContainsKey("status") -and $prev["status"] -eq "success") {
      Write-Log -Level Info -Message "Previous state was success; skipping. Use -Force to re-run."
      $FinishedAt = Get-ISO8601
      Write-State -Path $StateFile -Fields @{
        action      = $ActionName
        status      = "skipped"
        rc          = 0
        started_at  = $StartedAt
        finished_at = $FinishedAt
        user        = $UserName
        host        = $HostName
        log_path    = $LogPath
        version     = $Version
      }
      exit 0
    }
  }
} catch {
  Write-Log -Level Warning -Message "Could not read previous state (continuing): $($_.Exception.Message)"
}

$rc = 0
$status = "success"

try {
  # Create directories
  foreach ($d in $DirsToEnsure) {
    Ensure-Dir -Path $d
    Write-Log -Level Debug -Message "Ensured dir: $d"
  }
  Write-Log -Level Info -Message "Directory layout ensured on D:\."

  # Ensure extra cache dirs
  Ensure-Dir -Path "D:\dev\cache\gradle"
  Ensure-Dir -Path "D:\dev\envs\Android\.android\avd"

  # Set USER env vars (non-admin)
  foreach ($item in $UserEnvTargets) {
    Ensure-UserEnvVar -Name $item.Name -Value $item.Value
  }

  # .wslconfig
  if ($CreateWslConfig) {
    Ensure-WslConfig
    Write-Log -Level Info -Message "WSL config check complete."
    Write-Log -Level Info -Message "If you changed .wslconfig, run: wsl --shutdown"
  } else {
    Write-Log -Level Info -Message "CreateWslConfig not set; skipping .wslconfig management."
  }

  Write-Log -Level Info -Message "Done."
} catch {
  $rc = 1
  $status = "failed"
  Write-Log -Level Error -Message "Failed: $($_.Exception.Message)"
}

$FinishedAt = Get-ISO8601
try {
  Write-State -Path $StateFile -Fields @{
    action      = $ActionName
    status      = $status
    rc          = $rc
    started_at  = $StartedAt
    finished_at = $FinishedAt
    user        = $UserName
    host        = $HostName
    log_path    = $LogPath
    version     = $Version
  }
} catch {
  Write-Log -Level Warning -Message "Failed to write state file: $($_.Exception.Message)"
}

exit $rc
