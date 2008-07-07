require 'openssl'
require 'getopts'
include OpenSSL

getopts nil, "c:", "k:", "r:"

cert_file = $OPT_c
key_file  = $OPT_k
rcpt_file = $OPT_r

cert = X509::Certificate.new(File::read(cert_file))
key = PKey::RSA.new(File::read(key_file))

data  = "Content-Type: text/plain\r\n"
data << "\r\n"
data << "This is a clear-signed message.\r\n"

p7sig  = PKCS7::sign(cert, key, data, [], PKCS7::DETACHED)
smime0 = PKCS7::write_smime(p7sig)

rcpt  = X509::Certificate.new(File::read(rcpt_file))
p7enc = PKCS7::encrypt([rcpt], smime0)
print PKCS7::write_smime(p7enc)   
