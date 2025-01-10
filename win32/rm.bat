@echo off
@setlocal EnableExtensions DisableDelayedExpansion || exit /b -1
set recursive=
:optloop
if "%1" == "-f" shift
if "%1" == "-r" (shift & set "recursive=1" & goto :optloop)
if "%1" == "--debug" (shift & set PROMPT=$E[34m+$E[m$S & echo on & goto :optloop)
:begin
if "%1" == "" goto :end
set p=%1
shift
set p=%p:/=\%
if not exist "%p%" goto :begin
del /q "%p%" > nul && goto :begin
if "%recursive%" == "1" for /D %%I in (%p%) do (
    rd /s /q %%I
)
goto :begin
:end
