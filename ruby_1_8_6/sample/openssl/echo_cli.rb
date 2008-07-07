#!/usr/bin/env ruby

require 'socket'
require 'openssl'
require 'getopts'

getopts nil, "p:2000", "c:", "k:", "C:"

host      = ARGV[0] || "localhost"
port      = $OPT_p
cert_file = $OPT_c
key_file  = $OPT_k
ca_path   = $OPT_C

ctx = OpenSSL::SSL::SSLContext.new()
if cert_file && key_file
  ctx.cert = OpenSSL::X509::Certificate.new(File::read(cert_file))
  ctx.key  = OpenSSL::PKey::RSA.new(File::read(key_file))
end
if ca_path
  ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
  ctx.ca_path = ca_path
else
  $stderr.puts "!!! WARNING: PEER CERTIFICATE WON'T BE VERIFIED !!!"
end

s = TCPSocket.new(host, port)
ssl = OpenSSL::SSL::SSLSocket.new(s, ctx)
ssl.connect # start SSL session
ssl.sync_close = true  # if true the underlying socket will be
                       # closed in SSLSocket#close. (default: false)
while line = $stdin.gets
  ssl.write line
  print ssl.gets
end

ssl.close
