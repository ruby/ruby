@echo off
::: Don't set environment variable in batch file other than autoexec.bat
::: to avoid "Out of environment space" problem on Windows 95/98.
::: set TMPMAKE=~tmp~.mak

echo> ~tmp~.mak ####
echo>> ~tmp~.mak conf = %0
echo>> ~tmp~.mak $(conf:\=/): nul
echo>> ~tmp~.mak 	@del ~tmp~.mak
echo>> ~tmp~.mak 	@-$(MAKE) -l$(MAKEFLAGS) -f $(@D)/setup.mak \
if not "%1" == "" echo>> ~tmp~.mak 	srcdir="%1" \
echo>> ~tmp~.mak 	WIN32DIR=$(@D)
nmake -alf ~tmp~.mak
