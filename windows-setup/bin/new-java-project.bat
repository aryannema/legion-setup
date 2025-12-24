@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem ============================================================
rem new-java-project.bat
rem - Creates a minimal "plain JDK" Java scaffold (no Maven/Gradle)
rem - Flags:
rem     --ai : adds README notes for AI/ML options (DJL/ONNX/etc.)
rem     --tf : adds README notes recommending TF via Python service or ONNX
rem - Safety:
rem     refuses to overwrite a non-empty project dir unless --force
rem
rem Usage:
rem   new-java-project.bat --name myjava
rem   new-java-project.bat --name myjava --ai
rem   new-java-project.bat --name myjava --tf
rem   new-java-project.bat --name myjava --ai --tf
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
call :ensure_dir "%PROJECT_DIR%\out"

rem toolchain check (soft fail: warn, but scaffold can still be created)
where javac >nul 2>nul || echo [WARN] javac not found on PATH (build.cmd will fail until JDK is installed)
where java  >nul 2>nul || echo [WARN] java not found on PATH (run.cmd will fail until JDK is installed)

> "%PROJECT_DIR%\src\Main.java" (
  echo public class Main {
  echo     public static void main(String[] args) {
  echo         System.out.println("Hello from %NAME%!");
  echo         System.out.println("Java: " + System.getProperty("java.version"));
  echo     }
  echo }
)

> "%PROJECT_DIR%\scripts\build.cmd" (
  echo @echo off
  echo setlocal EnableExtensions
  echo set ^"PROJECT_DIR=%PROJECT_DIR%^"
  echo set ^"SRC_DIR=%%PROJECT_DIR%%\src^"
  echo set ^"OUT_DIR=%%PROJECT_DIR%%\out^"
  echo.
  echo where javac ^>nul 2^>nul ^|^| ^(echo [ERR] javac not found on PATH ^& exit /b 1^)
  echo if not exist ^"%%OUT_DIR%%^" mkdir ^"%%OUT_DIR%%^" ^>nul 2^>nul
  echo echo [INFO] Compiling...
  echo javac -d ^"%%OUT_DIR%%^" ^"%%SRC_DIR%%\Main.java^" ^|^| exit /b 1
  echo echo [OK] Build output: ^"%%OUT_DIR%%^"
  echo exit /b 0
)

> "%PROJECT_DIR%\scripts\run.cmd" (
  echo @echo off
  echo setlocal EnableExtensions
  echo set ^"PROJECT_DIR=%PROJECT_DIR%^"
  echo set ^"OUT_DIR=%%PROJECT_DIR%%\out^"
  echo.
  echo where java ^>nul 2^>nul ^|^| ^(echo [ERR] java not found on PATH ^& exit /b 1^)
  echo if not exist ^"%%OUT_DIR%%\Main.class^" ^(
  echo   echo [INFO] No build found. Running build first...
  echo   call ^"%%PROJECT_DIR%%\scripts\build.cmd^" ^|^| exit /b 1
  echo ^)
  echo echo [INFO] Running...
  echo java -cp ^"%%OUT_DIR%%^" Main
)

> "%PROJECT_DIR%\project_config.yaml" (
  echo name: %NAME%
  echo language: java
  echo paths:
  echo   project_root: %PROJECT_DIR%
  echo flags:
  if "%AI%"=="1" (echo   ai_ml: true) else (echo   ai_ml: false)
  if "%TF%"=="1" (echo   tensorflow: true) else (echo   tensorflow: false)
  echo toolchain:
  echo   jdk: true
  echo   build: plain-javac
)

> "%PROJECT_DIR%\.gitignore" (
  echo out/
  echo .idea/
  echo .vscode/
  echo *.class
  echo *.log
)

> "%PROJECT_DIR%\README.md" (
  echo # %NAME%
  echo.
  echo Minimal Java scaffold created by `new-java-project.bat` ^(plain JDK; no Maven/Gradle assumed^).
  echo.
  echo ## Quick start ^(CMD^)
  echo Build:
  echo ```bat
  echo scripts\build.cmd
  echo ```
  echo Run:
  echo ```bat
  echo scripts\run.cmd
  echo ```
  echo.
  echo ## Tooling
  echo - Requires a JDK on PATH (`javac`, `java`).
  echo - If you later want Maven/Gradle, add them manually and extend this project.
  echo.
  echo ## Flags
  if "%AI%"=="1" (echo - AI/ML: enabled) else (echo - AI/ML: disabled)
  if "%TF%"=="1" (echo - TensorFlow: enabled) else (echo - TensorFlow: disabled)
  echo.
  if "%AI%"=="1" (
    echo ## AI/ML notes (comments / suggestions)
    echo - In Java, common choices are:
    echo   - DJL (Deep Java Library) to run models from various backends
    echo   - ONNX Runtime (Java binding) for running ONNX models
    echo - Suggested pattern: keep model execution behind an interface so you can swap implementations.
    echo.
  )
  if "%TF%"=="1" (
    echo ## TensorFlow in Java (recommended alternatives)
    echo - Direct TF-Java usage is possible but can be painful for GPU + packaging.
    echo - Better alternatives:
    echo   1^) Run TensorFlow in a Python microservice (FastAPI) and call it from Java.
    echo   2^) Export to ONNX and use ONNX Runtime Java.
    echo.
    echo ## UI on iGPU, compute on dGPU (Windows practical approach)
    echo - If you build a UI app (JavaFX/Swing), set the UI executable to **Power saving** (iGPU)
    echo   in Windows Settings ^> System ^> Display ^> Graphics.
    echo - Keep your compute process/service as **High performance** (dGPU) if needed.
    echo.
    echo ## TODO comment
    echo - If desktop/GUI shows up in GPU tools, it can be normal.
    echo - Enforce per-app graphics preferences for iGPU-first GUI behavior.
  )
)

echo [OK] Java project created:
echo   %PROJECT_DIR%
exit /b 0

:help
echo new-java-project.bat
echo.
echo Usage:
echo   new-java-project.bat --name NAME [--projects-root PATH] [--ai] [--tf] [--force]
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
