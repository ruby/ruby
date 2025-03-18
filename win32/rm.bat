@echo off
setlocal
set recursive=
:optloop
if "%1" == "-f" shift
if "%1" == "-r" (shift & set "recursive=1" & goto :optloop)
if "%1" == "--debug" (shift & set PROMPT=$E[34m+$E[m$S & echo on & goto :optloop)
:begin
if "%1" == "" goto :end
set p=%1
set p=%p:/=\%
if exist "%p%" del /q "%p%" > nul
if "%recursive%" == "1" for /D %%I in (%p%) do (
    rd /s /q %%I
)
shift
goto :begin
:end
