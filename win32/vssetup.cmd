@setlocal ENABLEEXTENSIONS
::- do not `echo off` that affects the called batch files

::- check for vswhere
@set vswhere=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
@if not exist "%vswhere%" (
  echo 1>&2 vswhere.exe not found
  exit /b 1
)

::- find the latest build tool and its setup batch file.
@set VSDEVCMD=
@for /f "delims=" %%I in ('"%vswhere%" -products * -latest -property installationPath') do @(
  set VSDEVCMD=%%I\Common7\Tools\VsDevCmd.bat
)
@if not defined VSDEVCMD (
  echo 1>&2 Visual Studio not found
  exit /b 1
)

::- default to the current processor.
@set arch=%PROCESSOR_ARCHITECTURE%
::- `vsdevcmd.bat` requires arch names to be lowercase
@for %%i in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do @(
  call set arch=%%arch:%%i=%%i%%
)
@(endlocal && "%VSDEVCMD%" -arch=%arch% -host_arch=%arch% %*)
