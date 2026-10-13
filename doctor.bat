@echo off
chcp 65001 >nul
REM ============================================================================
REM  Marginalia - find out exactly what is wrong, in the order it goes wrong.
REM
REM  Usage:  doctor.bat
REM
REM  Checks: device, APK, install, launch. The install step is where a Xiaomi
REM  phone stops everything with USER_RESTRICTED, which reads like a bug and is
REM  really the handset asking permission.
REM ============================================================================

setlocal enabledelayedexpansion

REM  Paths come from the environment when it has them, and fall back to the
REM  machine this was written on when it does not. That keeps the script
REM  useful as-is for the author and runnable anywhere else — set SDK_HOME and
REM  APK_PATH in your shell and nothing below needs editing.
if "%SDK_HOME%"==""     set "SDK_HOME=E:\Dev_work\Android_Dev\Dev_Tools\Android_SDK\SDK_For_AS352"
if "%APK_PATH%"==""     set "APK_PATH=E:\Dev_work\Flutter_Dev\marginalia\Marginalia\build\app\outputs\flutter-apk\app-debug.apk"
set "SDK=%SDK_HOME%"
set "ADB=%SDK%\platform-tools\adb.exe"
set "APK=%APK_PATH%"
set "PKG=com.marginalia.reader"

echo.
echo   Marginalia doctor
echo   =====================================================================
echo.

echo   [1] device connected
REM Match on field two being exactly "device": findstr would also match the
REM header line "List of devices attached" and pass with nothing attached.
set "SERIAL="
for /f "tokens=1,2" %%a in ('"%ADB%" devices') do (
  if "%%b"=="device" set "SERIAL=%%a"
)

if not defined SERIAL (
  echo       FAIL  no device.
  echo.
  echo             Phone:     plug it in, enable USB debugging, accept the
  echo                       prompt on the handset.
  echo             Emulator:  run run-emulator.bat, which starts one for you.
  echo.
  pause
  exit /b 1
)
echo       ok    %SERIAL%

echo.
echo   [2] apk present
if not exist "%APK%" (
  echo       FAIL  not built yet.
  echo             Run run-app.bat once. The first build downloads Gradle and
  echo             takes 3-10 minutes.
  echo.
  pause
  exit /b 1
)
echo       ok

echo.
echo   [3] install
"%ADB%" -s %SERIAL% install -r "%APK%"
if errorlevel 1 (
  echo.
  echo       FAILED TO INSTALL
  echo.
  echo       On a Xiaomi, Redmi or HyperOS phone open
  echo         Settings, then More settings, then Developer options,
  echo       and set
  echo         USB debugging                ON
  echo         USB installation              ON    <-- this one
  echo         Verify apps over USB          OFF
  echo.
  echo       Then watch the phone: it asks whether to allow installing over USB.
  echo       Tap ALLOW. Nothing installs until you do.
  echo.
  pause
  exit /b 1
)
echo       ok

echo.
echo   [4] launch
"%ADB%" -s %SERIAL% shell monkey -p %PKG% -c android.intent.category.LAUNCHER 1 >nul 2>&1
timeout /t 6 /nobreak >nul
"%ADB%" -s %SERIAL% shell pidof %PKG% >nul 2>&1
if errorlevel 1 (
  echo       WARN  installed but not running.
  echo             Run run-app.bat and read the Dart error in its output.
) else (
  echo       ok    running
)

echo.
echo   All four checks passed.
pause
