@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem new-python-project.bat
rem - Creates a new Python project scaffold (conda env prefix + uv)
rem - Flags:
rem     --ai  : adds common DS/ML deps
rem     --tf  : adds tensorflow + TF validation script + notes
rem - Safety:
rem     refuses to overwrite a non-empty project dir unless --force
rem
rem Usage:
rem   new-python-project.bat --name myproj
rem   new-python-project.bat --name myproj --ai
rem   new-python-project.bat --name myproj --tf
rem   new-python-project.bat --name myproj --ai --tf
rem   new-python-project.bat --name myproj --projects-root D:\dev\projects --devroot D:\dev
rem   new-python-project.bat --help
rem ============================================================

set "NAME="
set "PROJECTS_ROOT=D:\dev\projects"
set "DEVROOT=D:\dev"
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

if /I "%~1"=="--devroot" (
  set "DEVROOT=%~2"
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
  echo Use --help
  exit /b 2
)

rem basic name validation: starts alnum, then alnum/_/-
echo %NAME%| findstr /R /C:"^[A-Za-z0-9][A-Za-z0-9_-]*$" >nul
if errorlevel 1 (
  echo [ERR] Invalid name "%NAME%". Allowed: letters, numbers, _ and - . Must start with alnum.
  exit /b 2
)

if not exist "D:\" (
  echo [ERR] D:\ drive not found.
  exit /b 1
)

set "PROJECT_DIR=%PROJECTS_ROOT%\%NAME%"
set "ENV_DIR=%DEVROOT%\envs\conda\%NAME%"

call :ensure_dir "%PROJECTS_ROOT%"

rem If exists and non-empty and not force -> refuse
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
call :ensure_dir "%PROJECT_DIR%\.vscode"

rem -----------------------
rem requirements.txt
rem -----------------------
set "REQ_TMP=%TEMP%\req_%RANDOM%.txt"
> "%REQ_TMP%" (
  echo pytest
  echo ruff
  if "%AI%"=="1" (
    echo numpy
    echo pandas
    echo scikit-learn
    echo matplotlib
  )
  if "%TF%"=="1" (
    echo tensorflow
  )
)

rem Write requirements.txt (unique-ish: keep simple; duplicates are harmless but we avoid them)
call :write_unique "%REQ_TMP%" "%PROJECT_DIR%\requirements.txt"
del /q "%REQ_TMP%" >nul 2>nul

rem -----------------------
rem project_config.yaml
rem -----------------------
> "%PROJECT_DIR%\project_config.yaml" (
  echo name: %NAME%
  echo language: python
  echo paths:
  echo   project_root: %PROJECT_DIR%
  echo   conda_env_prefix: %ENV_DIR%
  echo flags:
  if "%AI%"=="1" (echo   ai_ml: true) else (echo   ai_ml: false)
  if "%TF%"=="1" (echo   tensorflow: true) else (echo   tensorflow: false)
  echo toolchain:
  echo   conda: true
  echo   uv: true
)

rem -----------------------
rem .vscode/settings.json
rem -----------------------
> "%PROJECT_DIR%\.vscode\settings.json" (
  echo {
  echo   ^"python.defaultInterpreterPath^": ^"D:\\dev\\envs\\conda\\%NAME%\\python.exe^",
  echo   ^"python.terminal.activateEnvironment^": true,
  echo   ^"python.analysis.typeCheckingMode^": ^"basic^",
  echo   ^"python.analysis.diagnosticSeverityOverrides^": {
  echo     ^"reportMissingImports^": ^"warning^"
  echo   }
  echo }
)

rem -----------------------
rem src/main.py
rem -----------------------
> "%PROJECT_DIR%\src\main.py" (
  echo def main^(^) -^> None:
  echo     print^(^"Hello from %NAME%!^"^)
  echo.
  echo if __name__ == ^"__main__^":
  echo     main^(^)
)

rem -----------------------
rem scripts/dev.cmd (creates env + installs deps via uv)
rem -----------------------
> "%PROJECT_DIR%\scripts\dev.cmd" (
  echo @echo off
  echo setlocal EnableExtensions EnableDelayedExpansion
  echo.
  echo rem Creates ^(if missing^) and activates the conda env, then installs deps using uv.
  echo rem Requirements: conda + uv on PATH.
  echo rem NOTE: For "conda activate" to work in CMD, you may need to run once:
  echo rem   conda init cmd.exe
  echo.
  echo set ^"NAME=%NAME%^"
  echo set ^"PROJECT_DIR=%PROJECT_DIR%^"
  echo set ^"ENV_DIR=%ENV_DIR%^"
  echo.
  echo where conda ^>nul 2^>nul ^|^| ^(echo [ERR] conda not found on PATH ^& exit /b 1^)
  echo where uv ^>nul 2^>nul ^|^| ^(echo [ERR] uv not found on PATH ^& exit /b 1^)
  echo.
  echo if not exist ^"%ENV_DIR%\python.exe^" ^(
  echo   echo [INFO] Creating conda env at: ^"%ENV_DIR%^"
  echo   conda create -y -p ^"%ENV_DIR%^" python=3.11 ^|^| exit /b 1
  echo ^)
  echo.
  echo echo [INFO] Activating env...
  echo call conda activate ^"%ENV_DIR%^" ^|^| exit /b 1
  echo.
  echo echo [INFO] Installing deps with uv pip...
  echo cd /d ^"%PROJECT_DIR%^" ^|^| exit /b 1
  echo uv pip install -r requirements.txt ^|^| exit /b 1
  echo.
  echo echo [OK] Ready.
  echo echo Run:
  echo echo   python src\main.py
  if "%TF%"=="1" (
    echo echo   python src\validate_tf.py
  )
  echo exit /b 0
)

rem -----------------------
rem scripts/run.cmd
rem -----------------------
> "%PROJECT_DIR%\scripts\run.cmd" (
  echo @echo off
  echo setlocal EnableExtensions
  echo set ^"PROJECT_DIR=%PROJECT_DIR%^"
  echo set ^"ENV_DIR=%ENV_DIR%^"
  echo where conda ^>nul 2^>nul ^|^| ^(echo [ERR] conda not found on PATH ^& exit /b 1^)
  echo if not exist ^"%ENV_DIR%\python.exe^" ^(
  echo   echo [ERR] Env not found: ^"%ENV_DIR%^"
  echo   echo Run: scripts\dev.cmd
  echo   exit /b 1
  echo ^)
  echo call conda activate ^"%ENV_DIR%^" ^|^| exit /b 1
  echo cd /d ^"%PROJECT_DIR%^" ^|^| exit /b 1
  echo python src\main.py
)

rem -----------------------
rem TF validation files (only if --tf)
rem -----------------------
if "%TF%"=="1" (
  > "%PROJECT_DIR%\src\validate_tf.py" (
    echo import os
    echo import time
    echo.
    echo os.environ.setdefault^(^"TF_CPP_MIN_LOG_LEVEL^", ^"1^"^)
    echo.
    echo import tensorflow as tf  # noqa: E402
    echo.
    echo def main^(^) -^> None:
    echo     print^(^"TensorFlow:^", tf.__version__^)
    echo     gpus = tf.config.list_physical_devices^(^"GPU^"^)
    echo     print^(^"GPUs:^", gpus^)
    echo.
    echo     # Avoid grabbing all VRAM ^(helps VS Code notebooks too^)
    echo     for g in gpus:
    echo         try:
    echo             tf.config.experimental.set_memory_growth^(g, True^)
    echo         except Exception as e:
    echo             print^(^"Could not set memory growth:^", e^)
    echo.
    echo     a = tf.random.uniform^((2048, 2048^)^)
    echo     b = tf.random.uniform^((2048, 2048^)^)
    echo.
    echo     t0 = time.time^(^)
    echo     c = tf.linalg.matmul^(a, b^)
    echo     _ = c.numpy^(^)  # force execution
    echo     t1 = time.time^(^)
    echo.
    echo     print^(^"Matmul OK. Seconds:^", round^(t1 - t0, 3^)^)
    echo     print^(^"First run may be slower due to CUDA/PTX/XLA warmup.^"^)
    echo.
    echo if __name__ == ^"__main__^":
    echo     main^(^)
  )

  > "%PROJECT_DIR%\scripts\validate_tf.cmd" (
    echo @echo off
    echo setlocal EnableExtensions
    echo set ^"PROJECT_DIR=%PROJECT_DIR%^"
    echo set ^"ENV_DIR=%ENV_DIR%^"
    echo where conda ^>nul 2^>nul ^|^| ^(echo [ERR] conda not found on PATH ^& exit /b 1^)
    echo if not exist ^"%ENV_DIR%\python.exe^" ^(
    echo   echo [ERR] Env not found: ^"%ENV_DIR%^"
    echo   echo Run: scripts\dev.cmd
    echo   exit /b 1
    echo ^)
    echo call conda activate ^"%ENV_DIR%^" ^|^| exit /b 1
    echo cd /d ^"%PROJECT_DIR%^" ^|^| exit /b 1
    echo python src\validate_tf.py
  )
)

rem -----------------------
rem .gitignore
rem -----------------------
> "%PROJECT_DIR%\.gitignore" (
  echo __pycache__/
  echo *.pyc
  echo .venv/
  echo .env
  echo .python-version
  echo .ruff_cache/
  echo .pytest_cache/
  echo .mypy_cache/
  echo .vscode/
  echo .idea/
  echo .DS_Store
  echo.
  echo # Conda env is outside project by default ^(D:\dev\envs\conda\NAME^)
  echo.
  echo # Local outputs
  echo dist/
  echo build/
  echo *.egg-info/
)

rem -----------------------
rem README.md
rem -----------------------
> "%PROJECT_DIR%\README.md" (
  echo # %NAME%
  echo.
  echo Scaffold created by `new-python-project.bat` ^(toolchain: conda + uv^).
  echo.
  echo ## Flags
  if "%AI%"=="1" (echo - AI/ML: enabled) else (echo - AI/ML: disabled)
  if "%TF%"=="1" (echo - TensorFlow: enabled) else (echo - TensorFlow: disabled)
  echo.
  echo ## Layout
  echo - `src/` - app code
  echo - `scripts/` - helper scripts
  echo - `.vscode/` - editor settings ^(points to the conda env interpreter^)
  echo - `requirements.txt` - deps ^(installed via `uv pip` inside the conda env^)
  echo - `project_config.yaml` - local metadata ^(includes flags^)
  echo.
  echo ## Quick start ^(CMD^)
  echo 1^) Create/activate env + install deps:
  echo ```bat
  echo scripts\dev.cmd
  echo ```
  echo 2^) Run:
  echo ```bat
  echo scripts\run.cmd
  echo ```
  if "%TF%"=="1" (
    echo.
    echo ## TensorFlow GPU notes ^(important^)
    echo - First run can be slow due to CUDA/PTX/XLA warmup. This is expected.
    echo - `src\validate_tf.py` enables GPU memory-growth to avoid grabbing all VRAM.
    echo - Validate:
    echo ```bat
    echo scripts\validate_tf.cmd
    echo ```
    echo.
    echo ## UI on iGPU, compute on dGPU ^(Windows practical approach^)
    echo - If you build a UI app (Electron/Qt/etc.), set that UI app to **Power saving** (iGPU) in:
    echo   Windows Settings ^> System ^> Display ^> Graphics.
    echo - Keep Python/TensorFlow processes as **High performance** (dGPU) if needed.
    echo - This separation avoids the UI binding to the dGPU while letting TF use it.
  )
  echo.
  echo ## TODO notes (kept as comments)
  echo - If you see `Xorg`/GUI processes in GPU tools, it can be normal for desktop composition.
  echo - If you want strict iGPU-first behavior for GUI, enforce per-app graphics preferences.
)

echo [OK] Python project created:
echo   %PROJECT_DIR%
echo Env prefix (created by scripts\dev.cmd):
echo   %ENV_DIR%
exit /b 0

rem -----------------------
rem helpers
rem -----------------------
:help
echo new-python-project.bat
echo.
echo Usage:
echo   new-python-project.bat --name NAME [--projects-root PATH] [--devroot PATH] [--ai] [--tf] [--force]
echo.
echo Examples:
echo   new-python-project.bat --name demo
echo   new-python-project.bat --name demo --ai --tf
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

:write_unique
rem naive unique writer: sorts and removes dupes via sort (available on Windows)
rem %1 = input, %2 = output
sort "%~1" /unique > "%~2"
exit /b 0
