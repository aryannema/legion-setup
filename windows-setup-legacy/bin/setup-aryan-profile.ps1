# setup-aryan Managed Profile Hook
# Enforce D: Drive Authority for Toolchains

# 1. Conda Initialization (D:)
if (Test-Path "D:\dev\tools\miniconda3\Scripts\conda.exe") {
    (& "D:\dev\tools\miniconda3\Scripts\conda.exe" "shell.powershell" "hook") | Out-String | Invoke-Expression
}

# 2. uv Binary Path (D:)
if (Test-Path "D:\dev\tools\uv") {
    $env:Path = "D:\dev\tools\uv;" + $env:Path
}

# 3. Node/pnpm Path (D:)
if (Test-Path "D:\dev\tools\pnpm") {
    $env:Path = "D:\dev\tools\pnpm;" + $env:Path
}