@echo off
grep -qs MAJOR top.sed
if errorlevel 1 goto seen
if errorlevel 0 goto not_seen
:seen
  sed -n "/VERSION /s/[^0-9.]//gp" < version.h > version.out
  cut -d. -f1 version.out > major.out
  cut -d. -f2 version.out > minor.out
  cut -d. -f3 version.out > teeny.out
  sed "s/^/s,@MAJOR@,/;s/$/,/g" major.out >> top.sed
  sed "s/^/s,@MINOR@,/;s/$/,/g" minor.out >> top.sed
  sed "s/^/s,@TEENY@,/;s/$/,/g" teeny.out >> top.sed
  rm version.out major.out minor.out teeny.out
:not_seen
sed -f top.sed < Makefile.in > Makefile
sed -f top.sed < ext\extmk.rb.in > ext\extmk.rb
copy ext\Setup.dj ext\Setup
copy config_h.dj config.h
if not (%OS%) == (Windows_NT) goto LFN
    copy missing\vsnprintf.c missing\vsnprint.c
    copy config_s.dj config.sta
goto end
:LFN
    copy config_s.dj config.status
:end
