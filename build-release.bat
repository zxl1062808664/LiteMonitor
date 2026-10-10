@echo off
setlocal EnableExtensions

cd /d "%~dp0"

set "ROOT=%~dp0"
set "CONFIG=Release"
set "RID=win-x64"
set "TFM=net10.0-windows"
set "RELEASE_DIR=%ROOT%release"
set "STAGE_DIR=%RELEASE_DIR%\_stage"
set "UPDATER_DIR=%RELEASE_DIR%\_updater"
set "VERSION="

where dotnet >nul 2>&1
if errorlevel 1 goto :dotnet_missing

for /f "usebackq delims=" %%V in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$xml=[xml](Get-Content -Raw -LiteralPath '%ROOT%LiteMonitor.csproj'); ($xml.Project.PropertyGroup | Where-Object { $_.Version } | Select-Object -First 1).Version"`) do set "VERSION=%%V"
if not defined VERSION set "VERSION=unknown"

set "PACKAGE=%RELEASE_DIR%\LiteMonitor_v%VERSION%-%RID%.zip"
set "UPDATER_SOURCE=%UPDATER_DIR%\LiteMonitor.Updater.exe"

if not exist "%RELEASE_DIR%" mkdir "%RELEASE_DIR%"
if exist "%STAGE_DIR%" rmdir /s /q "%STAGE_DIR%"
if exist "%UPDATER_DIR%" rmdir /s /q "%UPDATER_DIR%"
if exist "%PACKAGE%" del /q "%PACKAGE%"

echo [1/5] Restoring packages...
dotnet restore "%ROOT%LiteMonitor.sln" --nologo
if errorlevel 1 goto :failed

echo [2/5] Publishing the self-contained updater...
dotnet publish "%ROOT%LiteMonitor.Updater\LiteMonitor.Updater.csproj" ^
  -c "%CONFIG%" -r "%RID%" --self-contained true --no-restore --nologo ^
  -p:PublishSingleFile=true -p:PublishTrimmed=false -o "%UPDATER_DIR%"
if errorlevel 1 goto :failed
if not exist "%UPDATER_SOURCE%" goto :failed

echo [3/5] Publishing the main application...
dotnet publish "%ROOT%LiteMonitor.csproj" ^
  -c "%CONFIG%" --self-contained false --no-restore --nologo ^
  -p:DebugType=None -p:DebugSymbols=false -o "%STAGE_DIR%"
if errorlevel 1 goto :failed
if not exist "%STAGE_DIR%\LiteMonitor.exe" goto :failed

echo [4/5] Installing the freshly published updater...
if not exist "%STAGE_DIR%\resources" mkdir "%STAGE_DIR%\resources"
copy /y "%UPDATER_SOURCE%" "%STAGE_DIR%\resources\LiteMonitor.Updater.exe" >nul
if errorlevel 1 goto :failed

echo [5/5] Creating the release archive...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path (Join-Path -Path '%STAGE_DIR%' -ChildPath '*') -DestinationPath '%PACKAGE%' -CompressionLevel Optimal -Force"
if errorlevel 1 goto :failed
if not exist "%PACKAGE%" goto :failed

for %%F in ("%PACKAGE%") do set "PACKAGE_SIZE=%%~zF"
rmdir /s /q "%STAGE_DIR%"
rmdir /s /q "%UPDATER_DIR%"

echo.
echo Release package created successfully:
echo %PACKAGE%
echo Archive size: %PACKAGE_SIZE% bytes
echo.
if /i not "%~1"=="nopause" pause
exit /b 0

:dotnet_missing
echo ERROR: .NET SDK was not found on PATH.
echo Install the .NET 10 SDK and run this script again.
if /i not "%~1"=="nopause" pause
exit /b 1

:failed
echo.
echo ERROR: Release build failed. Temporary files were kept for inspection.
if /i not "%~1"=="nopause" pause
exit /b 1
