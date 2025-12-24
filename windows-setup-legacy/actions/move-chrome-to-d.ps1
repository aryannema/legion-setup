<# 
Prerequisites
- Windows PowerShell 5.1
- Google Chrome installed (recommended)
- Target drive D: available

What this action does
- Stops Chrome if running
- Copies existing Chrome profile from:
    %LOCALAPPDATA%\Google\Chrome\User Data
  to:
    D:\profiles\Chrome\UserData
- Ensures cache directory exists:
    D:\profiles\Chrome\Cache
- Creates user shortcuts that launch Chrome with:
    --user-data-dir and --disk-cache-dir pointing to D:
- Writes logs to:
    D:\aryan-setup\logs\
- Writes state-file (INI key=value) to:
    D:\aryan-setup\state-files\move-chrome-to-d.state

Usage
- Help:
    .\move-chrome-to-d.ps1 -Help
- Normal run (skips if previously succeeded):
    .\move-chrome-to-d.ps1
- Force re-run:
    .\move-chrome-to-d.ps1 -Force
#>

[CmdletBinding()]
param(
  [switch]$Force,
  [switch]$Help
)

$ActionName = "move-chrome-to-d"
$Version = "1.0.0"

function Get-TzStamp {
  # Format: "<TZ dd-mm-yyyy HH:MM:ss>"
  # Using offset as TZ (e.g., +05:30) for consistency across systems.
  $d = Get-Date
  return "{0} {1}" -f $d.ToString("zzz"), $d.ToString("dd-MM-yyyy HH:mm:ss")
}

function Write-Log {
  param(
    [ValidateSet("Error","Warning","Info","Debug")]
    [string]$Level,
    [string]$Message
  )
  $line = "{0} {1} {2}" -f (Get-TzStamp), $Level, $Message
  Add-Content -Path $Global:LogFile -Value $line -Encoding UTF8
  Write-Host $line
}

function Ensure-Dir {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Read-State {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $map }
  foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
    if ($line -match '^\s*#') { continue }
    if ($line -match '^\s*$') { continue }
    $parts = $line.Split("=",2)
    if ($parts.Count -eq 2) {
      $k = $parts[0].Trim()
      $v = $parts[1].Trim()
      if ($k) { $map[$k] = $v }
    }
  }
  return $map
}

function Write-State {
  param(
    [string]$Path,
    [hashtable]$Data
  )
  $lines = @()
  foreach ($k in @("action","status","rc","started_at","finished_at","user","host","log_path","version")) {
    if ($Data.ContainsKey($k)) {
      $lines += ("{0}={1}" -f $k, $Data[$k])
    }
  }
  Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

function Find-ChromeExe {
  $candidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
  )
  foreach ($p in $candidates) {
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}

# Help
if ($Help) {
  @"
$ActionName ($Version)

Moves Chrome user data/profile to D: and creates shortcuts that always launch using D:\profiles\Chrome\UserData and D:\profiles\Chrome\Cache.

Usage:
  .\move-chrome-to-d.ps1 -Help
  .\move-chrome-to-d.ps1
  .\move-chrome-to-d.ps1 -Force

State:
  D:\aryan-setup\state-files\move-chrome-to-d.state

Logs:
  D:\aryan-setup\logs\

Notes:
- This does NOT delete the original profile on C: (safe).
- Use the created shortcut going forward to ensure Chrome uses D:.
"@ | Write-Host
  exit 0
}

# Paths
$LogDir   = "D:\aryan-setup\logs"
$StateDir = "D:\aryan-setup\state-files"
Ensure-Dir $LogDir
Ensure-Dir $StateDir

$LogFile = Join-Path $LogDir ("{0}_{1}.log" -f $ActionName, (Get-Date -Format "yyyyMMdd_HHmmss"))
$Global:LogFile = $LogFile
$StateFile = Join-Path $StateDir ("{0}.state" -f $ActionName)

$startedAt = (Get-Date).ToString("o")
$user = $env:USERNAME
$hostName = $env:COMPUTERNAME

# Idempotency check
$prev = Read-State $StateFile
if (-not $Force -and $prev.ContainsKey("status") -and $prev["status"] -eq "success") {
  Write-Log -Level Info -Message "State indicates previous success; skipping. Use -Force to re-run."
  exit 0
}

# Main
$rc = 0
$status = "success"

try {
  Write-Log -Level Info -Message "Starting action: $ActionName (version $Version)"

  # Stop Chrome to avoid profile lock/copy issues
  $chromeProcs = Get-Process -Name "chrome" -ErrorAction SilentlyContinue
  if ($chromeProcs) {
    Write-Log -Level Info -Message "Chrome is running; stopping processes..."
    $chromeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }

  $sourceUserData = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
  $targetUserData = "D:\profiles\Chrome\UserData"
  $targetCache    = "D:\profiles\Chrome\Cache"

  Ensure-Dir "D:\profiles\Chrome"
  Ensure-Dir $targetUserData
  Ensure-Dir $targetCache

  if (Test-Path -LiteralPath $sourceUserData) {
    Write-Log -Level Info -Message "Copying Chrome profile from '$sourceUserData' to '$targetUserData'..."

    # Robust copy: robocopy if available, else fallback to Copy-Item.
    $robocopy = "$env:SystemRoot\System32\robocopy.exe"
    if (Test-Path -LiteralPath $robocopy) {
      # /E = include subdirs, /R:1 /W:1 = quick retry, /NFL /NDL = reduce noise, /NP = no progress
      # We avoid /MIR to prevent accidental deletions of target data.
      $args = @(
        "`"$sourceUserData`"",
        "`"$targetUserData`"",
        "/E","/R:1","/W:1","/NP","/NFL","/NDL"
      )
      $p = Start-Process -FilePath $robocopy -ArgumentList $args -NoNewWindow -Wait -PassThru
      # Robocopy uses bitmask exit codes; 0-7 are generally non-fatal.
      if ($p.ExitCode -gt 7) {
        throw "Robocopy failed with exit code $($p.ExitCode)."
      }
      Write-Log -Level Info -Message "Robocopy completed with exit code $($p.ExitCode)."
    } else {
      Write-Log -Level Warning -Message "Robocopy not found; falling back to Copy-Item (slower)."
      Copy-Item -Path (Join-Path $sourceUserData "*") -Destination $targetUserData -Recurse -Force -ErrorAction Stop
    }
  } else {
    Write-Log -Level Warning -Message "Source Chrome profile not found at '$sourceUserData'. Creating D: structure and shortcuts anyway."
  }

  # Find chrome.exe for shortcut
  $chromeExe = Find-ChromeExe
  if (-not $chromeExe) {
    Write-Log -Level Warning -Message "chrome.exe not found in standard locations. Shortcuts will not be created. Install Chrome, then re-run with -Force."
  } else {
    $args = "--user-data-dir=`"$targetUserData`" --disk-cache-dir=`"$targetCache`""

    # Create shortcut on user desktop
    $desktop = [Environment]::GetFolderPath("Desktop")
    $desktopLnk = Join-Path $desktop "Google Chrome (D Profile).lnk"

    # Create shortcut in user Start Menu
    $startMenu = [Environment]::GetFolderPath("StartMenu")
    $programs = Join-Path $startMenu "Programs"
    Ensure-Dir $programs
    $startLnk = Join-Path $programs "Google Chrome (D Profile).lnk"

    $wsh = New-Object -ComObject WScript.Shell

    foreach ($lnk in @($desktopLnk, $startLnk)) {
      Write-Log -Level Info -Message "Creating shortcut: $lnk"
      $sc = $wsh.CreateShortcut($lnk)
      $sc.TargetPath = $chromeExe
      $sc.Arguments = $args
      $sc.WorkingDirectory = Split-Path -Path $chromeExe -Parent
      $sc.IconLocation = "$chromeExe,0"
      $sc.Save()
    }

    Write-Log -Level Info -Message "Shortcuts created. Use 'Google Chrome (D Profile)' going forward to keep data/caches off C:."
  }

  Write-Log -Level Info -Message "Completed action: $ActionName"
}
catch {
  $rc = 1
  $status = "failed"
  Write-Log -Level Error -Message ("Action failed: {0}" -f $_.Exception.Message)
}

$finishedAt = (Get-Date).ToString("o")

# Write state-file
$state = @{
  action      = $ActionName
  status      = $status
  rc          = $rc
  started_at  = $startedAt
  finished_at = $finishedAt
  user        = $user
  host        = $hostName
  log_path    = $LogFile
  version     = $Version
}
Write-State -Path $StateFile -Data $state

if ($status -ne "success") { exit $rc }
exit 0
