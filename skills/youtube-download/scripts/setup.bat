@echo off
REM Setup script for YouTube Download (Windows)
REM Helps install yt-dlp binary or Python module

echo.
cd /d "%~dp0.."

echo 🎬 YouTube Download Setup (Windows)
echo ===================================
echo.

if not exist "extension.mjs" (
    echo ❌ Error: Could not find the youtube-download skill root; expected extension.mjs and package.json.
    exit /b 1
)
if not exist "package.json" (
    echo ❌ Error: Could not find package.json in the youtube-download skill root.
    exit /b 1
)

REM Install npm dependencies
echo 1️⃣  Installing Node dependencies...
call npm install
if %errorlevel% neq 0 (
    echo ⚠️  npm install failed. Trying with --legacy-peer-deps...
    call npm install --legacy-peer-deps
    if %errorlevel% neq 0 (
        echo ⚠️  npm still failed. You may need to:
        echo    - Update Node.js: https://nodejs.org/
        echo    - Clear cache: npm cache clean --force
        echo    - Try manually: npm install
        exit /b 1
    )
)
echo ✅ Node dependencies installed
echo.

echo 2️⃣  Choose how to run yt-dlp:
echo.
echo   A) Download binary from GitHub (recommended)
echo   B) Install via pip (requires Python)
echo   C) Create virtual environment (isolated Python)
echo   D) Skip (install manually later)
echo.

set /p choice="Choose [A/B/C/D]: "

if /i "%choice%"=="A" (
    echo.
    echo 📥 Downloading yt-dlp binary...
    if not exist "bin" mkdir bin
    
    echo Downloading from GitHub...
    powershell -Command ^
        "$ProgressPreference='SilentlyContinue'; ^
        Invoke-WebRequest -Uri 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' ^
        -OutFile 'bin\yt-dlp.exe'"
    
    echo ✅ Downloaded yt-dlp for Windows
    echo.
) else if /i "%choice%"=="B" (
    echo.
    echo 📦 Installing yt-dlp Python module...
    pip install yt-dlp
    echo ✅ yt-dlp installed
    echo.
) else if /i "%choice%"=="C" (
    echo.
    echo 🐍 Creating virtual environment...
    python -m venv .venv
    call .venv\Scripts\activate.bat
    pip install yt-dlp
    call .venv\Scripts\deactivate.bat
    echo ✅ Virtual environment created with yt-dlp
    echo.
) else if /i "%choice%"=="D" (
    echo Skipped. Install yt-dlp manually when ready.
    echo.
) else (
    echo Invalid choice
    exit /b 1
)

REM Verify setup
echo 3️⃣  Verifying setup...
where yt-dlp >nul 2>nul
if %errorlevel% equ 0 (
    for /f "delims=" %%i in ('yt-dlp --version') do set VERSION=%%i
    echo ✅ yt-dlp found: %VERSION%
) else if exist "bin\yt-dlp.exe" (
    for /f "delims=" %%i in ('bin\yt-dlp.exe --version') do set VERSION=%%i
    echo ✅ yt-dlp binary found: %VERSION%
) else (
    python -c "import yt_dlp; print('✅ yt-dlp Python module found')" 2>nul
    if %errorlevel% neq 0 (
        echo ⚠️  yt-dlp not found. Install with one of the options above.
        exit /b 1
    )
)

echo.
echo 🎉 Setup complete!
echo.
echo Next steps:
echo 1. Reload Copilot extensions (or restart Copilot CLI^)
echo 2. Try: /youtube-download
echo.
