@echo off
copy config.h ..
copy Makefile ..
copy ruby.def ..
copy config.status ..

cd ..
echo type `nmake' to make ruby for mswin32.
