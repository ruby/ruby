#!/usr/bin/env ruby

require 'getopts'
require 'openssl'

include OpenSSL

def usage
  myname = File::basename($0)
  $stderr.puts <<EOS
Usage: #{myname} name [keypair_file]
  name ... ex. /C=JP/O=RRR/OU=CA/CN=NaHi/emailAddress=nahi@example.org
EOS
  exit
end

getopts nil, "key:", "csrout:", "keyout:"
keypair_file = $OPT_key
csrout = $OPT_csrout || "csr.pem"
keyout = $OPT_keyout || "keypair.pem"

name_str = ARGV.shift or usage()

$stdout.sync = true

name_ary = name_str.scan(/\s*([^\/,]+)\s*/).collect { |i| i[0].split("=") }
p name_ary
name = X509::Name.new(name_ary)

keypair = nil
if keypair_file
  keypair = PKey::RSA.new(File.read(keypair_file))
else
  keypair = PKey::RSA.new(1024) { putc "." }
  puts
  puts "Writing #{keyout}..."
  File.open(keyout, "w", 0400) do |f|
    f << keypair.to_pem
  end
end

puts "Generating CSR for #{name_ary.inspect}"

req = X509::Request.new
req.subject = name
req.public_key = keypair.public_key
req.sign(keypair, Digest::SHA1.new)

puts "Writing #{csrout}..."
File.open(csrout, "w") do |f|
  f << req.to_pem
end
