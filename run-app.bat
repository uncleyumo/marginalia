@echo off
chcp 65001 >nul
REM ============================================================================
REM  Marginalia - build and run on a connected Android device.
REM
REM  Usage:  run-app.bat
REM
REM  Sets everything the build needs so nothing depends on your shell, then
REM  clears the one thing that breaks on its own: a stale Kotlin incremental
REM  cache from an earlier build under a different JDK. It shows up as
REM      Could not close incremental caches ... class-fq-name-to-source.tab
REM  and its only cure is to delete build\. Better done here than asked of you.
REM ============================================================================

setlocal

set "SDK=E:\Dev_work\Android_Dev\Dev_Tools\Android_SDK\SDK_For_AS352"
set "PROJECT=E:\Dev_work\Flutter_Dev\marginalia\Marginalia"
set "FLUTTER=E:\Dev_work\Android_Dev\Dev_Tools\Flutter_SDK\flutter_windows_3.44.3-stable"
set "JDK=E:\Dev_work\Java_Dev\JDK_SRC\JDK_21"
set "ADB=%SDK%\platform-tools\adb.exe"

set "JAVA_HOME=%JDK%"
set "ANDROID_HOME=%SDK%"
set "ANDROID_SDK_ROOT=%SDK%"
set "ANDROID_AVD_HOME=%USERPROFILE%\.android\avd"
set "PATH=%JDK%\bin;%FLUTTER%\bin;%SDK%\platform-tools;%PATH%"

if not exist "%JDK%\bin\java.exe" (
  echo   ERROR: JDK 21 not found at %JDK%
  pause
  exit /b 1
)

where flutter >nul 2>&1
if errorlevel 1 (
  echo   ERROR: flutter is not on PATH.
  pause
  exit /b 1
)

echo.
echo   Marginalia
echo   -----------------------------------------------------
echo   JDK   %JDK%
echo   SDK   %SDK%
echo.

echo   Looking for a device...
REM Do not use findstr /i "device": it matches the header line
REM "List of devices attached" and reports success with nothing attached.
REM A real device line starts with its serial, so take field two of each line.
set "TARGET="
for /f "tokens=1,2" %%a in ('"%ADB%" devices') do (
  if "%%b"=="device" set "TARGET=%%a"
)

if not defined TARGET (
  echo.
  echo   ERROR: no Android device found.
  echo.
  echo     Phone:      plug it in, enable USB debugging, accept the prompt.
  echo     Emulator:   run run-emulator.bat instead of this one.
  echo.
  pause
  exit /b 1
)

echo   Device   %TARGET%
echo.

echo   Stopping Gradle daemons started by an earlier JDK...
pushd "%PROJECT%\android"
call gradlew.bat --stop >nul 2>&1
popd

REM Build output only. Never touches lib\, assets\ or android\src\.
if exist "%PROJECT%\build" (
  echo   Clearing stale build output...
  rd /s /q "%PROJECT%\build" >nul 2>&1
)

cd /d "%PROJECT%"
if errorlevel 1 (
  echo   ERROR: cannot enter %PROJECT%
  pause
  exit /b 1
)

echo   Building. The first build downloads Gradle (222 MB) plus dependencies
echo   and takes 3-10 minutes. Later builds take a minute or two.
echo.

flutter run -d %TARGET%

echo.
echo   Stopped.
pause
