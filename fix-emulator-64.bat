@echo off
REM ============================================================================
REM  Marginalia - fetch the 64-bit emulator image and rebuild the AVD.
REM
REM  Run:  fix-emulator-64.bat
REM
REM  Why this is needed at all:
REM    The AVD installed earlier uses the 32-bit x86 image. Flutter does not
REM    support running or debugging on a 32-bit emulator, which is why every
REM    device showed the "unsupported" label and `flutter run` refused to pick
REM    one. There is no flag for that; the image itself has to change.
REM
REM  This downloads about 2-3 GB, then creates a second AVD named marginalia64.
REM  The original 32-bit AVD is left in place rather than deleted: it is not
REM  ours to remove, and it costs nothing to keep.
REM ============================================================================

setlocal

set "SDK=E:\Dev_work\Android_Dev\Dev_Tools\Android_SDK\SDK_For_AS352"
set "JDK8=E:\Dev_work\Java_Dev\JDK_SRC\JDK_1.8"
set "SDKMANAGER=%SDK%\tools\bin\sdkmanager.bat"
set "AVDMANAGER=%SDK%\tools\bin\avdmanager.bat"
set "ANDROID_HOME=%SDK%"
set "ANDROID_SDK_ROOT=%SDK%"

REM sdkmanager and avdmanager both need JDK 8: JAXB was removed from the JDK in
REM 11, and both tools still reference it.
set "JAVA_HOME=%JDK8%"
set "PATH=%JDK8%\bin;%PATH%"

set "IMAGE=system-images;android-29;google_apis_playstore;x86_64"

echo.
echo   Marginalia - 64-bit emulator image
echo   -----------------------------------------------------
echo   Downloading roughly 2-3 GB. This takes a while and
echo   cannot be interrupted without starting over.
echo.

echo no | call "%SDKMANAGER%" "%IMAGE%"
if errorlevel 1 (
  echo.
  echo   ERROR: the download failed. Check the output above.
  pause
  exit /b 1
)

echo.
echo   Creating the AVD named marginalia64...
echo.

echo no | call "%AVDMANAGER%" create avd -n marginalia64 -k "%IMAGE%" -d pixel --force
if not exist "%USERPROFILE%\.android\avd\marginalia64.avd" (
  echo.
  echo   ERROR: creating the AVD failed.
  pause
  exit /b 1
)

echo.
echo   Done.
echo.
echo   Now run  run-emulator.bat  and it will use the 64-bit image.
echo   If it still picks the old one, close every emulator window first.
echo.
pause