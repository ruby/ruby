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
:end
echo>> ~tmp~.mak 	WIN32DIR=$(@D)
nmake -alf ~tmp~.mak
