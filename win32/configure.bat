@echo off
@setlocal disabledelayedexpansion
set PROMPT=$E[94m+$E[m$S
set witharg=

for %%I in (%0) do if /%%~dpI/ == /%CD%\/ (
    echo don't run in win32 directory.
    exit /b 999
)

set XINCFLAGS=
set XLDFLAGS=

set conf=%0
set pathlist=
set config_make=confargs~%RANDOM%.mak
set confargs=%config_make:.mak=.c%
echo>%config_make% # CONFIGURE
(
  echo #define $ $$ //
  echo !ifndef CONFIGURE_ARGS
  echo #define CONFIGURE_ARGS \
) >%confargs%
:loop
set opt=%1
if "%1" == "" goto :end
if "%1" == "--debug-configure" (echo on & shift & goto :loop)
if "%1" == "--no-debug-configure" (echo off & shift & goto :loop)
if "%1" == "--prefix" goto :prefix
if "%1" == "--srcdir" goto :srcdir
if "%1" == "srcdir" goto :srcdir
if "%1" == "--target" goto :target
if "%1" == "target" goto :target
if "%1" == "--with-static-linked-ext" goto :extstatic
if "%1" == "--program-prefix" goto :pprefix
if "%1" == "--program-suffix" goto :suffix
if "%1" == "--program-transform-name" goto :transform_name
if "%1" == "--program-name" goto :installname
if "%1" == "--install-name" goto :installname
if "%1" == "--so-name" goto :soname
if "%1" == "--enable-install-doc" goto :enable-rdoc
if "%1" == "--disable-install-doc" goto :disable-rdoc
if "%1" == "--enable-install-static-library" goto :enable-lib
if "%1" == "--disable-install-static-library" goto :disable-lib
if "%1" == "--enable-debug-env" goto :enable-debug-env
if "%1" == "--disable-debug-env" goto :disable-debug-env
if "%1" == "--enable-devel" goto :enable-devel
if "%1" == "--disable-devel" goto :disable-devel
if "%1" == "--enable-rubygems" goto :enable-rubygems
if "%1" == "--disable-rubygems" goto :disable-rubygems
if "%1" == "--extout" goto :extout
if "%1" == "--path" goto :path
if "%1" == "--with-baseruby" goto :baseruby
if "%1" == "--without-baseruby" goto :baseruby
if "%1" == "--with-ntver" goto :ntver
if "%1" == "--with-libdir" goto :libdir
if "%1" == "--with-git" goto :git
if "%1" == "--without-git" goto :nogit
if "%1" == "--without-ext" goto :witharg
if "%1" == "--without-extensions" goto :witharg
if "%1" == "--with-opt-dir" goto :opt-dir
if "%1" == "--with-gmp" goto :gmp
if "%1" == "--with-gmp-dir" goto :gmp-dir
if "%opt:~0,10%" == "--without-" goto :withoutarg
if "%opt:~0,7%" == "--with-" goto :witharg
if "%1" == "-h" goto :help
if "%1" == "--help" goto :help
  if "%opt:~0,1%" == "-" (
    echo>>%confargs%  %1 \
    set witharg=
  ) else if "%witharg%" == "" (
    echo>>%confargs%  %1 \
  ) else (
    echo>>%confargs% ,%1\
  )
  shift
goto :loop ;
:srcdir
  echo>> %config_make% srcdir = %~2
  echo>>%confargs% --srcdir=%2 \
  shift
  shift
goto :loop ;
:prefix
  echo>> %config_make% prefix = %~2
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:pprefix
  echo>> %config_make% PROGRAM_PREFIX = %~2
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:suffix
  echo>> %config_make% PROGRAM_SUFFIX = %~2
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:installname
  echo>> %config_make% RUBY_INSTALL_NAME = %~2
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:soname
  echo>> %config_make% RUBY_SO_NAME = %~2
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:transform_name

  shift
  shift
goto :loop ;
:target
  echo>> %config_make% target = %~2
  echo>>%confargs% --target=%2 \
  if "%~2" == "x64-mswin64" (
    echo>> %config_make% TARGET_OS = mswin64
  )
  shift
  shift
goto :loop ;
:extstatic
  echo>> %config_make% EXTSTATIC = static
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:enable-rdoc
  echo>> %config_make% RDOCTARGET = rdoc
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:disable-rdoc
  echo>> %config_make% RDOCTARGET = nodoc
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:enable-lib
  echo>> %config_make% INSTALL_STATIC_LIBRARY = yes
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:disable-lib
  echo>> %config_make% INSTALL_STATIC_LIBRARY = no
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:enable-debug-env
  echo>> %config_make% ENABLE_DEBUG_ENV = yes
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:disable-debug-env
  echo>> %config_make% ENABLE_DEBUG_ENV = no
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:enable-devel
  echo>> %config_make% RUBY_DEVEL = yes
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:disable-devel
  echo>> %config_make% RUBY_DEVEL = no
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:enable-rubygems
  echo>> %config_make% USE_RUBYGEMS = yes
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:disable-rubygems
  echo>> %config_make% USE_RUBYGEMS = no
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:ntver
  ::- For version constants, see
  ::- https://learn.microsoft.com/en-us/cpp/porting/modifying-winver-and-win32-winnt#remarks
  set NTVER=%~2
  if /i not "%NTVER:~0,2%" == "0x" if /i not "%NTVER:~0,13%" == "_WIN32_WINNT_" (
    for %%i in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
      call set NTVER=%%NTVER:%%i=%%i%%
    )
    call set NTVER=_WIN32_WINNT_%%NTVER%%
  )
  echo>> %config_make% NTVER = %NTVER%
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:extout
  if not "%~2" == ".ext" (echo>> %config_make% EXTOUT = %~2)
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:path
  set pathlist=%pathlist%%~2;
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:baseruby
  echo>> %config_make% BASERUBY = %~2
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:nobaseruby
  echo>> %config_make% HAVE_BASERUBY = no
  echo>>%confargs%  %1=%2 \
  shift
goto :loop ;
:libdir
  echo>> %config_make% libdir_basename = %~2
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:git
  echo>> %config_make% GIT = %~2
  echo>>%confargs%  %1=%2 \
  shift
  shift
goto :loop ;
:nogit
  echo>> %config_make% GIT = never-use
  echo>> %config_make% HAVE_GIT = no
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:gmp
  echo>> %config_make% WITH_GMP = yes
  echo>>%confargs%  %1=1 \
  shift
  shift
goto :loop ;
:gmp-dir
:opt-dir
  set opt=%~2
  for %%I in (%opt:;= %) do (
    set d=%%I
    call pushd %%d:/=\%% && (
      call set XINCFLAGS=%%XINCFLAGS%% -I%%CD:\=/%%/include
      call set XLDFLAGS=%%XLDFLAGS%% -libpath:%%CD:\=/%%/lib
      popd
    )
  )
:witharg
  echo>>%confargs%  %1=%2\
  set witharg=1
  shift
  shift
goto :loop ;
:withoutarg
  echo>>%confargs%  %1 \
  shift
goto :loop ;
:help
  echo Configuration:
  echo   --help                  display this help
  echo   --srcdir=DIR            find the sources in DIR [configure dir or `..']
  echo Installation directories:
  echo   --prefix=PREFIX         install files in PREFIX [/usr]
  echo System types:
  echo   --target=TARGET         configure for TARGET [i386-mswin32]
  echo Optional Package:
  echo   --with-baseruby=RUBY    use RUBY as baseruby [ruby]
  echo   --with-static-linked-ext link external modules statically
  echo   --with-ext="a,b,..."    use extensions a, b, ...
  echo   --without-ext="a,b,..." ignore extensions a, b, ...
  echo   --with-opt-dir="DIR-LIST" add optional headers and libraries directories separated by `;'
  echo   --disable-install-doc   do not install rdoc indexes during install
  echo   --with-ntver=0xXXXX     target NT version (shouldn't use with old SDK)
  echo   --with-ntver=_WIN32_WINNT_XXXX
  echo   --with-ntver=XXXX       same as --with-ntver=_WIN32_WINNT_XXXX
  echo Note that `,' and `;' need to be enclosed within double quotes in batch file command line.
  del %confargs% %config_make%
goto :exit
:end
(
  echo //
  echo configure_args = CONFIGURE_ARGS
  echo !endif
  echo #undef $
) >> %confargs%
(
  cl -EP %confargs% 2>nul | findstr "! ="
  echo.
  if NOT "%XINCFLAGS%" == "" echo XINCFLAGS = %XINCFLAGS%
  if NOT "%XLDFLAGS%" == "" echo XLDFLAGS = %XLDFLAGS%
  if NOT "%pathlist%" == "" (
    call echo PATH = %%pathlist:;=/bin;%%$^(PATH^)
    call echo INCLUDE = %%pathlist:;=/include;%%$^(INCLUDE^)
    call echo LIB = %%pathlist:;=/lib;%%$^(LIB^)
  )
) >> %config_make%
del %confargs% > nul

set setup_make=%config_make:confargs=setup%
(
  echo #### -*- makefile -*-
  echo conf = %conf%
  echo $^(conf^): nul
  echo 	@del %setup_make%
  echo 	@$^(MAKE^) -l$^(MAKEFLAGS^) -f $^(@D^)/setup.mak \
  echo 	WIN32DIR=$^(@D:\=/^) config_make=%config_make%
  echo 	-@move /y Makefile Makefile.old ^> nul 2^> nul
  echo 	@ren Makefile.new Makefile
) > %setup_make%
nmake -alf %setup_make% MAKEFILE=Makefile.new

exit /b %ERRORLEVEL%
:exit
@endlocal
