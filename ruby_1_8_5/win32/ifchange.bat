@echo off
:: usage: ifchange target temporary

:: check if fc.exe works.
echo foo > conftest1.tmp
echo bar > conftest2.tmp
fc.exe conftest1.tmp conftest2.tmp > nul
if not errorlevel 1 goto :brokenfc
del conftest1.tmp > nul
del conftest2.tmp > nul

:: target does not exist or new file differs from it.
if not exist %1 goto :update
fc.exe %1 %2 > nul
if errorlevel 1 goto :update

:unchange
echo %1 unchanged.
del %2
goto :end

:brokenfc
del conftest1.tmp > nul
del conftest2.tmp > nul
echo FC.EXE does not work properly.
echo assuming %1 should be changed.

:update
echo %1 updated.
if exist %1 del %1
copy %2 %1 > nul
:end
