@echo off
setlocal
set recursive=
:optloop
if "%1" == "-f" shift
if "%1" == "-r" (shift & set "recursive=1" & goto :optloop)
:begin
if "%1" == "" goto :end
set p=%1
if exist "%p:/=\%" for %%I in ("%p:/=\%") do (
    del /q "%%I" || if "%recursive%" == "1" rd /s /q "%%I"
) 2> nul
shift
goto :begin
:end
