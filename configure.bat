@echo off
sed -f top.sed < Makefile.in > Makefile
sed -f top.sed < ext/extmk.rb.in > ext\extmk.rb
copy ext\Setup.dj ext\Setup
copy config_h.dj config.h
if not (%OS%) == (Windows_NT) goto LFN
    copy missing\vsnprintf.c missing\vsnprint.c
    copy config_s.dj config.sta
goto end
:LFN
    copy config_s.dj config.status
:end
