require 'getopts'
require 'openssl'
include OpenSSL

getopts nil, "c:", "k:", "C:"

cert_file = $OPT_c
key_file  = $OPT_k
ca_path   = $OPT_C

data = $stdin.read

cert = X509::Certificate.new(File::read(cert_file))
key = PKey::RSA.new(File::read(key_file))
p7enc = PKCS7::read_smime(data)
data = p7enc.decrypt(key, cert)

store = X509::Store.new
store.add_path(ca_path)
p7sig = PKCS7::read_smime(data)
if p7sig.verify([], store)
  puts p7sig.data
end
