@echo off
setlocal EnableExtensions

cd /d "%~dp0"

set "ROOT=%~dp0"
set "CONFIG=Release"
set "RID=win-x64"
set "RELEASE_DIR=%ROOT%release"
set "VERSION="

where dotnet >nul 2>&1
if errorlevel 1 goto :dotnet_missing

for /f "usebackq delims=" %%V in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$xml=[xml](Get-Content -Raw -LiteralPath '%ROOT%LiteMonitor.csproj'); ($xml.Project.PropertyGroup | Where-Object { $_.Version } | Select-Object -First 1).Version"`) do set "VERSION=%%V"
if not defined VERSION set "VERSION=unknown"

if not exist "%RELEASE_DIR%" mkdir "%RELEASE_DIR%"

echo [1/4] Restoring packages...
dotnet restore "%ROOT%LiteMonitor.sln" --nologo -clp:ErrorsOnly
if errorlevel 1 goto :failed

echo.
echo [2/4] Publishing net8.0, net9.0 and net10.0 packages...
for %%T in (net8.0 net9.0 net10.0) do (
  call :build_target %%T
  if errorlevel 1 goto :failed
)

echo.
echo All release packages created successfully in:
echo %RELEASE_DIR%
echo.
if /i not "%~1"=="nopause" pause
exit /b 0

:build_target
set "TFM_LABEL=%~1"
set "TFM=%TFM_LABEL%-windows"
set "STAGE_DIR=%RELEASE_DIR%\_%TFM_LABEL%_stage"
set "UPDATER_DIR=%RELEASE_DIR%\_%TFM_LABEL%_updater"
set "BUILD_DIR=%RELEASE_DIR%\_%TFM_LABEL%_build"
set "UPDATER_SOURCE=%UPDATER_DIR%\LiteMonitor.Updater.exe"
set "PACKAGE=%RELEASE_DIR%\LiteMonitor_v%VERSION%-%TFM_LABEL%-%RID%.zip"

if exist "%STAGE_DIR%" rmdir /s /q "%STAGE_DIR%"
if exist "%UPDATER_DIR%" rmdir /s /q "%UPDATER_DIR%"
if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
if exist "%PACKAGE%" del /q "%PACKAGE%"
if exist "%STAGE_DIR%" exit /b 1
if exist "%UPDATER_DIR%" exit /b 1
if exist "%BUILD_DIR%" exit /b 1

echo.
echo [2/4] Publishing updater for %TFM_LABEL%...
dotnet publish "%ROOT%LiteMonitor.Updater\LiteMonitor.Updater.csproj" ^
  -f "%TFM%" -c "%CONFIG%" -r "%RID%" --self-contained true --no-restore --nologo ^
  -p:PublishSingleFile=true -p:PublishTrimmed=false ^
  -p:BaseOutputPath="%BUILD_DIR%\updater" -o "%UPDATER_DIR%" -clp:ErrorsOnly
if errorlevel 1 exit /b 1
if not exist "%UPDATER_SOURCE%" exit /b 1

echo [3/4] Publishing main application for %TFM_LABEL%...
dotnet publish "%ROOT%LiteMonitor.csproj" ^
  -f "%TFM%" -c "%CONFIG%" --self-contained false --no-restore --nologo ^
  -p:DebugType=None -p:DebugSymbols=false ^
  -p:BaseOutputPath="%BUILD_DIR%\main" -o "%STAGE_DIR%" -clp:ErrorsOnly
if errorlevel 1 exit /b 1
if not exist "%STAGE_DIR%\LiteMonitor.exe" exit /b 1

echo [4/4] Creating %TFM_LABEL% archive...
if not exist "%STAGE_DIR%\resources" mkdir "%STAGE_DIR%\resources"
copy /y "%UPDATER_SOURCE%" "%STAGE_DIR%\resources\LiteMonitor.Updater.exe" >nul
if errorlevel 1 exit /b 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $stage='%STAGE_DIR%'; $package='%PACKAGE%'; for($attempt=1; $attempt -le 5; $attempt++){ try { if(Test-Path -LiteralPath $package){Remove-Item -LiteralPath $package -Force}; Compress-Archive -Path (Join-Path -Path $stage -ChildPath '*') -DestinationPath $package -CompressionLevel Optimal -Force; $zip=[System.IO.Compression.ZipFile]::OpenRead($package); try { $names=@(); foreach($entry in $zip.Entries){ $names += $entry.FullName.Replace('/','\') }; $valid=($names -contains 'LiteMonitor.exe') -and ($names -contains 'resources\LiteMonitor.Updater.exe') } finally { $zip.Dispose() }; if($valid){ exit 0 }; throw 'Archive validation failed.' } catch { if($attempt -eq 5){ Write-Error $_; exit 1 }; Start-Sleep -Seconds 2 } }; exit 1"
if errorlevel 1 exit /b 1
if not exist "%PACKAGE%" exit /b 1

for %%F in ("%PACKAGE%") do set "PACKAGE_SIZE=%%~zF"
rmdir /s /q "%STAGE_DIR%" >nul 2>&1
rmdir /s /q "%UPDATER_DIR%" >nul 2>&1
rmdir /s /q "%BUILD_DIR%" >nul 2>&1
echo Created: %PACKAGE% (%PACKAGE_SIZE% bytes)
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
