@echo off
::: Don't set environment variable in batch file other than autoexec.bat
::: to avoid "Out of environment space" problem on Windows 95/98.
::: set TMPMAKE=~tmp~.mak

echo> ~tmp~.mak ####
echo>> ~tmp~.mak conf = %0
echo>> ~tmp~.mak $(conf:\=/): nul
echo>> ~tmp~.mak 	@del ~tmp~.mak
echo>> ~tmp~.mak 	@-$(MAKE) -l$(MAKEFLAGS) -f $(@D)/setup.mak \
echo>confargs.tmp #define CONFIGURE_ARGS \
:loop
if "%1" == "" goto :end
if "%1" == "--prefix" goto :prefix
if "%1" == "--srcdir" goto :srcdir
if "%1" == "srcdir" goto :srcdir
if "%1" == "--target" goto :target
if "%1" == "target" goto :target
if "%1" == "--with-static-linked-ext" goto :extstatic
if "%1" == "--with-winsock2" goto :winsock2
if "%1" == "--program-suffix" goto :suffix
if "%1" == "--program-name" goto :installname
if "%1" == "--install-name" goto :installname
if "%1" == "--so-name" goto :soname
if "%1" == "--enable-install-doc" goto :enable-rdoc
if "%1" == "--disable-install-doc" goto :disable-rdoc
if "%1" == "--extout" goto :extout
echo %1| findstr "^--with-.*-dir$" > nul
if not errorlevel 1 goto :withdir
echo %1| findstr "^--with-.*-include$" > nul
if not errorlevel 1 goto :withdir
echo %1| findstr "^--with-.*-lib$" > nul
if not errorlevel 1 goto :withdir
if "%1" == "-h" goto :help
if "%1" == "--help" goto :help
  echo>>confargs.tmp %1 \
  shift
goto :loop
:srcdir
  echo>> ~tmp~.mak 	"srcdir=%2" \
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:prefix
  echo>> ~tmp~.mak 	"prefix=%2" \
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
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:extstatic
  echo>> ~tmp~.mak 	"EXTSTATIC=static" \
  echo>>confargs.tmp %1 \
  shift
goto :loop
:winsock2
  echo>> ~tmp~.mak 	"USE_WINSOCK2=1" \
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
:extout
  echo>> ~tmp~.mak 	"EXTOUT=%2" \
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:withdir
  echo>>confargs.tmp %1=%2 \
  shift
  shift
goto :loop
:help
  echo Configuration:
  echo   --help                  display this help
  echo   --srcdir=DIR            find the sources in DIR [configure dir or `..']
  echo Installation directories:
  echo   --prefix=PREFIX         install files in PREFIX (ignored currently)
  echo System types:
  echo   --target=TARGET         configure for TARGET [i386-mswin32]
  echo Optional Package:
  echo   --with-winsock2         link winsock2
  echo   --with-static-linked-ext link external modules statically
  echo   --enable-install-doc    install rdoc indexes during install
  del *.tmp
  del ~tmp~.mak
goto :exit
:end
echo>> ~tmp~.mak 	WIN32DIR=$(@D:\=/)
echo.>>confargs.tmp
echo>confargs.c #define $ $$ 
type>>confargs.c confargs.tmp
echo>>confargs.c configure_args = CONFIGURE_ARGS
echo>>confargs.c #undef $
cl -EP confargs.c >> ~tmp~.mak 2>nul
del *.tmp > nul
nmake -alf ~tmp~.mak
:exit
