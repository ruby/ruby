@echo off
sed -f top.sed Makefile.in >Makefile
sed -f top.sed ext/extmk.rb.in > ext\extmk.rb
copy ext\Setup.dj ext\Setup
copy config.dj config.h
