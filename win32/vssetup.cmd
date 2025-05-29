@echo off
setlocal

::- check for vswhere
set vswhere=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
if not exist "%vswhere%" (
  echo 1>&2 vswhere.exe not found
  exit /b 1
)

::- find the latest build tool and its setup batch file.
set VCVARS=
for /f "delims=" %%I in ('"%vswhere%" -products * -latest -property installationPath') do (
  set VCVARS=%%I\VC\Auxiliary\Build\vcvarsall.bat
)
if not defined VCVARS (
  echo 1>&2 Visual Studio not found
  exit /b 1
)

::- If no target is given, setup for the current processor.
set target=
if "%1" == "" set target=%PROCESSOR_ARCHITECTURE%
echo on && endlocal && "%VCVARS%" %target% %*
