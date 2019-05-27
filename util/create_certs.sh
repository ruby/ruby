#!/bin/sh

# cp /etc/ssl/openssl.cnf . # copied from OpenSSL 1.1.1b source

rm -rf demoCA/ server/ client/ 

mkdir demoCA demoCA/private demoCA/newcerts
touch demoCA/index.txt
echo 00 > demoCA/serial
openssl genrsa -out demoCA/private/cakey.pem 2048
openssl req -new -key demoCA/private/cakey.pem -out demoCA/careq.pem -subj "/C=JP/ST=Tokyo/O=RubyGemsTest/CN=CA"
openssl ca -batch -config openssl.cnf -extensions v3_ca -out demoCA/cacert.pem -startdate 090101000000Z -enddate 491231235959Z -batch -keyfile demoCA/private/cakey.pem -selfsign -infiles demoCA/careq.pem

mkdir server
openssl genrsa -out server/server.key 2048
openssl req -new -key server/server.key -out server/csr.pem -subj "/C=JP/ST=Tokyo/O=RubyGemsTest/CN=localhost"
openssl ca -batch -config openssl.cnf -startdate 090101000000Z -enddate 491231235959Z -in server/csr.pem -keyfile demoCA/private/cakey.pem -cert demoCA/cacert.pem -out server/cert.pem

mkdir client
openssl genrsa -out client/client.key 2048
openssl req -config openssl.cnf -new -key client/client.key -out client/csr.pem -subj "/C=JP/ST=Tokyo/O=RubyGemsTest/CN=client"
openssl ca -batch -config openssl.cnf -startdate 090101000000Z -enddate 491231235959Z -in client/csr.pem -keyfile demoCA/private/cakey.pem -cert demoCA/cacert.pem -out client/cert.pem

cp demoCA/cacert.pem $(git rev-parse --show-toplevel)/test/rubygems/ca_cert.pem
cp server/cert.pem $(git rev-parse --show-toplevel)/test/rubygems/ssl_cert.pem
cp server/server.key $(git rev-parse --show-toplevel)/test/rubygems/ssl_key.pem
cat client/cert.pem client/client.key > $(git rev-parse --show-toplevel)/test/rubygems/client.pem
