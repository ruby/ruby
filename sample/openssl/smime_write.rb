require 'openssl'
require 'optparse'

options = ARGV.getopts("c:k:r:")

cert_file = options["c"]
key_file  = options["k"]
rcpt_file = options["r"]

cert = OpenSSL::X509::Certificate.new(File::read(cert_file))
key = OpenSSL::PKey::read(File::read(key_file))

data  = "Content-Type: text/plain\r\n"
data << "\r\n"
data << "This is a clear-signed message.\r\n"

p7sig  = OpenSSL::PKCS7::sign(cert, key, data, [], OpenSSL::PKCS7::DETACHED)
smime0 = OpenSSL::PKCS7::write_smime(p7sig)

rcpt  = OpenSSL::X509::Certificate.new(File::read(rcpt_file))
p7enc = OpenSSL::PKCS7::encrypt([rcpt], smime0)
print OpenSSL::PKCS7::write_smime(p7enc)
