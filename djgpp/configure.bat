@echo off
if exist configure.bat cd ..
if exist djgpp\version.sed goto exist
  sed -n -f djgpp\mkver.sed < version.h > djgpp\version.sed
:exist
set _conv_=-f djgpp\config.sed -f djgpp\version.sed
sed %_conv_% < Makefile.in > Makefile
sed %_conv_% < ext\extmk.rb.in > ext\extmk.rb
sed %_conv_% < djgpp\config.hin > config.h
echo LFN check > 12345678
sed -n /LFN/d 123456789 > nul
if errorlevel 2 goto LFN
    copy missing\vsnprintf.c missing\vsnprint.c > nul
    copy djgpp\config.sed config.sta > nul
goto end
:LFN
    copy djgpp\config.sed config.status > nul
:end
set _conv_=
del 12345678
echo Now you must run a make.
