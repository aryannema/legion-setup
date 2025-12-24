@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem new-node-project.bat
rem - Creates a minimal Node.js scaffold (no framework/templates)
rem - Does NOT recommend create-vite/next/etc. User decides.
rem - Flags:
rem     --ai : adds README notes for AI patterns (service/onnx/tfjs)
rem     --tf : adds README notes recommending TF via Python service or ONNX
rem - Safety:
rem     refuses to overwrite a non-empty project dir unless --force
rem
rem Usage:
rem   new-node-project.bat --name myapp
rem   new-node-project.bat --name myapp --ai
rem   new-node-project.bat --name myapp --tf
rem   new-node-project.bat --name myapp --ai --tf
rem ============================================================

set "NAME="
set "PROJECTS_ROOT=D:\dev\projects"
set "AI=0"
set "TF=0"
set "FORCE=0"

:parse
if "%~1"=="" goto :parsed
if /I "%~1"=="--help" goto :help
if /I "%~1"=="-h" goto :help

if /I "%~1"=="--name" (
  set "NAME=%~2"
  shift /1
  shift /1
  goto :parse
)

if /I "%~1"=="--projects-root" (
  set "PROJECTS_ROOT=%~2"
  shift /1
  shift /1
  goto :parse
)

if /I "%~1"=="--ai" (
  set "AI=1"
  shift /1
  goto :parse
)

if /I "%~1"=="--tf" (
  set "TF=1"
  shift /1
  goto :parse
)

if /I "%~1"=="--force" (
  set "FORCE=1"
  shift /1
  goto :parse
)

echo [ERR] Unknown argument: %~1
echo Use --help
exit /b 2

:parsed
if "%NAME%"=="" (
  echo [ERR] --name is required
  exit /b 2
)

echo %NAME%| findstr /R /C:"^[A-Za-z0-9][A-Za-z0-9_-]*$" >nul
if errorlevel 1 (
  echo [ERR] Invalid name "%NAME%".
  exit /b 2
)

if not exist "D:\" (
  echo [ERR] D:\ drive not found.
  exit /b 1
)

set "PROJECT_DIR=%PROJECTS_ROOT%\%NAME%"

call :ensure_dir "%PROJECTS_ROOT%"

if exist "%PROJECT_DIR%\" (
  call :dir_nonempty "%PROJECT_DIR%"
  if "!NONEMPTY!"=="1" if not "%FORCE%"=="1" (
    echo [ERR] Project directory exists and is not empty:
    echo       %PROJECT_DIR%
    echo       Re-run with --force to overwrite scaffold files.
    exit /b 3
  )
) else (
  call :ensure_dir "%PROJECT_DIR%"
)

call :ensure_dir "%PROJECT_DIR%\src"
call :ensure_dir "%PROJECT_DIR%\scripts"

where node >nul 2>nul || echo [WARN] node not found on PATH (scripts will fail until Node is installed)
where npm  >nul 2>nul || echo [WARN] npm not found on PATH
where pnpm >nul 2>nul || echo [INFO] pnpm not on PATH (OK). This scaffold does not enforce package manager.

> "%PROJECT_DIR%\package.json" (
  echo {
  echo   ^"name^": ^"%NAME%^",
  echo   ^"version^": ^"0.1.0^",
  echo   ^"private^": true,
  echo   ^"type^": ^"module^",
  echo   ^"scripts^": {
  echo     ^"start^": ^"node src/index.js^",
  echo     ^"dev^": ^"node --watch src/index.js^",
  echo     ^"lint^": ^"echo (add eslint later if needed)^",
  echo     ^"test^": ^"echo (add tests later)^"
  echo   }
  echo }
)

> "%PROJECT_DIR%\src\index.js" (
  echo console.log("Hello from %NAME%!");
  echo console.log("Node:", process.version);
)

> "%PROJECT_DIR%\scripts\dev.cmd" (
  echo @echo off
  echo setlocal EnableExtensions
  echo cd /d ^"%PROJECT_DIR%^" ^|^| exit /b 1
  echo where node ^>nul 2^>nul ^|^| ^(echo [ERR] node not found on PATH ^& exit /b 1^)
  echo echo [INFO] Starting dev (node --watch)...
  echo node --watch src\index.js
)

> "%PROJECT_DIR%\scripts\run.cmd" (
  echo @echo off
  echo setlocal EnableExtensions
  echo cd /d ^"%PROJECT_DIR%^" ^|^| exit /b 1
  echo where node ^>nul 2^>nul ^|^| ^(echo [ERR] node not found on PATH ^& exit /b 1^)
  echo node src\index.js
)

> "%PROJECT_DIR%\project_config.yaml" (
  echo name: %NAME%
  echo language: node
  echo paths:
  echo   project_root: %PROJECT_DIR%
  echo flags:
  if "%AI%"=="1" (echo   ai_ml: true) else (echo   ai_ml: false)
  if "%TF%"=="1" (echo   tensorflow: true) else (echo   tensorflow: false)
  echo toolchain:
  echo   node: true
  echo   package_manager: user-choice
)

> "%PROJECT_DIR%\.gitignore" (
  echo node_modules/
  echo .pnpm-store/
  echo npm-debug.log*
  echo yarn-debug.log*
  echo yarn-error.log*
  echo .env
  echo .vscode/
  echo .idea/
  echo dist/
  echo build/
)

> "%PROJECT_DIR%\README.md" (
  echo # %NAME%
  echo.
  echo Minimal Node.js scaffold created by `new-node-project.bat`.
  echo This intentionally avoids framework templates. Add your stack manually.
  echo.
  echo ## Quick start ^(CMD^)
  echo Run in watch mode:
  echo ```bat
  echo scripts\dev.cmd
  echo ```
  echo Run once:
  echo ```bat
  echo scripts\run.cmd
  echo ```
  echo.
  echo ## Flags
  if "%AI%"=="1" (echo - AI/ML: enabled) else (echo - AI/ML: disabled)
  if "%TF%"=="1" (echo - TensorFlow: enabled) else (echo - TensorFlow: disabled)
  echo.
  if "%AI%"=="1" (
    echo ## AI/ML notes (comments / suggestions)
    echo - For Node, common approaches:
    echo   - Call a Python inference service (FastAPI) from Node for GPU TensorFlow.
    echo   - Use ONNX Runtime (node binding) after exporting models to ONNX.
    echo   - Use tfjs (CPU) or tfjs-node (native) depending on your packaging needs.
    echo - Keep model logic behind a small adapter module so you can swap implementations.
    echo.
  )
  if "%TF%"=="1" (
    echo ## TensorFlow in Node (recommended alternatives)
    echo - If you specifically need TensorFlow GPU, the most reliable path is:
    echo   1^) TensorFlow in Python (service) + Node calls it over HTTP.
    echo   2^) Export model to ONNX + run in Node via ONNX Runtime.
    echo.
    echo ## UI on iGPU, compute on dGPU (Windows practical approach)
    echo - If you build an Electron UI:
    echo   - Set Electron app to **Power saving** (iGPU) in Windows Graphics settings.
    echo   - Keep the Python TF service process as **High performance** (dGPU) if needed.
    echo.
    echo ## TODO comment
    echo - If desktop/GUI shows up in GPU tools, it can be normal.
    echo - Enforce per-app graphics preferences for iGPU-first GUI behavior.
  )
)

echo [OK] Node project created:
echo   %PROJECT_DIR%
exit /b 0

:help
echo new-node-project.bat
echo.
echo Usage:
echo   new-node-project.bat --name NAME [--projects-root PATH] [--ai] [--tf] [--force]
exit /b 0

:ensure_dir
if exist "%~1\" exit /b 0
mkdir "%~1" >nul 2>nul
if exist "%~1\" (
  exit /b 0
) else (
  echo [ERR] Failed to create directory: %~1
  exit /b 1
)

:dir_nonempty
set "NONEMPTY=0"
for /f "delims=" %%G in ('dir /b /a "%~1" 2^>nul') do (
  set "NONEMPTY=1"
  goto :dir_nonempty_done
)
:dir_nonempty_done
exit /b 0
