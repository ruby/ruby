@echo off
set rt=
set rtver=
set osver=
for /f "usebackq" %%I in (`dumpbin -dependents %1 ^| findstr -r -i "\<msvcr.*\.dll$"`) do set rt=%%~nI
if "%rt%" == "" (
    (echo %0: %1 is not linked to msvcrt) 1>&2
    exit 1
)
for %%i in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do @call set rt=%%rt:%%i=%%i%%
if "%rt%" == "msvcrt" (
    call set rtver=60
) else (
    call set rtver=%%rt:msvcr=%%
    call set rt=msvcr%%rtver%%
    call set osver=_%%rtver%%
)
for %%I in ("PLATFORM = $(TARGET_OS)%osver%" "RT = %rt%" "RT_VER = %rtver%") do @echo %%~I
