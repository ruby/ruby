@echo off
set rt=
set rtver=
set osver=
for /f "usebackq" %%I in (`
    dumpbin -dependents %1 ^|
    findstr -r -i -c:"\<vcruntime.*\.dll$" -c:"\<msvcr.*\.dll$"
`) do (
    set rt=%%~nI
)

for %%i in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do @(
    ::- downcase
    call set rt=%%rt:%%i=%%i%%
)

if "%rt%" == "msvcrt" (
    call set rtver=60
) else if "%rt:~0,5%" == "msvcr" (
    call set rtver=%%rt:msvcr=%%
    call set osver=_%%rtver%%
) else if "%rt:~0,9%" == "vcruntime" (
    call set rtver=%%rt:vcruntime=%%
    call set osver=_%%rtver%%
) else (
    (echo %0: %1 is not linked to msvcrt nor vcruntime) 1>&2
    exit 1
)
for %%I in (
    "PLATFORM = $(TARGET_OS)%osver%"
    "RT = %rt%"
    "RT_VER = %rtver%"
) do @(
    echo %%~I
)
