all:

regen_certs:
	touch server.key
	make server.crt

cacert.pem: server.key
	openssl req -new -x509 -days 1825 -key server.key -out cacert.pem -text -subj "/C=JP/ST=Shimane/L=Matz-e city/O=Ruby Core Team/CN=Ruby Test CA/emailAddress=security@ruby-lang.org"

server.csr:
	openssl req -new -key server.key -out server.csr -text -subj "/C=JP/ST=Shimane/O=Ruby Core Team/OU=Ruby Test/CN=localhost"

server.crt: server.csr cacert.pem
	openssl x509 -days 1825 -CA cacert.pem -CAkey server.key -set_serial 00 -in server.csr -req -text -out server.crt
	rm server.csr
