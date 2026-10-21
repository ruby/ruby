@echo off
::- Add Windows Defender Firewall rules that block inbound connections to
::- ruby.exe and rubyw.exe in the build directory, so that tests listening
::- on all interfaces do not bring up the security alert dialog.
::- With -delete, delete the rules added for the build directory.
@setlocal EnableExtensions DisableDelayedExpansion || exit /b -1

set dir=.
set delete=
:argloop
::- %~1, not %1, which would break on a quoted path with parentheses
(set "arg=%~1") & if not defined arg goto :argend
shift /1
if /i "%arg%" == "-delete" (
    set delete=-delete
    goto :argloop
)
if "%arg:~0,1%" == "-" (
    (echo usage: %~nx0 [-delete] [build directory]) 1>&2
    exit /b 1
)
set "dir=%arg%"
goto :argloop
:argend

for %%I in ("%dir%\.") do set "dir=%%~fI"
if not defined delete if not exist "%dir%\" (
    (echo "%dir%" is not a directory) 1>&2
    exit /b 1
)
set "name=Ruby build directory %dir%"

fltmc >nul 2>&1 && goto :elevated
::- the elevated window closes at once, so show the result here
set "args=/c ""%~f0" %delete% "%dir%"""
powershell -NoProfile -Command "$p = Start-Process -Verb RunAs -Wait -PassThru -ErrorAction Stop $env:ComSpec $env:args; exit $p.ExitCode"
set "status=%errorlevel%"
netsh advfirewall firewall show rule name="%name%" verbose
exit /b %status%

:elevated
if defined delete (
    netsh advfirewall firewall delete rule name="%name%"
    exit /b 0
)
netsh advfirewall firewall delete rule name="%name%" >nul
for %%I in (ruby rubyw) do (
    netsh advfirewall firewall add rule name="%name%" dir=in action=block program="%dir%\%%I.exe" || exit /b
)
