@echo off

if "%1"==""     goto error
if "%2"==""     goto error

if exist make.bat @del make.bat

if "%1"=="MIPS" goto mips
if "%1"=="ARM"  goto arm
if "%1"=="SH3"  goto sh3
if "%1"=="SH4"  goto sh4

:mips

copy config config.h
echo #define RUBY_PLATFORM "mips-mswince" >> config.h
echo #define RUBY_ARCHLIB "/lib/ruby/1.8/mips-mswince" >> config.h
echo #define RUBY_SITE_ARCHLIB "/lib/ruby/site_ruby/1.8/mips-mswince" >> config.h

if "%2"=="HPC2K"  goto mipshpc2k
if "%2"=="PPC"    goto mipsppc
if "%2"=="HPCPRO" goto mipshpcpro

:mipshpc2k
  echo nmake /f "dll.mak" CFG=MIPS >> make.bat
  echo nmake /f "exe.mak" CFG=MIPS >> make.bat
  set path=c:\program files\microsoft embedded tools\common\evc\bin;C:\Program Files\Microsoft eMbedded Tools\EVC\WCE300\BIN
  set include=c:\windows ce tools\wce300\hpc2000\include
  set lib=C:\Windows CE Tools\wce300\hpc2000\lib\mips
  goto normalend
:mipsppc
  echo nmake /f "dll.mak" CFG=MIPS >> make.bat
  echo nmake /f "exe.mak" CFG=MIPS >> make.bat
  set path=c:\program files\microsoft embedded tools\common\evc\bin;C:\Program Files\Microsoft eMbedded Tools\EVC\WCE300\BIN
  set include=c:\windows ce tools\wce300\MS Pocket PC\include
  set lib=c:\windows ce tools\wce300\MS Pocket PC\lib\mips
  goto normalend
:mipshpcpro
  echo nmake /f "dll.mak" CFG=MIPS CESubsystem=windowsce,2.11 CEVersion=211 >> make.bat
  echo nmake /f "exe.mak" CFG=MIPS CESubsystem=windowsce,2.11 CEVersion=211 >> make.bat
  set path=c:\program files\microsoft embedded tools\common\evc\bin;C:\Program Files\Microsoft eMbedded Tools\EVC\WCE211\BIN
  set include=C:\Windows CE Tools\wce211\MS HPC Pro\include
  set lib=C:\Windows CE Tools\wce211\MS HPC Pro\lib\mips
  goto normalend

:arm

copy config config.h
echo #define RUBY_PLATFORM "arm-mswince" >> config.h
echo #define RUBY_ARCHLIB "/lib/ruby/1.8/arm-mswince" >> config.h
echo #define RUBY_SITE_ARCHLIB "/lib/ruby/site_ruby/1.8/arm-mswince" >> config.h

if "%2"=="HPC2K"  goto armhpc2k
if "%2"=="PPC"    goto armppc
if "%2"=="HPCPRO" goto armhpcpro

:armhpc2k
  echo nmake /f "dll.mak" CFG=ARM >> make.bat
  echo nmake /f "exe.mak" CFG=ARM >> make.bat
  set path=c:\program files\microsoft embedded tools\common\evc\bin;C:\Program Files\Microsoft eMbedded Tools\EVC\WCE300\BIN
  set include=c:\windows ce tools\wce300\hpc2000\include
  set lib=C:\Windows CE Tools\wce300\hpc2000\lib\arm
  goto normalend
:armppc
  echo nmake /f "dll.mak" CFG=ARM >> make.bat
  echo nmake /f "exe.mak" CFG=ARM >> make.bat
  set path=c:\program files\microsoft embedded tools\common\evc\bin;C:\Program Files\Microsoft eMbedded Tools\EVC\WCE300\BIN
  set include=c:\windows ce tools\wce300\MS Pocket PC\include
  set lib=c:\windows ce tools\wce300\MS Pocket PC\lib\arm
  goto normalend
:armhpcpro
  echo nmake /f "dll.mak" CFG=ARM CESubsystem=windowsce,2.11 CEVersion=211 >> make.bat
  echo nmake /f "exe.mak" CFG=ARM CESubsystem=windowsce,2.11 CEVersion=211 >> make.bat
  set path=c:\program files\microsoft embedded tools\common\evc\bin;C:\Program Files\Microsoft eMbedded Tools\EVC\WCE211\BIN
  set include=C:\Windows CE Tools\wce211\MS HPC Pro\include
  set lib=C:\Windows CE Tools\wce211\MS HPC Pro\lib\arm
  goto normalend

:sh3

copy config config.h
echo #define RUBY_PLATFORM "sh3-mswince" >> config.h
echo #define RUBY_ARCHLIB "/lib/ruby/1.8/sh3-mswince" >> config.h
echo #define RUBY_SITE_ARCHLIB "/lib/ruby/site_ruby/1.8/sh3-mswince" >> config.h

if "%2"=="HPC2K"  goto error
if "%2"=="PPC"    goto sh3ppc
if "%2"=="HPCPRO" goto sh3hpcpro

:sh3ppc
  echo nmake /f "dll.mak" CFG=SH3 >> make.bat
  echo nmake /f "exe.mak" CFG=SH3 >> make.bat
  set path=c:\program files\microsoft embedded tools\common\evc\bin;C:\Program Files\Microsoft eMbedded Tools\EVC\WCE300\BIN
  set include=c:\windows ce tools\wce300\MS Pocket PC\include
  set lib=c:\windows ce tools\wce300\MS Pocket PC\lib\sh3
  goto normalend
:sh3hpcpro
  echo nmake /f "dll.mak" CFG=SH3 CESubsystem=windowsce,2.11 CEVersion=211 >> make.bat
  echo nmake /f "exe.mak" CFG=SH3 CESubsystem=windowsce,2.11 CEVersion=211 >> make.bat
  set path=c:\program files\microsoft embedded tools\common\evc\bin;C:\Program Files\Microsoft eMbedded Tools\EVC\WCE211\BIN
  set include=C:\Windows CE Tools\wce211\MS HPC Pro\include
  set lib=C:\Windows CE Tools\wce211\MS HPC Pro\lib\sh3
  goto normalend

:sh4

copy config config.h
echo #define RUBY_PLATFORM "sh4-mswince" >> config.h
echo #define RUBY_ARCHLIB "/lib/ruby/1.8/sh4-mswince" >> config.h
echo #define RUBY_SITE_ARCHLIB "/lib/ruby/site_ruby/1.8/sh4-mswince" >> config.h

if "%2"=="HPC2K"  goto error
if "%2"=="PPC"    goto error
if "%2"=="HPCPRO" goto sh4hpcpro

:sh4hpcpro
  echo nmake /f "dll.mak" CFG=SH4 CESubsystem=windowsce,2.11 CEVersion=211 >> make.bat
  echo nmake /f "exe.mak" CFG=SH4 CESubsystem=windowsce,2.11 CEVersion=211 >> make.bat
  set path=c:\program files\microsoft embedded tools\common\evc\bin;C:\Program Files\Microsoft eMbedded Tools\EVC\WCE211\BIN
  set include=C:\Windows CE Tools\wce211\MS HPC Pro\include
  set lib=C:\Windows CE Tools\wce211\MS HPC Pro\lib\sh4
  goto normalend


:error
echo ERROR. Please check arguments.
goto end

:normalend
echo configure OK. Please type ".\make.bat".
goto end

:end
