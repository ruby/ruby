@echo off
::: $Id: rm.bat,v 1.1 2004/03/21 23:21:30 nobu Exp $
if "%1" == "-f" shift
:begin
if "%1" == "" goto :end
if exist "%1" del "%1"
shift
goto :begin
:end
