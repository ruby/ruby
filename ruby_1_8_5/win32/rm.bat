@echo off
if "%1" == "-f" shift
:begin
if "%1" == "" goto :end
if exist "%1" del "%1"
shift
goto :begin
:end
