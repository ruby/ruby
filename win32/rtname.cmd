@echo off
set rt=
set rtver=
set osver=
for /f "usebackq" %%I in (`dumpbin -dependents %1 ^| findstr -r -i "\<msvcr.*\.dll$"`) do set rt=%%~nI
if "%rt%" NEQ "" goto :msvcr
for /f "usebackq" %%I in (`dumpbin -dependents %1 ^| findstr -r -i "\<vcruntime.*\.dll$"`) do set rt=%%~nI
if "%rt%" NEQ "" goto :vcruntime

(echo %0: %1 is not linked to msvcrt nor vcruntime) 1>&2
exit 1

:msvcr
for %%i in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do @call set rt=%%rt:%%i=%%i%%
if "%rt%" == "msvcrt" (
    call set rtver=60
) else (
    call set rtver=%%rt:msvcr=%%
    call set rt=msvcr%%rtver%%
    call set osver=_%%rtver%%
)
goto :exit

:vcruntime
for %%i in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do @call set rt=%%rt:%%i=%%i%%
call set rtver=%%rt:vcruntime=%%
call set rt=vcruntime%%rtver%%
call set osver=_%%rtver%%

:exit
for %%I in ("PLATFORM = $(TARGET_OS)%osver%" "RT = %rt%" "RT_VER = %rtver%") do @echo %%~I
