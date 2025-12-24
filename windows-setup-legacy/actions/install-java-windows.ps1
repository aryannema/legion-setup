[CmdletBinding()]
param([switch]$Force)

$ActionName = "install-java-windows"
$StateFile  = "D:\aryan-setup\state-files\$ActionName.state"

try {
    # 1. Verify Authoritative Binary on C:
    $javaBin = "C:\Program Files\Java\jdk-21\bin\java.exe"
    if (!(Test-Path $javaBin)) { throw "JDK 21 binary not found at $javaBin. Install MSI first." }

    # 2. Set System Authority (JAVA_HOME)
    [Environment]::SetEnvironmentVariable("JAVA_HOME", "C:\Program Files\Java\jdk-21", "Machine")

    # 3. Redirect Build Caches to D:
    $cacheRoot = "D:\dev\cache"
    $vars = @{ "GRADLE_USER_HOME" = "$cacheRoot\.gradle"; "IVY_HOME" = "$cacheRoot\.ivy2" }
    foreach ($v in $vars.Keys) {
        if (!(Test-Path $vars[$v])) { New-Item -ItemType Directory -Path $vars[$v] -Force | Out-Null }
        [Environment]::SetEnvironmentVariable($v, $vars[$v], "User")
    }

    # 4. Write INI State
    Set-Content -Path $StateFile -Value "action=$ActionName`nstatus=success`nrc=0" -Encoding UTF8
    Write-Host "Java Validated: Binary (C:) | Caches (D:)" -ForegroundColor Green
} catch {
    Write-Error $_.Exception.Message; exit 1
}