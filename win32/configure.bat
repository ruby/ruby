@echo off
::: Don't set environment variable in batch file other than autoexec.bat
::: to avoid "Out of environment space" problem on Windows 95/98.
::: set TMPMAKE=~tmp~.mak

echo> ~tmp~.mak ####
echo>> ~tmp~.mak conf = %0
echo>> ~tmp~.mak $(conf:\=/): nul
echo>> ~tmp~.mak 	@del ~tmp~.mak
echo>> ~tmp~.mak 	@-$(MAKE) -l$(MAKEFLAGS) -f $(@D)/setup.mak \
:loop
if "%1" == "" goto :end
if "%1" == "--srcdir" goto :srcdir
if "%1" == "srcdir" goto :srcdir
if "%1" == "--target" goto :target
if "%1" == "target" goto :target
if "%1" == "--enable-install-doc" goto :enable-rdoc
if "%1" == "--disable-install-doc" goto :disable-rdoc
if "%1" == "-h" goto :help
if "%1" == "--help" goto :help
  echo>> ~tmp~.mak 	"%1" \
  shift
goto :loop
:srcdir
  echo>> ~tmp~.mak 	"srcdir=%2" \
  shift
  shift
goto :loop
:target
  echo>> ~tmp~.mak 	"%2" \
  shift
  shift
goto :loop
:enable-rdoc
  echo>> ~tmp~.mak 	"RDOCTARGET=install-doc" \
  shift
goto :loop
:disable-rdoc
  echo>> ~tmp~.mak 	"RDOCTARGET=install-nodoc" \
  shift
goto :loop
:help
  echo Configuration:
  echo   --help                  display this help
  echo   --srcdir=DIR            find the sources in DIR [configure dir or `..']
  echo System types:
  echo   --target=TARGET         configure for TARGET [i386-mswin32]
  echo Optional Package:
  echo   --enable-install-doc    install rdoc indexes during install
  del ~tmp~.mak
goto :exit
:end
echo>> ~tmp~.mak 	WIN32DIR=$(@D)
nmake -alf ~tmp~.mak
:exit
