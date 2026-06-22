@echo off & if not [%1]==[] goto :process

echo.
echo This script demonstrates how shellsplit.cmd works.
echo usage: %0 arg1 arg2...
echo.
echo Prints separated arguments as (arg1)(arg2)...
echo - splits commandline with spaces/tabs. cmd.exe standard rule is ignored.
echo - you can use double quotes to contain spaces/tabs into an argument.
echo - you can not escape double quote.
echo - solitary "" is ignored since cmd.exe variables cannot represent empty value.
exit /b 0

:process
setlocal
set V=0

:: %* can contain meta character inside quote. do not use set "args=%*" here.
set args=%*

:loop
call %~dp0\shellsplit.cmd
if not defined argv goto :end
set /p "tmp=(%argv%)"<NUL
goto :loop

:end
endlocal & exit /b 0
