@echo off
::: Don't set environment variable in batch file other than autoexec.bat
::: to avoid "Out of environment space" problem on Windows 95/98.
::: set TMPMAKE=~tmp~.mak

echo> ~tmp~.mak ####
echo>> ~tmp~.mak conf = %0
echo>> ~tmp~.mak $(conf:\=/): nul
echo>> ~tmp~.mak  @del ~tmp~.mak
echo>> ~tmp~.mak  make -Dbcc32dir="$(@D)" -f$(@D)/setup.mak %1
make -s -f ~tmp~.mak
