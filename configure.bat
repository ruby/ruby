@echo off
sed -f top.sed Makefile.in >Makefile
sed -f top.sed ext/extmk.rb.in > ext\extmk.rb
copy ext\Setup.dj ext\Setup
copy config_h.dj config.h
copy config_s.dj config.status
