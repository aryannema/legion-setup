@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem devdirs-create.bat
rem - Creates dev directory layout (safe if exists)
rem - Prints ONLY guidance for installers + environment variables
rem - Does NOT set/modify environment variables
rem
rem Usage:
rem   devdirs-create.bat
rem   devdirs-create.bat --devroot D:\dev
rem   devdirs-create.bat -h | --help
rem ============================================================

if /I "%~1"=="-h"  goto :help
if /I "%~1"=="--help" goto :help

set "DEVROOT=D:\dev"
if /I "%~1"=="--devroot" (
  if not "%~2"=="" set "DEVROOT=%~2"
)

rem Normalize trailing backslash
if "%DEVROOT:~-1%"=="\" set "DEVROOT=%DEVROOT:~0,-1%"

set "TOOLS=%DEVROOT%\tools"
set "CACHE=%DEVROOT%\cache"
set "TMPDIR=%DEVROOT%\tmp"

echo ============================================================
echo [devdirs-create] Creating Windows dev directories under:
echo   %DEVROOT%
echo ============================================================

call :mk "%DEVROOT%"
call :mk "%DEVROOT%\repos"
call :mk "%TMPDIR%"

rem Tools
call :mk "%TOOLS%"
call :mk "%TOOLS%\bin"
call :mk "%TOOLS%\java"
call :mk "%TOOLS%\node"
call :mk "%TOOLS%\python"
call :mk "%TOOLS%\nvm"
call :mk "%TOOLS%\nodejs"
call :mk "%TOOLS%\pnpm"
call :mk "%TOOLS%\miniconda3"

rem Caches (recommended)
call :mk "%CACHE%"
call :mk "%CACHE%\conda"
call :mk "%CACHE%\conda\pkgs"
call :mk "%CACHE%\conda\envs"
call :mk "%CACHE%\pip"
call :mk "%CACHE%\uv"
call :mk "%CACHE%\npm"
call :mk "%CACHE%\pnpm"
call :mk "%CACHE%\gradle"
call :mk "%CACHE%\maven"
call :mk "%CACHE%\ivy"

echo.
echo ============================================================
echo NEXT: Manual installs + manual env var setup (this script
echo prints guidance only; it does not change anything).
echo ============================================================
echo.

call :print_miniconda
call :print_uv
call :print_java
call :print_node
call :print_nvmw
call :print_pnpm
call :print_vscode
call :print_chrome

echo.
echo ============================================================
echo Done.
echo Next run:
echo   devdirs-validate.bat --devroot "%DEVROOT%"
echo ============================================================
exit /b 0

:help
echo devdirs-create.bat
echo.
echo Creates the dev directory layout and prints manual setup instructions.
echo.
echo Usage:
echo   devdirs-create.bat
echo   devdirs-create.bat --devroot D:\dev
echo.
echo This script does NOT change environment variables.
exit /b 0

:mk
set "P=%~1"
if exist "%P%" (
  echo [OK ] exists: "%P%"
) else (
  mkdir "%P%" >nul 2>nul
  if exist "%P%" (
    echo [OK ] created: "%P%"
  ) else (
    echo [ERR] failed to create: "%P%"
  )
)
exit /b 0

:print_miniconda
echo ------------------------------------------------------------
echo 1) Miniconda (manual install)
echo Sources:
echo   https://www.anaconda.com/docs/getting-started/miniconda/main
echo   https://www.anaconda.com/download
echo Install location (user-level tools rule):
echo   CONDA_ROOT=%TOOLS%\miniconda3
echo Notes:
echo   - Choose "Just Me" installer if possible.
echo   - During install, avoid auto-modifying PATH unless you prefer it.
echo Environment variables to SET MANUALLY:
echo   USER level (recommended):
echo     CONDA_ROOT=%TOOLS%\miniconda3
echo     CONDA_PKGS_DIRS=%CACHE%\conda\pkgs
echo     CONDA_ENVS_PATH=%CACHE%\conda\envs
echo     PIP_CACHE_DIR=%CACHE%\pip
echo PATH guidance (manual):
echo   - Add: %%CONDA_ROOT%%\condabin
echo   - Optionally add: %%CONDA_ROOT%%\Scripts and %%CONDA_ROOT%%\Library\bin
echo Verify after setup:
echo   conda --version
echo   conda info
echo ------------------------------------------------------------
echo.
exit /b 0

:print_uv
echo ------------------------------------------------------------
echo 2) uv (manual install)
echo Sources:
echo   https://docs.astral.sh/uv/getting-started/installation/
echo   https://github.com/astral-sh/uv/releases
echo   https://docs.astral.sh/uv/reference/environment/
echo Recommended (no PowerShell required):
echo   - Download the Windows zip from GitHub releases
echo   - Put uv.exe into: %TOOLS%\bin
echo   - Add %TOOLS%\bin to PATH (User-level)
echo Environment variables to SET MANUALLY:
echo   USER level:
echo     UV_CACHE_DIR=%CACHE%\uv
echo     (Optional) UV_INSTALL_DIR=%TOOLS%\bin
echo Verify after setup:
echo   uv --version
echo   uv cache dir
echo ------------------------------------------------------------
echo.
exit /b 0

:print_java
echo ------------------------------------------------------------
echo 3) Java (system-level install recommended)
echo Sources:
echo   https://adoptium.net/temurin/releases
echo   https://projects.eclipse.org/projects/adoptium.temurin/downloads
echo Recommended install location (system-level):
echo   C:\Program Files\Java\jdk-21
echo   (or) C:\Java\jdk-21
echo Environment variables to SET MANUALLY:
echo   SYSTEM level:
echo     JAVA_HOME=C:\Program Files\Java\jdk-21
echo   PATH (SYSTEM or USER):
echo     %%JAVA_HOME%%\bin
echo Optional build caches (manual):
echo   GRADLE_USER_HOME=%CACHE%\gradle
echo   MAVEN_USER_HOME=%CACHE%\maven
echo   (Ivy cache stays under %CACHE%\ivy unless a tool allows redirect)
echo Verify:
echo   java -version
echo   javac -version
echo ------------------------------------------------------------
echo.
exit /b 0

:print_node
echo ------------------------------------------------------------
echo 4) Node.js (direct install OR via nvm-windows)
echo Source (direct Node download):
echo   https://nodejs.org/en/download
echo If installing Node directly (without nvm):
echo   - Install normally, ensure node.exe and npm are on PATH
echo Suggested cache env var (manual):
echo   NPM_CONFIG_CACHE=%CACHE%\npm
echo Verify:
echo   node --version
echo   npm --version
echo ------------------------------------------------------------
echo.
exit /b 0

:print_nvmw
echo ------------------------------------------------------------
echo 5) nvm-windows (recommended for multi-Node)
echo Sources:
echo   https://github.com/coreybutler/nvm-windows
echo   https://github.com/coreybutler/nvm-windows/releases
echo   https://learn.microsoft.com/en-us/windows/dev-environment/javascript/nodejs-on-windows
echo Install locations (match user-level tools rule):
echo   NVM_HOME=%TOOLS%\nvm
echo   NVM_SYMLINK=%TOOLS%\nodejs
echo Notes:
echo   - nvm-windows uses a symlink directory (NVM_SYMLINK) to point to the active Node.
echo   - The installer typically sets NVM_HOME and NVM_SYMLINK.
echo Correct commands (nvm-windows syntax):
echo   nvm version
echo   nvm list
echo   nvm install lts
echo   nvm use lts
echo ------------------------------------------------------------
echo.
exit /b 0

:print_pnpm
echo ------------------------------------------------------------
echo 6) pnpm
echo Sources:
echo   https://pnpm.io/installation
echo   https://pnpm.io/settings
echo Preferred location (user-level tools rule):
echo   PNPM_HOME=%TOOLS%\pnpm
echo Environment variables to SET MANUALLY:
echo   USER level:
echo     PNPM_HOME=%TOOLS%\pnpm
echo   PATH (USER level):
echo     %%PNPM_HOME%%
echo Suggested cache/store (manual):
echo   - Recommended store dir: %CACHE%\pnpm
echo   - After install you can set:
echo       pnpm config set store-dir %CACHE%\pnpm\store
echo Verify:
echo   pnpm --version
echo ------------------------------------------------------------
echo.
exit /b 0

:print_vscode
echo ------------------------------------------------------------
echo 7) Visual Studio Code
echo Source:
echo   https://code.visualstudio.com/download
echo Install notes:
echo   - VS Code is a GUI app; install location may be user installer default.
echo Optional PATH:
echo   - Ensure "code" CLI is available (installer option).
echo Verify:
echo   code --version
echo ------------------------------------------------------------
echo.
exit /b 0

:print_chrome
echo ------------------------------------------------------------
echo 8) Google Chrome
echo Sources:
echo   https://www.google.com/intl/en_in/chrome/
echo   https://support.google.com/chrome/answer/95346
echo Install notes:
echo   - Chrome is a GUI app; standard install is fine.
echo   - Put Chrome profiles under: %DEVROOT%\profiles (per your storage policy)
echo Verify:
echo   - Open Chrome > Settings > About Chrome
echo ------------------------------------------------------------
echo.
exit /b 0
