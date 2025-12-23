#requires -Version 5.1
<#
Creates a new Java project scaffold aligned with the Aryan workstation toolchain.

Toolchain expectations:
- JDK installed and on PATH (javac, java, jar).
  (Recommended: setup-aryan install-java-windows)

This scaffold is "plain JDK" (no Maven/Gradle required) to avoid external tool assumptions.
You can add Maven/Gradle later.

Layout:
D:\dev\projects\<Name>\
  src\Main.java
  out\ (build output)
  scripts\build.ps1
  scripts\run.ps1
  README.md

Usage:
  setup-aryan new-java-project-windows -Name myjava
  setup-aryan new-java-project-windows -Name myjava -Force

State (NO JSON):
  D:\aryan-setup\state-files\new-java-project-windows.state
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

$ActionName = "new-java-project-windows"
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
  if (-not (Get-Command javac -ErrorAction SilentlyContinue)) { throw "javac not found. Run: setup-aryan install-java-windows" }
  if (-not (Get-Command java  -ErrorAction SilentlyContinue)) { throw "java not found. Run: setup-aryan install-java-windows" }
  if (-not (Get-Command jar   -ErrorAction SilentlyContinue)) { throw "jar not found. Run: setup-aryan install-java-windows" }
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
  Ensure-Dir (Join-Path $ProjectDir "out")

  $mainJava = @"
public class Main {
    public static void main(String[] args) {
        System.out.println("Hello from $Name!");
        System.out.println("Java: " + System.getProperty("java.version"));
    }
}
"@
  Write-Text -Path (Join-Path $ProjectDir "src\Main.java") -Content $mainJava

  $buildPs = @"
#requires -Version 5.1
`$ErrorActionPreference = "Stop"

`$ProjectDir = `"$ProjectDir`"
`$SrcDir = Join-Path `$ProjectDir "src"
`$OutDir = Join-Path `$ProjectDir "out"

if (-not (Test-Path -LiteralPath `$OutDir)) { New-Item -ItemType Directory -Path `$OutDir -Force | Out-Null }

Write-Host "Compiling..."
javac -d `$OutDir (Join-Path `$SrcDir "Main.java")

Write-Host "Build output -> `$OutDir"
"@
  Write-Text -Path (Join-Path $ProjectDir "scripts\build.ps1") -Content $buildPs

  $runPs = @"
#requires -Version 5.1
`$ErrorActionPreference = "Stop"

`$ProjectDir = `"$ProjectDir`"
`$OutDir = Join-Path `$ProjectDir "out"

if (-not (Test-Path -LiteralPath (Join-Path `$OutDir "Main.class"))) {
  Write-Host "No build found, running build first..."
  & (Join-Path `"$ProjectDir`" "scripts\build.ps1")
}

Write-Host "Running..."
java -cp `$OutDir Main
"@
  Write-Text -Path (Join-Path $ProjectDir "scripts\run.ps1") -Content $runPs

  $readme = @"
# $Name

Minimal Java scaffold created by \`new-java-project-windows.ps1\`.

## Requirements
- JDK on PATH (javac/java/jar) — recommended: \`setup-aryan install-java-windows\`

## Quick start (PowerShell)
Build:
```powershell
.\scripts\build.ps1
"@
Write-Text -Path (Join-Path $ProjectDir "README.md") -Content $readme

Write-Log Info "Java project created: $ProjectDir"
} catch {
$rc = 1
$status = "failed"
Write-Log Error $_.Exception.Message
}

$finishedAt = Get-ISO8601
try { Write-State $status $rc $startedAt $finishedAt $ProjectDir } catch {}
exit $rc