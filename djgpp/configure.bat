@echo off
set _dj_=djgpp
if exist djgpp\nul goto top
  cd ..
:top
if exist %_dj_%\version.sed goto exist
  sed -n -f %_dj_%\mkver.sed < version.h > %_dj_%\version.sed
:exist
set _convert_=-f %_dj_%\config.status -f %_dj_%\version.sed
sed %_convert_% < Makefile.in > Makefile
sed %_convert_% < ext\extmk.rb.in > ext\extmk.rb
sed %_convert_% < %_dj_%\config.hin > config.h
echo LFN check > 12345678
sed -n /LFN/d 123456789 > nul
if errorlevel 2 goto LFN
    copy missing\vsnprintf.c missing\vsnprint.c > nul
    copy %_dj_%\config.status config.sta > nul
goto end
:LFN
    copy %_dj_%\config.status config.status > nul
:end
set _dj_=
set _convert_=
del 12345678
echo Now you must run a make.
