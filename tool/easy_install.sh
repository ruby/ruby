#!/bin/sh
# Installs Ruby into custom /opt/rubies/ prefix.

if [ $# -eq 1 ]
then
 build_name=$1
 prefix=/opt/rubies/${build_name}
 export BASERUBY=$(brew --prefix ruby)/bin/ruby
else
 echo "Please name the ruby build with the first program argument."
 exit 1
fi

echo "Installing dependencies..." &&\
 brew install autoconf openssl libyaml ruby &&\
 echo "Done installing dependencies."

echo "Starting..." &&\
 ./autogen.sh &&\
 mkdir -p build/ &&\
 cd build &&\
 ../configure\
 --config-cache\
 --prefix=${prefix}\
 --with-baseruby\
 --with-libyaml-dir=$(brew --prefix libyaml)\
 --with-openssl-dir=$(brew --prefix openssl) &&\
 make &&\
 make install &&\
 cd - &&\
 echo "Done."
