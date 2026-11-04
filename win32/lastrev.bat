@echo off
@setlocal EnableExtensions DisableDelayedExpansion || exit /b -1

for %%I in (%0) do set "progname=%%~nI"

if not defined git (set "git=git")
if not defined gitdir (set "gitdir=.")
set "head=HEAD"
set "width=10"
set "date_type=cd"
goto :optloop

:usage
    for %%I in (
        "usage: %progname% [options] [working-directory [head]]"
        "options:"
        "  -g, --git=git-command         specify the git command[%git%]"
        "  -d, --date=author|committer   specify date type"
        "  -w, --width=width             abbreviation width [default=%width%]"
    ) do echo.%%~I
    exit %1
:die
    for %%I in (%1) do (echo %progname%: %%~I) 1>&2
    call :usage 1 1>&2

:optloop
set "opt=%1"
if not defined opt (goto :optend)
if not "%opt:~0,1%" == "-" (goto :optend)
if "%opt%" == "--" (shift /1 & goto :optend)
    shift
    if not "%opt:~0,2%" == "--" goto :shortopt
        for /f "delims== tokens=1,*" %%I in ("%opt%") do (set "opt=%%I" & set "optarg=%%J")
    goto :eachopt
    :shortopt
        set "optarg=%opt:~2%"
        set "opt=%opt:~0,2%"
        if defined optarg goto :have_optarg
            set "optarg=%1"
            if not defined optarg (
                call :die "Missing argument for %opt%"
            )
            if "%optarg:~0,1%" == "-" (set optarg=) else (shift)
            goto :eachopt
        :have_optarg
            if "%opt%" == "-g" (set "opt=--git" & goto :eachopt)
            if "%opt%" == "-d" (set "opt=--date" & goto :eachopt)
            if "%opt%" == "-w" (set "opt=--width" & goto :eachopt)
            if "%opt%" == "-h" (set "opt=--help" & goto :eachopt)
            call :die "Unknown option %opt"
        ::-
    :eachopt
    if defined optarg goto :havearg
        set "optarg=%1"
        if "%optarg:~0,1%" == "-" (set "optarg=") else (shift)
    :havearg
    if "%opt%" == "--git" (
        set "git=%optarg%"
        goto :optloop
    )
    if "%opt%" == "--date" (
        ((echo author) | findstr -b -l -c:"%optarg%" > nul) && (set "date_type=ad" & goto :optloop)
        ((echo committer) | findstr -b -l -c:"%optarg%" > nul) && (set "date_type=cd" & goto :optloop)
        call :die "Unknown date %optarg%"
    )
    if "%opt%" == "--width" (
        set /a "width=%optarg%"
        goto :optloop
    )
    if "%opt%" == "--debug" (
        set "PROMPT=$E[94m+$E[m$S"
        echo on
        goto :optloop
    )
    if "%opt%" == "--help" (
        call :usage
    )
    call :die "Unknown option: %1"

:optend

if not defined git goto :EOF

if not "%1" == "" (set "gitdir=%1")
if not "%2" == "" (set "head=%2")

set TZ=UTC

(for /f "usebackq tokens=1" %%I in (
    `%git% -C "%gitdir%" symbolic-ref --short %head%`
) do set branch=%%I) 2> nul
if not defined branch (
   set "branch=%head%"
)

for /f "usebackq tokens=1-6" %%A in (
    `%git% -C "%gitdir%" log -1 --no-show-signature "--abbrev=%width%" ^
     "--date=format-local:%%FT%%TZ %%Y %%m %%d" "--format=%%h %%H %%%date_type%" "%head%" --`
) do (
    set rev=%%A
    set full=%%B
    set dt=%%C
    set yy=%%D
    set /a mm=1%%E %% 100
    set /a dd=1%%F %% 100
)

if "%rev%" == "" goto :EOF

echo #define RUBY_REVISION "%rev%"
echo #define RUBY_FULL_REVISION "%full%"
echo #define RUBY_BRANCH_NAME "%branch%"
echo #define RUBY_RELEASE_DATETIME "%dt%"
echo #define RUBY_RELEASE_YEAR %yy%
echo #define RUBY_RELEASE_MONTH %mm%
echo #define RUBY_RELEASE_DAY %dd%

@endlocal
