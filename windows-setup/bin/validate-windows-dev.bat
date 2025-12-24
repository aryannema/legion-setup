@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem validate-windows-dev.bat
rem - One-shot Windows dev audit (CMD/BAT only)
rem - Validates:
rem     1) Dev directories under %DEVROOT%
rem     2) Environment variables (prints + checks directory targets)
rem     3) Tool presence on PATH
rem     4) Tool versions
rem     5) Cache directory sanity
rem
rem Usage:
rem   validate-windows-dev.bat
rem   validate-windows-dev.bat --devroot D:\dev
rem   validate-windows-dev.bat -h | --help
rem
rem Notes:
rem - Read-only validation: does NOT modify anything.
rem - No PowerShell. No state. No idempotency contract.
rem ============================================================

if /I "%~1"=="-h" goto :help
if /I "%~1"=="--help" goto :help

set "DEVROOT=D:\dev"
if /I "%~1"=="--devroot" (
  if not "%~2"=="" set "DEVROOT=%~2"
)

if "%DEVROOT:~-1%"=="\" set "DEVROOT=%DEVROOT:~0,-1%"

set "TOOLS=%DEVROOT%\tools"
set "CACHE=%DEVROOT%\cache"
set "TMPDIR=%DEVROOT%\tmp"

set "FAIL_DIRS=0"
set "FAIL_ENV=0"
set "FAIL_TOOLS=0"

echo ============================================================
echo [validate-windows-dev] Windows dev audit
echo DEVROOT:
echo   %DEVROOT%
echo ============================================================
echo.

rem ------------------------------------------------------------
rem 1) Directory checks
rem ------------------------------------------------------------
echo ------------------------------------------------------------
echo [1/5] Directory layout checks
echo ------------------------------------------------------------

call :chkdir "%DEVROOT%"
call :chkdir "%DEVROOT%\repos"
call :chkdir "%TMPDIR%"

call :chkdir "%TOOLS%"
call :chkdir "%TOOLS%\bin"
call :chkdir "%TOOLS%\java"
call :chkdir "%TOOLS%\node"
call :chkdir "%TOOLS%\python"
call :chkdir "%TOOLS%\miniconda3"
call :chkdir "%TOOLS%\nvm"
call :chkdir "%TOOLS%\nodejs"
call :chkdir "%TOOLS%\pnpm"

call :chkdir "%CACHE%"
call :chkdir "%CACHE%\conda"
call :chkdir "%CACHE%\conda\pkgs"
call :chkdir "%CACHE%\conda\envs"
call :chkdir "%CACHE%\pip"
call :chkdir "%CACHE%\uv"
call :chkdir "%CACHE%\npm"
call :chkdir "%CACHE%\pnpm"
call :chkdir "%CACHE%\gradle"
call :chkdir "%CACHE%\maven"
call :chkdir "%CACHE%\ivy"

echo.
if "%FAIL_DIRS%"=="0" (
  echo [PASS] Directory layout
) else (
  echo [FAIL] Directory layout (missing folders)
)

echo.

rem ------------------------------------------------------------
rem 2) Environment variables (print + directory checks)
rem ------------------------------------------------------------
echo ------------------------------------------------------------
echo [2/5] Environment variables (print + validate targets)
echo ------------------------------------------------------------

rem Core tool roots
call :env_print "CONDA_ROOT"
call :env_print "JAVA_HOME"
call :env_print "NVM_HOME"
call :env_print "NVM_SYMLINK"
call :env_print "PNPM_HOME"

rem Caches
call :env_print "CONDA_PKGS_DIRS"
call :env_print "CONDA_ENVS_PATH"
call :env_print "UV_CACHE_DIR"
call :env_print "UV_INSTALL_DIR"
call :env_print "PIP_CACHE_DIR"
call :env_print "NPM_CONFIG_CACHE"
call :env_print "GRADLE_USER_HOME"
call :env_print "MAVEN_USER_HOME"
call :env_print "IVY_USER_DIR"

rem TEMP/TMP (optional)
call :env_print "TEMP"
call :env_print "TMP"

echo.
echo ---- Env var target checks (if set, directory must exist) ----
call :env_dircheck "CONDA_ROOT"
call :env_dircheck "JAVA_HOME"
call :env_dircheck "NVM_HOME"
call :env_dircheck "NVM_SYMLINK"
call :env_dircheck "PNPM_HOME"

call :env_dircheck "CONDA_PKGS_DIRS"
call :env_dircheck "CONDA_ENVS_PATH"
call :env_dircheck "UV_CACHE_DIR"
call :env_dircheck "UV_INSTALL_DIR"
call :env_dircheck "PIP_CACHE_DIR"
call :env_dircheck "NPM_CONFIG_CACHE"
call :env_dircheck "GRADLE_USER_HOME"
call :env_dircheck "MAVEN_USER_HOME"
call :env_dircheck "IVY_USER_DIR"

call :env_dircheck "TEMP"
call :env_dircheck "TMP"

echo.
if "%FAIL_ENV%"=="0" (
  echo [PASS] Environment variables (no invalid directory targets)
) else (
  echo [FAIL] Environment variables (one or more set vars point to missing dirs)
)

echo.

rem ------------------------------------------------------------
rem 3) Tool presence on PATH (where ...)
rem ------------------------------------------------------------
echo ------------------------------------------------------------
echo [3/5] Tool presence on PATH (where ...)
echo ------------------------------------------------------------

call :wherechk "conda"  required
call :wherechk "python" required
call :wherechk "pip"    required

call :wherechk "uv"     recommended

call :wherechk "node"   recommended
call :wherechk "npm"    recommended
call :wherechk "pnpm"   recommended
call :wherechk "nvm"    optional

call :wherechk "java"   required
call :wherechk "javac"  required

call :wherechk "code"   recommended

echo.
if "%FAIL_TOOLS%"=="0" (
  echo [PASS] Required tools present on PATH
) else (
  echo [FAIL] Required tools missing on PATH
)
echo.

rem ------------------------------------------------------------
rem 4) Tool versions (safe)
rem ------------------------------------------------------------
echo ------------------------------------------------------------
echo [4/5] Tool versions
echo ------------------------------------------------------------

call :ver "conda"  "conda --version"
call :ver "python" "python --version"
call :ver "pip"    "pip --version"

call :ver "uv"     "uv --version"

call :ver "node"   "node --version"
call :ver "npm"    "npm --version"
call :ver "pnpm"   "pnpm --version"
call :ver "nvm"    "nvm version"

call :ver "java"   "java -version"
call :ver "javac"  "javac -version"

call :ver "code"   "code --version"

echo.

rem ------------------------------------------------------------
rem 5) Cache sanity checks (recommended defaults)
rem ------------------------------------------------------------
echo ------------------------------------------------------------
echo [5/5] Cache sanity checks (recommended defaults under DEVROOT)
echo ------------------------------------------------------------

call :chkdir "%CACHE%\conda\pkgs"
call :chkdir "%CACHE%\conda\envs"
call :chkdir "%CACHE%\pip"
call :chkdir "%CACHE%\uv"
call :chkdir "%CACHE%\npm"
call :chkdir "%CACHE%\pnpm"
call :chkdir "%CACHE%\gradle"
call :chkdir "%CACHE%\maven"
call :chkdir "%CACHE%\ivy"

echo.
echo ============================================================
echo Summary
echo ============================================================
if "%FAIL_DIRS%"=="0" (
  echo Directories : PASS
) else (
  echo Directories : FAIL
)
if "%FAIL_ENV%"=="0" (
  echo Env Vars    : PASS
) else (
  echo Env Vars    : FAIL
)
if "%FAIL_TOOLS%"=="0" (
  echo Tools PATH  : PASS
) else (
  echo Tools PATH  : FAIL
)

echo.
if "%FAIL_DIRS%"=="0" if "%FAIL_ENV%"=="0" if "%FAIL_TOOLS%"=="0" (
  echo [PASS] validate-windows-dev completed successfully.
  exit /b 0
) else (
  echo [FAIL] validate-windows-dev completed with issues.
  exit /b 2
)

rem ============================================================
rem helpers
rem ============================================================

:help
echo validate-windows-dev.bat
echo.
echo One-shot validator for Windows dev setup:
echo - directories, environment vars, PATH tools, versions, caches
echo.
echo Usage:
echo   validate-windows-dev.bat
echo   validate-windows-dev.bat --devroot D:\dev
exit /b 0

:chkdir
set "P=%~1"
if exist "%P%" (
  echo [OK ] "%P%"
) else (
  echo [ERR] missing: "%P%"
  set "FAIL_DIRS=1"
)
exit /b 0

:env_print
set "K=%~1"
for /f "tokens=1,* delims==" %%A in ('set %K% 2^>nul') do (
  if /I "%%A"=="%K%" (
    echo [OK ] %K%=%%B
    goto :env_print_done
  )
)
echo [WARN] %K% is not set
:env_print_done
exit /b 0

:env_dircheck
set "K=%~1"
for /f "tokens=1,* delims==" %%A in ('set %K% 2^>nul') do (
  if /I "%%A"=="%K%" (
    set "VAL=%%B"
    if "!VAL!"=="" (
      echo [WARN] %K% is set but empty
      goto :env_dircheck_done
    )
    if exist "!VAL!" (
      echo [OK ] %K% target exists: "!VAL!"
    ) else (
      echo [ERR] %K% target missing: "!VAL!"
      set "FAIL_ENV=1"
    )
    goto :env_dircheck_done
  )
)
echo [INFO] %K% not set (skip target check)
:env_dircheck_done
exit /b 0

:wherechk
set "B=%~1"
set "MODE=%~2"

where %B% >nul 2>nul
if errorlevel 1 (
  echo [WARN] not found on PATH: %B% (%MODE%)
  if /I "%MODE%"=="required" set "FAIL_TOOLS=1"
) else (
  for /f "usebackq delims=" %%P in (`where %B%`) do (
    echo [OK ] %B%: %%P
  )
)
exit /b 0

:ver
set "NAME=%~1"
set "CMD=%~2"

where %NAME% >nul 2>nul
if errorlevel 1 (
  echo [SKIP] %NAME% not on PATH (version not available)
  exit /b 0
)

echo.
echo ---- %NAME% ----
call %CMD%
exit /b 0
