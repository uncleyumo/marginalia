@echo off
chcp 65001 >nul
REM ============================================================================
REM  Marginalia - start an Android emulator, wait for it, then run the app.
REM
REM  Usage:  run-emulator.bat
REM
REM  avdmanager needs JDK 8 (it crashes on 11+ with a missing JAXB class) while
REM  the Gradle build needs 17+. This script hands avdmanager the 8 it wants, for
REM  one command only, and leaves the build pinned to 21 in gradle.properties.
REM ============================================================================

setlocal

REM  Every path is read from the environment first and falls back to the
REM  machine this was written on. Set SDK_HOME / PROJECT_HOME / FLUTTER_HOME /
REM  JDK8_HOME / JDK21_HOME in your shell and nothing below needs editing.
if "%SDK_HOME%"==""     set "SDK_HOME=E:\Dev_work\Android_Dev\Dev_Tools\Android_SDK\SDK_For_AS352"
if "%PROJECT_HOME%"=="" set "PROJECT_HOME=E:\Dev_work\Flutter_Dev\marginalia\Marginalia"
if "%FLUTTER_HOME%"=="" set "FLUTTER_HOME=E:\Dev_work\Android_Dev\Dev_Tools\Flutter_SDK\flutter_windows_3.44.3-stable"
if "%JDK8_HOME%"==""    set "JDK8_HOME=E:\Dev_work\Java_Dev\JDK_SRC\JDK_1.8"
if "%JDK21_HOME%"==""   set "JDK21_HOME=E:\Dev_work\Java_Dev\JDK_SRC\JDK_21"
set "SDK=%SDK_HOME%"
set "PROJECT=%PROJECT_HOME%"
set "FLUTTER=%FLUTTER_HOME%"
set "JDK8=%JDK8_HOME%"
set "JDK21=%JDK21_HOME%"
set "ADB=%SDK%\platform-tools\adb.exe"
set "EMULATOR=%SDK%\emulator\emulator.exe"
set "AVDMANAGER=%SDK%\tools\bin\avdmanager.bat"
set "ENGINE=%SDK%\emulator\qemu\windows-x86_64\qemu-system-x86_64.exe"

set "ANDROID_HOME=%SDK%"
set "ANDROID_SDK_ROOT=%SDK%"
set "ANDROID_AVD_HOME=%USERPROFILE%\.android\avd"

REM ENGINE has no trailing backslash on purpose: a quoted path ending in one
REM turns the closing quote into an escaped quote, and the test then reports
REM a file that is plainly there as missing.
if not exist "%ENGINE%" (
  echo   ERROR: the emulator engine is missing.
  echo     expected: %ENGINE%
  pause
  exit /b 1
)

if not exist "%ANDROID_AVD_HOME%\marginalia64.avd" (
  echo   Creating the AVD named marginalia. This step uses JDK 8.
  set "JAVA_HOME=%JDK8%"
  set "PATH=%JDK8%\bin;%PATH%"
  echo no | call "%AVDMANAGER%" create avd -n marginalia64 -k "system-images;android-29;google_apis_playstore;x86_64" -d pixel --force
  if not exist "%ANDROID_AVD_HOME%\marginalia64.avd" (
    echo.
    echo   ERROR: creating the AVD failed.
    pause
    exit /b 1
  )
  echo   Created.
)

REM Back to 21 for the build.
set "JAVA_HOME=%JDK21%"
set "PATH=%JDK21%\bin;%FLUTTER%\bin;%SDK%\platform-tools;%PATH%"

echo.
echo   Marginalia
echo   -----------------------------------------------------
echo   Starting the emulator. First boot takes 1-3 minutes.
echo.

start "Marginalia emulator" /min "%EMULATOR%" -avd marginalia64 -no-skin -no-boot-anim

echo   Waiting for the device to finish booting...
"%ADB%" start-server >nul 2>&1
"%ADB%" wait-for-device >nul 2>&1

set "BOOTED="
:wait
for /f "tokens=1" %%b in ('"%ADB%" shell getprop sys.boot_completed 2^>nul') do set "BOOTED=%%b"
if "%BOOTED%"=="1" goto ready
timeout /t 3 /nobreak >nul
goto wait

:ready
echo   Device is up.
"%ADB%" devices

echo   Stopping Gradle daemons started by an earlier JDK...
pushd "%PROJECT%\android"
call gradlew.bat --stop >nul 2>&1
popd

if exist "%PROJECT%\build" (
  echo   Clearing stale build output...
  rd /s /q "%PROJECT%\build" >nul 2>&1
)

cd /d "%PROJECT%"
echo.
echo   Building and launching. The first build takes 3-10 minutes.
echo.

REM No -d flag on purpose.
REM
REM `flutter devices` labels the emulator "unsupported", because it reads
REM ro.build.characteristics, which is literally the string "emulator" on an AVD
REM and "default" on a handset. That label is only used when flutter PICKS a
REM device for you; naming it explicitly with -d bypasses the picker entirely.
REM Naming it made it WORSE, though: with -d, flutter validates the id against
REM its own supported list first and rejects it. Letting it choose the only
REM target is the path that works, so this passes nothing at all.
flutter run

echo.
echo   Stopped.
pause
