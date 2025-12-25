@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ==============================================================================
rem new-node-project.bat  (Windows CMD)
rem
rem Minimal Node scaffold generator.
rem
rem Creates:
rem   <project>\.gitignore
rem   <project>\package.json
rem   <project>\README.md
rem   <project>\project_config.yaml
rem   <project>\src\index.js
rem   <project>\scripts\dev.cmd
rem   <project>\scripts\run.cmd
rem
rem Defaults:
rem   Projects root: D:\dev\projects
rem
rem Flags:
rem   --ai / --tf are documentation-only notes (README + project_config.yaml).
rem
rem Overwrite:
rem   - If project dir exists and is non-empty -> refuse unless --force
rem
rem Usage:
rem   new-node-project --name <project> [--projects-root <dir>] [--ai] [--tf] [--force]
rem   new-node-project --help
rem ==============================================================================

set "NAME="
set "PROJECTS_ROOT=D:\dev\projects"
set "AI=0"
set "TF=0"
set "FORCE=0"

call :log INFO "Starting new-node-project"

rem ---------------------------
rem Parse args
rem ---------------------------
:parse
if "%~1"=="" goto :parsed

if /I "%~1"=="--help" goto :help
if /I "%~1"=="-h" goto :help

if /I "%~1"=="--name" (
  if "%~2"=="" call :die "ERROR: --name requires a value"
  set "NAME=%~2"
  shift
  shift
  goto :parse
)

if /I "%~1"=="--projects-root" (
  if "%~2"=="" call :die "ERROR: --projects-root requires a value"
  set "PROJECTS_ROOT=%~2"
  shift
  shift
  goto :parse
)

if /I "%~1"=="--ai" (
  set "AI=1"
  shift
  goto :parse
)

if /I "%~1"=="--tf" (
  set "TF=1"
  shift
  goto :parse
)

if /I "%~1"=="--force" (
  set "FORCE=1"
  shift
  goto :parse
)

call :die "ERROR: Unknown argument: %~1 (use --help)"

:parsed
if "%NAME%"=="" call :die "ERROR: --name is required (use --help)"

rem ---------------------------
rem Validate project name
rem Only: letters/digits/dot/underscore/hyphen
rem ---------------------------
echo(%NAME%| findstr /R /X /C:"[A-Za-z0-9._-][A-Za-z0-9._-]*" >nul
if errorlevel 1 (
  call :die "ERROR: Invalid --name ""%NAME%"" (allowed: letters, digits, dot, underscore, hyphen)"
)

set "PROJECT_DIR=%PROJECTS_ROOT%\%NAME%"

call :log INFO "Name          = %NAME%"
call :log INFO "Projects root  = %PROJECTS_ROOT%"
call :log INFO "Project dir    = %PROJECT_DIR%"
call :log INFO "Flags          = ai=%AI% tf=%TF% force=%FORCE%"

rem ---------------------------
rem Ensure projects root exists
rem ---------------------------
if not exist "%PROJECTS_ROOT%\" (
  call :log INFO "Creating projects root: %PROJECTS_ROOT%"
  mkdir "%PROJECTS_ROOT%" >nul 2>&1
  if errorlevel 1 call :die "ERROR: Failed to create projects root: %PROJECTS_ROOT%"
)

rem ---------------------------
rem Handle existing project dir
rem ---------------------------
if exist "%PROJECT_DIR%\" (
  call :dir_nonempty "%PROJECT_DIR%"
  if "%NONEMPTY%"=="1" (
    if "%FORCE%"=="1" (
      call :log WARN "Project dir exists and is non-empty; --force set, will overwrite generated files."
    ) else (
      call :die "ERROR: Project dir exists and is non-empty. Use --force to overwrite files."
    )
  ) else (
    call :log INFO "Project dir exists but is empty; continuing."
  )
) else (
  call :log INFO "Creating project dir: %PROJECT_DIR%"
  mkdir "%PROJECT_DIR%" >nul 2>&1
  if errorlevel 1 call :die "ERROR: Failed to create project dir: %PROJECT_DIR%"
)

rem ---------------------------
rem Create subdirs
rem ---------------------------
call :ensure_dir "%PROJECT_DIR%\src"
call :ensure_dir "%PROJECT_DIR%\scripts"

rem ---------------------------
rem Write .gitignore
rem ---------------------------
call :log INFO "Writing .gitignore"
> "%PROJECT_DIR%\.gitignore" (
  echo node_modules/
  echo dist/
  echo build/
  echo .env
  echo .DS_Store
  echo pnpm-lock.yaml
  echo package-lock.json
  echo yarn.lock
  echo .pnpm-store/
  echo npm-debug.log*
  echo yarn-debug.log*
)
if errorlevel 1 call :die "ERROR: Failed writing .gitignore"

rem ---------------------------
rem Write package.json
rem IMPORTANT: escape parentheses inside echo strings within (...) block
rem ---------------------------
call :log INFO "Writing package.json"
> "%PROJECT_DIR%\package.json" (
  echo {
  echo   ^"name^": ^"%NAME%^",
  echo   ^"version^": ^"0.1.0^",
  echo   ^"private^": true,
  echo   ^"type^": ^"module^",
  echo   ^"scripts^": {
  echo     ^"start^": ^"node src/index.js^",
  echo     ^"dev^": ^"node --watch src/index.js^",
  echo     ^"lint^": ^"echo ^(add eslint later if needed^)^",
  echo     ^"test^": ^"echo ^(add tests later^)^"
  echo   }
  echo }
)
if errorlevel 1 call :die "ERROR: Failed writing package.json"

rem ---------------------------
rem Write src/index.js
rem ---------------------------
call :log INFO "Writing src\index.js"
> "%PROJECT_DIR%\src\index.js" (
  echo console.log("Hello from %NAME%!");
  echo console.log("Node:", process.version);
)
if errorlevel 1 call :die "ERROR: Failed writing src\index.js"

rem ---------------------------
rem Write scripts/dev.cmd
rem ---------------------------
call :log INFO "Writing scripts\dev.cmd"
> "%PROJECT_DIR%\scripts\dev.cmd" (
  echo @echo off
  echo setlocal EnableExtensions
  echo cd /d "%%~dp0\.."
  echo echo [INFO] Starting dev ^(node --watch^)...
  echo node --watch src\index.js
  echo exit /b %%errorlevel%%
)
if errorlevel 1 call :die "ERROR: Failed writing scripts\dev.cmd"

rem ---------------------------
rem Write scripts/run.cmd
rem ---------------------------
call :log INFO "Writing scripts\run.cmd"
> "%PROJECT_DIR%\scripts\run.cmd" (
  echo @echo off
  echo setlocal EnableExtensions
  echo cd /d "%%~dp0\.."
  echo node src\index.js
  echo exit /b %%errorlevel%%
)
if errorlevel 1 call :die "ERROR: Failed writing scripts\run.cmd"

rem ---------------------------
rem Write project_config.yaml
rem ---------------------------
call :log INFO "Writing project_config.yaml"
> "%PROJECT_DIR%\project_config.yaml" (
  echo project:
  echo   name: "%NAME%"
  echo   type: "node"
  echo   template_version: "1.0.0"
  echo flags:
  if "%AI%"=="1" (echo   ai_ml: true) else (echo   ai_ml: false)
  if "%TF%"=="1" (echo   tensorflow: true) else (echo   tensorflow: false)
  echo paths:
  echo   projects_root: "%PROJECTS_ROOT%"
)
if errorlevel 1 call :die "ERROR: Failed writing project_config.yaml"

rem ---------------------------
rem Write README.md
rem ---------------------------
call :log INFO "Writing README.md"
> "%PROJECT_DIR%\README.md" (
  echo # %NAME%
  echo.
  echo Minimal Node.js project generated by `new-node-project.bat`.
  echo.
  echo ## Quick start ^(CMD^)
  echo ```bat
  echo cd /d "%PROJECT_DIR%"
  echo node src\index.js
  echo ```
  echo.
  echo ## Scripts
  echo ```bat
  echo scripts\dev.cmd
  echo scripts\run.cmd
  echo ```
  echo.
  echo ## Flags
  if "%AI%"=="1" (echo - AI/ML: enabled) else (echo - AI/ML: disabled)
  if "%TF%"=="1" (echo - TensorFlow: enabled) else (echo - TensorFlow: disabled)
  echo.
  if "%AI%"=="1" (
    echo ## AI/ML notes ^(comments / suggestions^)
    echo - Prefer calling a Python inference service ^(FastAPI^) from Node for GPU TensorFlow.
    echo - Use ONNX Runtime after exporting models to ONNX.
    echo - Use tfjs for lightweight browser inference if you truly need JS runtime.
    echo.
  )
  if "%TF%"=="1" (
    echo ## TensorFlow in Node ^(recommended alternatives^)
    echo 1^) TensorFlow in Python ^(service^) + Node calls it over HTTP.
    echo 2^) Export to ONNX and use ONNX Runtime in Node.
    echo 3^) Use tfjs for browser-side inference.
    echo.
  )
)
if errorlevel 1 call :die "ERROR: Failed writing README.md"

call :log INFO "SUCCESS: Node project created at: %PROJECT_DIR%"
exit /b 0

rem ==============================================================================
rem Helpers
rem ==============================================================================

:help
echo.
echo new-node-project
echo.
echo Usage:
echo   new-node-project --name ^<project^> [--projects-root ^<dir^>] [--ai] [--tf] [--force]
echo.
exit /b 0

:ensure_dir
if not exist "%~1\" (
  mkdir "%~1" >nul 2>&1
  if errorlevel 1 call :die "ERROR: Failed to create directory: %~1"
)
exit /b 0

:dir_nonempty
set "NONEMPTY=0"
for /f "delims=" %%G in ('dir /b "%~1" 2^>nul') do (
  set "NONEMPTY=1"
  goto :done_nonempty
)
:done_nonempty
exit /b 0

:log
rem %1=LEVEL, %2=MSG
echo [%~1] %~2
exit /b 0

:die
echo [%~1]
exit /b 1
