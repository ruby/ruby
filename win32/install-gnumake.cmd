@echo off
@setlocal EnableExtensions DisableDelayedExpansion || exit /b -1

::- usage: install-gnumake.cmd [destdir]
::- Builds GNU make from the GNU release with cl.exe, using only the
::- tools bundled with Windows to fetch and verify it.

set version=4.4.1
set sha256=dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3
:: The tarball is checked against sha256, so a mirror is as good as the origin.
set mirrors=https://mirrors.kernel.org/gnu https://ftp.gnu.org/gnu

for %%I in ("%~dp0..") do set "srcdir=%%~fI"
set "dest=%~1"
if not defined dest set "dest=%srcdir%\.gnumake"
for %%I in ("%dest%") do set "dest=%%~fI"
set "tarball=%dest%\make-%version%.tar.gz"
set "builddir=%dest%\make-%version%"

if not exist "%dest%\." mkdir "%dest%" || exit /b 1
call :verify || call :download || exit /b 1

if exist "%builddir%\." rmdir /s /q "%builddir%"
"%SystemRoot%\System32\tar.exe" -xzf "%tarball%" -C "%dest%" || exit /b 1

where cl.exe >nul 2>&1 || call "%~dp0vssetup.cmd" >nul || exit /b 1
pushd "%builddir%" || exit /b 1
call "%builddir%\build_w32.bat" --without-guile
popd
if not exist "%builddir%\WinRel\gnumake.exe" (
    echo 1>&2 failed to build GNU make
    exit /b 1
)
copy /y "%builddir%\WinRel\gnumake.exe" "%dest%\make.exe" >nul || exit /b 1
rmdir /s /q "%builddir%"

echo.
"%dest%\make.exe" --version | findstr /b /c:"GNU Make"
echo installed %dest%\make.exe
exit /b 0

:download
for %%U in (%mirrors%) do (
    "%SystemRoot%\System32\curl.exe" -fsSL --connect-timeout 30 --max-time 300 --retry 2 -o "%tarball%" %%U/make/make-%version%.tar.gz && call :verify && exit /b 0
)
echo 1>&2 failed to download make-%version%.tar.gz with the expected SHA256
exit /b 1

:verify
if not exist "%tarball%" exit /b 1
set actual=
for /f "skip=1 delims=" %%I in ('certutil -hashfile "%tarball%" SHA256') do (
    if not defined actual set "actual=%%I"
)
if not defined actual exit /b 1
if /i "%actual: =%" == "%sha256%" exit /b 0
exit /b 1
