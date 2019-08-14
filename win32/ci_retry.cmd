@echo off

if "%WAITS%" == "" set WAITS=1 25 100
for %I in (0 %WAITS%) do (
    sleep %%I
    echo + %*
    %* && exit /b 0
)
exit /b 1
