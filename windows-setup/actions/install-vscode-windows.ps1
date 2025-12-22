<# 
Prerequisites
- Windows 11
- PowerShell 5.1+ (PowerShell 7+ OK)
- Internet access
- You should run from a normal user PowerShell (NOT Admin)

Usage
- Help:
  powershell -File .\install-vscode-windows.ps1 -Help

- Install / Ensure:
  powershell -File .\install-vscode-windows.ps1

What it does (idempotent)
- Installs VS Code (User Setup) if missing
- Optionally creates a “pinned dirs” launcher wrapper:
  - User data: D:\dev\envs\vscode
  - Extensions: D:\dev\envs\vscode\extensions
- Writes logs to: D:\aryan-setup\logs\install-vscode-windows.log
- Writes state to: D:\aryan-setup\state\install-vscode-windows.state.json
#>

[CmdletBinding()]
param(
  [switch]$Help,
  [switch]$CreatePinnedLauncher = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-ISTTimestamp {
  $tz = [TimeZoneInfo]::FindSystemTimeZoneById("India Standard Time")
  $nowIst = [TimeZoneInfo]::ConvertTime([DateTime]::Now, $tz)
  return "IST " + $nowIst.ToString("dd-MM-yyyy HH:mm:ss")
}

function Write-Log {
  param(
    [ValidateSet("Error","Warning","Info","Debug")] [string]$Level,
    [Parameter(Mandatory=$true)] [string]$Message
  )
  $line = "$(Get-ISTTimestamp) $Level $Message"
  Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
  Write-Host $line
}

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Save-State([hashtable]$State) {
  $json = $State | ConvertTo-Json -Depth 6
  Set-Content -Path $script:StateFile -Value $json -Encoding UTF8
}

function Show-Help {
@"
install-vscode-windows.ps1

Ensures VS Code is installed in USER scope and (optionally) creates a pinned-dirs launcher.

Flags:
  -Help                 Show help
  -CreatePinnedLauncher Create C:\Tools\aryan-setup\bin\code-aryan.cmd (default: true)

Outputs:
  Logs : D:\aryan-setup\logs\install-vscode-windows.log
  State: D:\aryan-setup\state\install-vscode-windows.state.json
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }

# Paths
$LogRoot   = "D:\aryan-setup\logs"
$StateRoot = "D:\aryan-setup\state"
Ensure-Dir $LogRoot
Ensure-Dir $StateRoot

$script:LogFile   = Join-Path $LogRoot "install-vscode-windows.log"
$script:StateFile = Join-Path $StateRoot "install-vscode-windows.state.json"

Write-Log -Level Info -Message "=== START install-vscode-windows ==="

# Detect VS Code (user install path)
$codeExeCandidates = @(
  "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
  "$env:ProgramFiles\Microsoft VS Code\Code.exe",
  "$env:ProgramFiles(x86)\Microsoft VS Code\Code.exe"
)

$codeExe = $codeExeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $codeExe) {
  Write-Log -Level Info -Message "VS Code not detected. Installing User Setup..."
  
  $tmp = Join-Path $env:TEMP "vscode-user-setup.exe"
  $url = "https://update.code.visualstudio.com/latest/win32-x64-user/stable"

  Write-Log -Level Info -Message "Downloading VS Code installer -> $tmp"
  Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing

  # Inno Setup silent params (common/compatible):
  # /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /MERGETASKS=!runcode
  $args = @("/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/MERGETASKS=!runcode,addtopath")
  Write-Log -Level Info -Message "Running installer silently..."
  $p = Start-Process -FilePath $tmp -ArgumentList $args -Wait -PassThru
  Write-Log -Level Info -Message "Installer exit code: $($p.ExitCode)"

  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

  # Re-detect
  $codeExe = $codeExeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

if (-not $codeExe) {
  Write-Log -Level Error -Message "VS Code still not found after install attempt."
  Save-State @{ status="error"; step="detect_vscode"; at=(Get-ISTTimestamp) }
  exit 1
}

Write-Log -Level Info -Message "VS Code detected at: $codeExe"

# Optional pinned launcher
if ($CreatePinnedLauncher) {
  $binDir = "C:\Tools\aryan-setup\bin"
  Ensure-Dir $binDir

  $vscodeUserData = "D:\dev\envs\vscode"
  $vscodeExtDir   = "D:\dev\envs\vscode\extensions"
  Ensure-Dir $vscodeUserData
  Ensure-Dir $vscodeExtDir

  $cmdPath = Join-Path $binDir "code-aryan.cmd"
  $cmd = @"
@echo off
setlocal
REM VS Code launcher with pinned dirs (no %USERPROFILE% bloat)
"$codeExe" --user-data-dir="$vscodeUserData" --extensions-dir="$vscodeExtDir" %*
endlocal
"@
  Set-Content -Path $cmdPath -Value $cmd -Encoding ASCII
  Write-Log -Level Info -Message "Created pinned launcher: $cmdPath"
}

Save-State @{
  status="ok"
  vscode_path=$codeExe
  pinned_launcher_created=[bool]$CreatePinnedLauncher
  at=(Get-ISTTimestamp)
}

Write-Log -Level Info -Message "=== DONE install-vscode-windows ==="
exit 0
