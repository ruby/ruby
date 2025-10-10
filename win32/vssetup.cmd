@setlocal EnableExtensions DisableDelayedExpansion || exit /b -1
::- do not `echo off` that affects the called batch files

::- check for vswhere
@set vswhere=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
@if not exist "%vswhere%" (
  echo 1>&2 vswhere.exe not found
  exit /b 1
)

::- find the latest build tool and its setup batch file.
@set VSDEVCMD=
@set VSDEV_ARGS=
@set where_opt=
@set arch=
:argloop
@(set arg=%1) & if defined arg (shift) else (goto :argend)
    @if "%arg%" == "-prerelease" (
        set where_opt=-prerelease
        goto :argloop
    )
    @if /i "%arg%" == "-arch" (
        set arch=%1
        shift
        goto :argloop
    )
    @if /i "%arg:~0,6%" == "-arch=" (
        set arch=%arg:~6%
        goto :argloop
    )

    @set VSDEV_ARGS=%VSDEV_ARGS% %arg%
    @goto :argloop
:argend
@if defined VSDEV_ARGS set VSDEV_ARGS=%VSDEV_ARGS:~1%

@for /f "delims=" %%I in ('"%vswhere%" -products * -latest -property installationPath %where_opt%') do @(
  set VSDEVCMD=%%I\Common7\Tools\VsDevCmd.bat
)
@if not defined VSDEVCMD (
  echo 1>&2 Visual Studio not found
  exit /b 1
)

::- default to the current processor.
@set host_arch=%PROCESSOR_ARCHITECTURE%
@if not defined arch set arch=%PROCESSOR_ARCHITECTURE%
::- `vsdevcmd.bat` requires arch names to be lowercase
@for %%i in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do @(
  call set arch=%%arch:%%i=%%i%%
  call set host_arch=%%host_arch:%%i=%%i%%
)
@if "%arch%" == "x86_64" set arch=amd64

::- chain to `vsdevcmd.bat`
@(endlocal && "%VSDEVCMD%" -arch=%arch% -host_arch=%host_arch% %VSDEV_ARGS%)
