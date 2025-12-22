<#
Prerequisites
- Windows 11
- PowerShell 5.1+
- Internet access

Usage
  powershell -File .\install-java-windows.ps1 -Help
  powershell -File .\install-java-windows.ps1

What it does (idempotent)
- Downloads latest Temurin JDK 21 (Windows x64, Hotspot) using Adoptium API metadata
- Installs it portably to: D:\dev\tools\jdk\temurin-21\current
- Sets USER JAVA_HOME and adds %JAVA_HOME%\bin to USER PATH (without truncating PATH)
- Logs:  D:\aryan-setup\logs\install-java-windows.log
- State: D:\aryan-setup\state\install-java-windows.state.json
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
  $json = $State | ConvertTo-Json -Depth 8
  Set-Content -Path $script:StateFile -Value $json -Encoding UTF8
}

function Set-UserEnvVar([string]$Name, [string]$Value) {
  [Environment]::SetEnvironmentVariable($Name, $Value, "User")
}

function Add-ToUserPathIfMissing([string]$Dir) {
  $userPath = [Environment]::GetEnvironmentVariable("Path","User")
  $parts = $userPath -split ';' | Where-Object { $_ -and $_.Trim() -ne "" }
  if ($parts -notcontains $Dir) {
    $newPath = ($parts + $Dir) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    return $true
  }
  return $false
}

function Show-Help {
@"
install-java-windows.ps1

Installs Temurin JDK 21 portably to D:\dev\tools\jdk\temurin-21\current.

Outputs:
  Logs : D:\aryan-setup\logs\install-java-windows.log
  State: D:\aryan-setup\state\install-java-windows.state.json
"@ | Write-Host
}

if ($Help) { Show-Help; exit 0 }

$LogRoot   = "D:\aryan-setup\logs"
$StateRoot = "D:\aryan-setup\state"
Ensure-Dir $LogRoot
Ensure-Dir $StateRoot

$script:LogFile   = Join-Path $LogRoot "install-java-windows.log"
$script:StateFile = Join-Path $StateRoot "install-java-windows.state.json"

Write-Log -Level Info -Message "=== START install-java-windows ==="

$DevRoot   = "D:\dev"
$ToolsRoot = Join-Path $DevRoot "tools"
$JdkRoot   = Join-Path $ToolsRoot "jdk\temurin-21"
$Current   = Join-Path $JdkRoot "current"

Ensure-Dir $ToolsRoot
Ensure-Dir $JdkRoot

# If already installed and java works, keep idempotent
$javaExe = Join-Path $Current "bin\java.exe"
if (Test-Path -LiteralPath $javaExe) {
  Write-Log -Level Info -Message "Temurin JDK already present: $javaExe"
} else {
  Write-Log -Level Info -Message "Temurin JDK not detected. Resolving latest JDK 21 (Windows x64) from Adoptium API..."

  # Use assets API (metadata), then pick a ZIP package.
  # Endpoint family is documented via Adoptium API swagger. We keep params explicit.
  $metaUrl = "https://api.adoptium.net/v3/assets/feature_releases/21/ga?architecture=x64&heap_size=normal&image_type=jdk&jvm_impl=hotspot&os=windows&vendor=eclipse"
  $assets = Invoke-RestMethod -Uri $metaUrl

  if (-not $assets) { throw "No assets returned from Adoptium API." }

  # Pick first asset with a zip binary (prefer .zip to stay portable, avoid MSI admin scope issues)
  $chosen = $null
  foreach ($a in $assets) {
    foreach ($b in $a.binaries) {
      if ($b.package -and $b.package.name -and $b.package.name.ToLower().EndsWith(".zip")) {
        $chosen = $b
        break
      }
    }
    if ($chosen) { break }
  }
  if (-not $chosen) {
    throw "Could not find a ZIP JDK package in assets payload."
  }

  $zipUrl  = $chosen.package.link
  $zipName = $chosen.package.name
  $release = $chosen.version_data.semver

  Write-Log -Level Info -Message "Selected: $zipName (release: $release)"
  Write-Log -Level Info -Message "Downloading: $zipUrl"

  $tmpZip = Join-Path $env:TEMP $zipName
  Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing

  # Reset current safely
  if (Test-Path -LiteralPath $Current) {
    Remove-Item -LiteralPath $Current -Recurse -Force
  }
  Ensure-Dir $Current

  # Extract to a temp folder to find the top directory
  $tmpExtract = Join-Path $env:TEMP ("temurin-jdk21-" + [Guid]::NewGuid().ToString("N"))
  Ensure-Dir $tmpExtract

  Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force
  Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue

  # Usually extracts as a single top-level folder (e.g., jdk-21.0.x+...)
  $top = Get-ChildItem -Path $tmpExtract -Directory | Select-Object -First 1
  if (-not $top) { throw "Unexpected ZIP layout (no top-level directory found)." }

  Move-Item -LiteralPath $top.FullName -Destination $Current -Force
  Remove-Item -LiteralPath $tmpExtract -Recurse -Force -ErrorAction SilentlyContinue

  if (-not (Test-Path -LiteralPath $javaExe)) {
    throw "java.exe not found after extraction: $javaExe"
  }

  Write-Log -Level Info -Message "Installed Temurin JDK to: $Current"
}

# Set JAVA_HOME (User) and update PATH (User) to include %JAVA_HOME%\bin
Set-UserEnvVar -Name "JAVA_HOME" -Value $Current
$added = Add-ToUserPathIfMissing (Join-Path $Current "bin")
if ($added) {
  Write-Log -Level Info -Message "Added to USER PATH: $Current\bin (new shells will see it)"
} else {
  Write-Log -Level Debug -Message "USER PATH already contains: $Current\bin"
}

# Sanity
try {
  $out = & $javaExe -version 2>&1
  Write-Log -Level Info -Message "java -version OK"
  Write-Log -Level Debug -Message ($out -join " | ")
} catch {
  Write-Log -Level Warning -Message "java -version failed in this session (may need new shell): $($_.Exception.Message)"
}

Save-State @{
  status="ok"
  jdk_current=$Current
  java_exe=$javaExe
  java_home=$Current
  at=(Get-ISTTimestamp)
}

Write-Log -Level Info -Message "=== DONE install-java-windows ==="
exit 0
