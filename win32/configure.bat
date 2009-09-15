@echo off
::: Don't set environment variable in batch file other than autoexec.bat
::: to avoid "Out of environment space" problem on Windows 95/98.
::: set TMPMAKE=~tmp~.mak

echo> ~tmp~.mak ####
echo>> ~tmp~.mak conf = %0
echo>> ~tmp~.mak $(conf:\=/): nul
echo>> ~tmp~.mak 	@del ~setup~.mak
echo>> ~tmp~.mak 	@-$(MAKE) -l$(MAKEFLAGS) -f $(@D)/setup.mak \
if exist pathlist.tmp del pathlist.tmp
echo>confargs.tmp #define CONFIGURE_ARGS \
:loop
if "%1" == "" goto :end
if "%1" == "--prefix" goto :prefix
if "%1" == "--srcdir" goto :srcdir
if "%1" == "srcdir" goto :srcdir
if "%1" == "--target" goto :target
if "%1" == "target" goto :target
if "%1" == "--with-static-linked-ext" goto :extstatic
if "%1" == "--program-prefix" goto :pprefix
if "%1" == "--program-suffix" goto :suffix
if "%1" == "--program-name" goto :installname
if "%1" == "--install-name" goto :installname
if "%1" == "--so-name" goto :soname
if "%1" == "--enable-install-doc" goto :enable-rdoc
if "%1" == "--disable-install-doc" goto :disable-rdoc
if "%1" == "--enable-win95" goto :enable-win95
if "%1" == "--disable-win95" goto :disable-win95
if "%1" == "--extout" goto :extout
if "%1" == "--path" goto :path
if "%1" == "--with-baseruby" goto :baseruby
if "%1" == "-h" goto :help
if "%1" == "--help" goto :help
  echo>>confargs.tmp %1 \
  shift
goto :loop
:srcdir
  echo>> ~tmp~.mak 	"srcdir=%2" \
  echo>>confargs.tmp --srcdir=%2 \
  shift
  shift
goto :loop
:prefix
  echo>> ~tmp~.mak 	"prefix=%2" \
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:pprefix
  echo>> ~tmp~.mak 	"RUBY_PREFIX=%2" \
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:suffix
  echo>> ~tmp~.mak 	"RUBY_SUFFIX=%2" \
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:installname
  echo>> ~tmp~.mak 	"RUBY_INSTALL_NAME=%2" \
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:soname
  echo>> ~tmp~.mak 	"RUBY_SO_NAME=%2" \
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:target
  echo>> ~tmp~.mak 	"%2" \
  echo>>confargs.tmp --target=%2 \
  if "%2" == "x64-mswin64" goto target2
  if NOT "%2" == "ia64-mswin64" goto target3
:target2
  echo>> ~tmp~.mak 	"TARGET_OS=mswin64" \
:target3
  shift
  shift
goto :loop
:extstatic
  echo>> ~tmp~.mak 	"EXTSTATIC=static" \
  echo>>confargs.tmp %1 \
  shift
goto :loop
:enable-rdoc
  echo>> ~tmp~.mak 	"RDOCTARGET=rdoc" \
  echo>>confargs.tmp %1 \
  shift
goto :loop
:disable-rdoc
  echo>> ~tmp~.mak 	"RDOCTARGET=nodoc" \
  echo>>confargs.tmp %1 \
  shift
goto :loop
:enable-win95
  echo>> ~tmp~.mak 	"ENABLE_WIN95=yes" \
  echo>>confargs.tmp %1 \
  shift
goto :loop
:disable-win95
  echo>> ~tmp~.mak 	"ENABLE_WIN95=no" \
  echo>>confargs.tmp %1 \
  shift
goto :loop
:extout
  echo>> ~tmp~.mak 	"EXTOUT=%2" \
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:path
  echo>>pathlist.tmp %2;\
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:baseruby
  echo>> ~tmp~.mak 	"BASERUBY=%2" \
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
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
  echo   --disable-install-doc   do not install rdoc indexes during install
  echo   --enable-win95          enable win95 support
  del *.tmp
  del ~tmp~.mak
goto :exit
:end
echo>> ~tmp~.mak 	WIN32DIR=$(@D)
echo.>>confargs.tmp
echo>confargs.c #define $ $$ 
echo>>confargs.c !ifndef CONFIGURE_ARGS
type>>confargs.c confargs.tmp
echo>>confargs.c configure_args = CONFIGURE_ARGS
echo>>confargs.c !endif
echo>>confargs.c #undef $
if exist pathlist.tmp echo>>confargs.c #define PATH_LIST \
if exist pathlist.tmp type>>confargs.c pathlist.tmp
if exist pathlist.tmp echo.>>confargs.c
if exist pathlist.tmp echo>>confargs.c pathlist = PATH_LIST
cl -EP confargs.c > ~setup~.mak 2>nul
if exist pathlist.tmp echo>>~setup~.mak PATH = $(pathlist:;=/bin;)$(PATH)
if exist pathlist.tmp echo>>~setup~.mak INCLUDE = $(pathlist:;=/include;)
if exist pathlist.tmp echo>>~setup~.mak LIB = $(pathlist:;=/lib;)
type>>~setup~.mak ~tmp~.mak
del *.tmp > nul
del ~tmp~.mak > nul
echo>>~setup~.mak 	@if exist Makefile.old del Makefile.old
echo>>~setup~.mak 	@if exist Makefile ren Makefile Makefile.old
echo>>~setup~.mak 	@ren Makefile.new Makefile
nmake -alf ~setup~.mak MAKEFILE=Makefile.new
:exit
