@echo off
copy config.h ..
copy Makefile ..
copy ruby.def ..
copy config.status ..
cd ..\ext
copy Setup.nt Setup
copy extmk.rb.nt extmk.rb

cd ..
echo type `nmake' to make ruby for mswin32.
