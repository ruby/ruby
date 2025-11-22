#!/bin/sh
# Installs Ruby into custom /opt/rubies/ prefix.

if [ $# -eq 1 ]
then
 build_name=$1
 prefix=/opt/rubies/$build_name
else
 echo "Please name the ruby build with the first program argument."
 exit 1
fi

echo "Installing dependencies..." &&\
 brew install autoconf openssl libyaml ruby &&\
 echo "Done installing dependencies."

echo "Starting..." &&\
 mkdir -p build/ &&\
 cd build &&\
 ../autogen.sh &&\
 ../configure\
 --prefix=${prefix}\
 --with-openssl-dir=$(brew --prefix openssl)\
 --with-libyaml-dir=$(brew --prefix libyaml)\
 --with-baseruby=$(brew --prefix ruby) &&\
 make install &&\
 cd - &&\
 echo "Done."
