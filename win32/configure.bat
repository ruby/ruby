@echo off
@setlocal EnableExtensions DisableDelayedExpansion || exit /b -1
set PROMPT=$E[94m+$E[m$S
goto :main

:set
set %*
exit /b

:shift
call %~dp0shellsplit.cmd
set "argv1=%argv2%"
set "argv2=%argv%"
if not defined argv1 if defined argv2 goto :shift
exit /b

:take_arg
if defined arg exit /b
if not defined argv2 exit /b
if not "%argv2:~0,1%"=="-" (set "arg=%argv2%" & call :shift)
exit /b

:main
if "%~dp0" == "%CD%\" (
    echo don't run in win32 directory.
    exit /b 999
) else if "%~0" == "%~nx0" (
    set "WIN32DIR=%~$PATH:0"
) else if "%~0" == "%~n0" (
    set "WIN32DIR=%~$PATH:0"
) else (
    set "WIN32DIR=%~0"
)

set "WIN32DIR=%WIN32DIR:\=/%:/:"
call :set "WIN32DIR=%%WIN32DIR:%~x0:/:=:/:%%"
call :set "WIN32DIR=%%WIN32DIR:/%~n0:/:=:/:%%"
set "WIN32DIR=%WIN32DIR:~0,-3%"

set configure=%~0
set args=%*
set target=
set optdirs=
set pathlist=
set config_make=confargs~%RANDOM%.mak
set confargs=%config_make:.mak=.sub%
set debug_configure=
echo>%config_make% # CONFIGURE
type nul > %confargs%
:loop
call :shift
if not defined argv1 goto :end
for /f "delims== tokens=1,*" %%I in (" %argv1% ") do ((set "opt=%%I") && (set "arg=%%J"))
  set "opt=%opt:~1%"
  if defined arg (
    set "eq=="
    set "arg=%arg:~0,-1%"
  ) else (
    set "eq="
    set "opt=%opt:~0,-1%"
  )
  if "%opt%"=="" (
    echo 1>&2 %configure%: assignment for empty variable name %argv1%
    exit /b 1
  )
  if "%opt%" == "--debug-configure" (
    echo on
    set "debug_configure=yes"
    goto :loop ;
  )
  if "%opt%" == "--no-debug-configure" (
    echo off
    set "debug_configure="
    goto :loop ;
  )
  if "%opt%" == "--prefix" goto :dir
  if "%opt%" == "srcdir" set "opt=--srcdir"
  if "%opt%" == "--srcdir" goto :dir
  if "%opt%" == "--target" goto :target
  if "%opt%" == "target" goto :target
  if "%opt:~0,10%" == "--program-" goto :program_name
  if "%opt%" == "--install-name" (set "var=RUBY_INSTALL_NAME" & goto :name)
  if "%opt%" == "--so-name" (set "var=RUBY_SO_NAME" & goto :name)
  if "%opt%" == "--extout" goto :extout
  if "%opt%" == "--path" goto :path
  if "%opt:~0,9%" == "--enable-" (set "enable=yes" & goto :enable)
  if "%opt:~0,10%" == "--disable-" (set "enable=no" & goto :enable)
  if "%opt:~0,10%" == "--without-" goto :withoutarg
  if "%opt:~0,7%" == "--with-" goto :witharg
  if "%opt%" == "-h" goto :help
  if "%opt%" == "--help" goto :help
  if "%opt:~0,1%" == "-" (
    goto :unknown_opt
  )
  if "%eq%" == "=" (
    set "var=%opt%"
    goto :name
  )
  set "arg=%opt%"
  set "eq=="
  set "opt=--target"
  set "target=%arg%"
:loopend
  if not "%arg%" == "" (
    echo>>%confargs%  "%opt%=%arg:$=$$%" \
  ) else (
    echo>>%confargs%  "%opt%%eq%" \
  )
goto :loop ;
:target
  if "%eq%" == "" call :take_arg
  if "%arg%" == "" (
    echo 1>&2 %configure%: missing argument for %opt%
    exit /b 1
  )
  set "target=%arg%"
  set "opt=--target"
  echo>>%confargs%  "--target=%arg:$=$$%" \
goto :loop ;
:program_name
  for /f "delims=- tokens=1,*" %I in ("%opt%") do set "var=%%J"
  if "%var%" == "prefix" (set "var=PROGRAM_PREFIX" & goto :name)
  if "%var%" == "suffix" (set "var=PROGRAM_SUFFIX" & goto :name)
  if "%var%" == "name" (set "var=RUBY_INSTALL_NAME" & goto :name)
  if "%var%" == "transform-name" (
    echo.1>&2 %configure%: --program-transform-name option is not supported
    exit /b 1
  )
goto :unknown_opt
:name
  if "%eq%" == "" call :take_arg
  echo>> %config_make% %var% = %arg%
goto :loopend ;
:dir
  if "%eq%" == "" call :take_arg
  if defined arg set "arg=%arg:\=/%"
  echo>> %config_make% %opt:~2% = %arg%
goto :loopend ;
:enable
  if %enable% == yes (
    if "%eq%" == "" call :take_arg
    set "feature=%opt:~9%"
  ) else (
    set "feature=%opt:~10%"
  )
  if %enable% == yes if defined arg (set "enable=%arg%")
  if "%feature%" == "install-doc" (
    echo>> %config_make% RDOCTARGET = %enable:yes=r%doc
  )
  if "%feature%" == "install-static-library" (
    echo>> %config_make% INSTALL_STATIC_LIBRARY = %enable%
  )
  if "%feature%" == "debug-env" (
    echo>> %config_make% ENABLE_DEBUG_ENV = %enable%
  )
  if "%feature%" == "devel" (
    echo>> %config_make% RUBY_DEVEL = %enable%
  )
  if "%feature%" == "rubygems" (
     echo>> %config_make% USE_RUBYGEMS = %enable%
  )
goto :loopend ;
:withoutarg
  echo>>%confargs%  "%opt%" \
  if "%opt%" == "--without-baseruby" goto :nobaseruby
  if "%opt%" == "--without-git" goto :nogit
  if "%opt%" == "--without-ext" goto :witharg
  if "%opt%" == "--without-extensions" goto :witharg
goto :loop ;
:witharg
  if "%opt%" == "--with-static-linked-ext" goto :extstatic
  if "%eq%" == "" call :take_arg
  if not "%arg%" == "" (
    echo>>%confargs%  "%opt%=%arg:$=$$%" \
  ) else (
    echo>>%confargs%  "%opt%%eq%" \
  )
  if "%opt%" == "--with-baseruby" goto :baseruby
  if "%opt%" == "--with-ntver" goto :ntver
  if "%opt%" == "--with-libdir" goto :libdir
  if "%opt%" == "--with-git" goto :git
  if "%opt%" == "--with-opt-dir" goto :opt-dir
  if "%opt%" == "--with-gmp-dir" goto :opt-dir
  if "%opt%" == "--with-gmp" goto :gmp
  if "%opt%" == "--with-destdir" goto :destdir
goto :loop ;
:ntver
  ::- For version constants, see
  ::- https://learn.microsoft.com/en-us/cpp/porting/modifying-winver-and-win32-winnt#remarks
  if "%eq%" == "" (set "NTVER=%~1" & call :shift) else (set "NTVER=%arg%")
  if /i not "%NTVER:~0,2%" == "0x" if /i not "%NTVER:~0,13%" == "_WIN32_WINNT_" (
    for %%i in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
      call :set NTVER=%%NTVER:%%i=%%i%%
    )
    call :set NTVER=_WIN32_WINNT_%%NTVER%%
  )
  echo>> %config_make% NTVER = %NTVER%
goto :loopend ;
:extout
  if "%eq%" == "" call :take_arg
  if not "%arg%" == ".ext" (echo>> %config_make% EXTOUT = %arg%)
goto :loopend ;
:path
  if "%eq%" == "" call :take_arg
  set "pathlist=%pathlist%%arg:\=/%;"
goto :loopend ;
:extstatic
  if "%eq%" == "" (set "arg=static")
  echo>> %config_make% EXTSTATIC = %arg%
goto :loopend ;
:baseruby
  echo>> %config_make% HAVE_BASERUBY = yes
  echo>> %config_make% BASERUBY = %arg%
goto :loop ;
:nobaseruby
  echo>> %config_make% HAVE_BASERUBY = no
  echo>> %config_make% BASERUBY =
goto :loop ;
:libdir
  echo>> %config_make% libdir_basename = %arg%
goto :loop ;
:git
  echo>> %config_make% GIT = %arg%
goto :loop ;
:nogit
  echo>> %config_make% GIT = never-use
  echo>> %config_make% HAVE_GIT = no
goto :loop ;
:gmp
  echo>> %config_make% WITH_GMP = yes
goto :loop ;
:destdir
  echo>> %config_make% DESTDIR = %arg%
goto :loop ;
:opt-dir
  if "%arg%" == "" (
    echo 1>&2 %configure%: missing argument for %opt%
    exit /b 1
  )
  :optdir-loop
  for /f "delims=; tokens=1,*" %%I in ("%arg%") do (set "d=%%I" & set "arg=%%J")
    pushd %d:/=\% 2> nul && (
      call :set "optdirs=%optdirs%;%%CD:\=/%%"
      popd
    ) || (
      set "optdirs=%optdirs%;%d:\=/%"
    )
  if not "%arg%" == "" goto :optdir-loop
goto :loop ;
:help
  echo Configuration:
  echo   --help                  display this help
  echo   --srcdir=DIR            find the sources in DIR [configure dir or '..']
  echo Installation directories:
  echo   --prefix=PREFIX         install files in PREFIX [/usr]
  echo System types:
  echo   --target=TARGET         configure for TARGET [i386-mswin32]
  echo Optional Package:
  echo   --with-baseruby=RUBY    use RUBY as baseruby [ruby]
  echo   --with-static-linked-ext link external modules statically
  echo   --with-ext="a,b,..."    use extensions a, b, ...
  echo   --without-ext="a,b,..." ignore extensions a, b, ...
  echo   --with-opt-dir="DIR-LIST" add optional headers and libraries directories separated by ';'
  echo   --disable-install-doc   do not install rdoc indexes during install
  echo   --with-ntver=0xXXXX     target NT version (shouldn't use with old SDK)
  echo   --with-ntver=_WIN32_WINNT_XXXX
  echo   --with-ntver=XXXX       same as --with-ntver=_WIN32_WINNT_XXXX
  echo Note that parameters containing spaces must be enclosed within double quotes.
  del %confargs% %config_make%
goto :EOF
:unknown_opt
  (
    echo %configure%: unknown option %opt%
    echo Try --help option.
  ) 1>&2
  exit /b 1
:end
if "%debug_configure%" == "yes" (type %confargs%)
if defined optdirs (echo>>%config_make% optdirs = %optdirs:~1%)
(
  echo.
  echo configure_args = \
  type %confargs%
  echo # configure_args

  echo.
  echo !if "$(optdirs)" != ""
  for %%I in ("$(optdirs:\=/)" "$(optdirs:/;=;)") do @echo optdirs = %%~I
  echo XINCFLAGS = -I"$(optdirs:;=/include" -I")/include"
  echo XLDFLAGS = -libpath:"$(optdirs:;=/lib" -libpath:")/lib"
  echo !endif

  if not "%pathlist%" == "" (
    echo.
    call echo PATH = %%pathlist:;=/bin;%%$^(PATH^)
    call echo INCLUDE = %%pathlist:;=/include;%%$^(INCLUDE^)
    call echo LIB = %%pathlist:;=/lib;%%$^(LIB^)
  )
) >> %config_make%

del %confargs%
if "%debug_configure%" == "yes" (type %config_make%)

nmake -al -f %WIN32DIR%/setup.mak "WIN32DIR=%WIN32DIR%" ^
    config_make=%config_make% ^
    MAKEFILE=Makefile.new MAKEFILE_BACK=Makefile.old MAKEFILE_NEW=Makefile ^
    %target%
set error=%ERRORLEVEL%
if exist %config_make% del /q %config_make%
