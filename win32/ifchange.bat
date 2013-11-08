@echo off
:: usage: ifchange target temporary

set timestamp=
set keepsuffix=
set empty=
:optloop
for %%I in (%1) do set opt=%%~I
if "%opt%" == "--timestamp" (
    set timestamp=.
    shift
    goto :optloop
) else if "%opt:~0,12%" == "--timestamp=" (
    set timestamp=%opt:~12%
    shift
    goto :optloop
) else if "%opt%" == "--keep" (
    set keepsuffix=.old
    shift
    goto :optloop
) else if "%opt:~0,7%" == "--keep=" (
    set keepsuffix=%opt:~7%
    shift
    goto :optloop
) else if "%opt%" == "--empty" (
    set empty=yes
    shift
    goto :optloop
)
if "%opt%" == "" goto :end

set dest=%1
set src=%2
set dest=%dest:/=\%
set src=%src:/=\%
if not "%dest%" == "" if not "%dest%" == "%%dest:/=\%%" goto :nt

if not exist %2 goto :end

:: check if fc.exe works.
echo foo > conftst1.tmp
echo bar > conftst2.tmp
fc.exe conftst1.tmp conftst2.tmp > nul
if not errorlevel 1 goto :brokenfc
del conftst1.tmp > nul
del conftst2.tmp > nul

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
:: if exist %1 del %1
dir /b %2
if "%keepsuffix%" != "" %1 %1%keepsuffix%
copy %2 %1
del %2
goto :end

:nt
if exist %dest% (
    if not exist %src% goto :nt_unchanged1
    if "%empty%" == "" for %%I in (%src%) do if %%~zI == 0 goto :nt_unchanged
    fc.exe %dest% %src% > nul && (
      :nt_unchanged
	del %src%
      :nt_unchanged1
	for %%I in (%1) do echo %%~I unchanged
	goto :nt_end
    )
)
for %%I in (%1) do echo %%~I updated
copy %src% %dest% > nul
del %src%

:nt_end
if "%timestamp%" == "" goto :end
    if "%timestamp%" == "." (
        for %%I in ("%dest%") do set timestamp=%%~dpI.time.%%~nxI
    )
    goto :end > "%timestamp%"
:end
