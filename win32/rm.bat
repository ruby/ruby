@echo off
@setlocal EnableExtensions DisableDelayedExpansion || exit /b -1

set prog=%~n0
set dryrun=
set recursive=
set debug=
set error=0
set parent=

:optloop
if "%1" == "-f" shift
if "%1" == "-n" (shift & set "dryrun=%1" & goto :optloop)
if "%1" == "-r" (shift & set "recursive=%1" & goto :optloop)
if "%1" == "--debug" (shift & set "debug=%1" & set PROMPT=$E[34m+$E[m$S & echo on & goto :optloop)
:begin
if "%1" == "" goto :EOF
  set p=%1
  shift
  set p=%p:/=\%
  call :remove %p%
goto :begin

:remove
setlocal

::- Split %1 by '?' and '*', wildcard characters
for /f "usebackq delims=?* tokens=1*" %%I in ('%1') do (set "par=%%I" & set "sub=%%J")
if "%sub%" == "" goto :remove_plain
if "%sub:\=%" == "%sub%" goto :remove_plain
    ::- Extract the first wildcard
    set "q=%1"
    call set "q=%%q:%par%=%%"
    set q=%q:~0,1%

    ::- `delims` chars at the beginning are removed in `for`
    if "%sub:~0,1%" == "\" (
        set "sub=%sub:~1%"
        set "par=%par%%q%"
    ) else (
        for /f "usebackq delims=\\ tokens=1*" %%I in ('%sub%') do (set "par=%par%%q%%%I" & set "sub=%%J")
    )

    ::- Recursive search
    for /d %%D in (%par%) do (
        call :remove %sub% %2%%D\
    )
goto :remove_end
:remove_plain
    set p=%2%1
    if not exist "%1" goto :remove_end
    if not "%dryrun%" == "" (
        echo Removing %p:\=/%
        goto :remove_end
    )
    ::- Try `rd` first for symlink to a directory; `del` attemps to remove all
    ::- files under the target directory, instead of the symlink itself.
    (rd /q "%p%" || del /q "%p%") 2> nul && goto :remove_end

    if "%recursive%" == "-r" for /D %%I in (%p%) do (
        rd /s /q %%I || call set error=%%ERRORLEVEL%%
    )
:remove_end
endlocal & set "error=%error%" & goto :EOF
