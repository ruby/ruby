#!/usr/bin/env ruby

require 'optparse'
require 'openssl'

def usage
  myname = File::basename($0)
  $stderr.puts <<EOS
Usage: #{myname} [--key keypair_file] name
  name ... ex. /C=JP/O=RRR/OU=CA/CN=NaHi/emailAddress=nahi@example.org
EOS
  exit
end

options = ARGV.getopts(nil, "key:", "csrout:", "keyout:")
keypair_file = options["key"]
csrout = options["csrout"] || "csr.pem"
keyout = options["keyout"] || "keypair.pem"

$stdout.sync = true
name_str = ARGV.shift or usage()
name = OpenSSL::X509::Name.parse(name_str)

keypair = nil
if keypair_file
  keypair = OpenSSL::PKey.read(File.read(keypair_file))
else
  keypair = OpenSSL::PKey::RSA.new(2048) { putc "." }
  puts
  puts "Writing #{keyout}..."
  File.open(keyout, "w", 0400) do |f|
    f << keypair.to_pem
  end
end

puts "Generating CSR for #{name_str}"

req = OpenSSL::X509::Request.new
req.version = 0
req.subject = name
req.public_key = keypair
req.sign(keypair, "MD5")

puts "Writing #{csrout}..."
File.open(csrout, "w") do |f|
  f << req.to_pem
end
puts req.to_text
puts req.to_pem
