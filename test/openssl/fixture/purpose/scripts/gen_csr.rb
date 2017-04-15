#!/usr/bin/env ruby

require 'getopts'
require 'openssl'

include OpenSSL

def usage
  myname = File::basename($0)
  $stderr.puts <<EOS
Usage: #{myname} [--key keypair_file] name
  name ... ex. /C=JP/O=RRR/OU=CA/CN=NaHi/emailAddress=nahi@example.org
EOS
  exit
end

getopts nil, "key:", "csrout:", "keyout:"
keypair_file = $OPT_key
csrout = $OPT_csrout || "csr.pem"
keyout = $OPT_keyout || "keypair.pem"

$stdout.sync = true
name_str = ARGV.shift or usage()
p name_str
name = X509::Name.parse(name_str)

keypair = nil
if keypair_file
  keypair = PKey::RSA.new(File.open(keypair_file).read)
else
  keypair = PKey::RSA.new(1024) { putc "." }
  puts
  puts "Writing #{keyout}..."
  File.open(keyout, "w", 0400) do |f|
    f << keypair.to_pem
  end
end

puts "Generating CSR for #{name_str}"

req = X509::Request.new
req.version = 0
req.subject = name
req.public_key = keypair.public_key
req.sign(keypair, OpenSSL::Digest::MD5.new)

puts "Writing #{csrout}..."
File.open(csrout, "w") do |f|
  f << req.to_pem
end
