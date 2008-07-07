#!/usr/bin/env ruby

require 'net/https'
require 'getopts'

getopts nil, 'C:'

ca_path = $OPT_C

uri = URI.parse(ARGV[0])
if proxy = ENV['HTTP_PROXY']
  prx_uri = URI.parse(proxy)
  prx_host = prx_uri.host
  prx_port = prx_uri.port
end

h = Net::HTTP.new(uri.host, uri.port, prx_host, prx_port)
h.set_debug_output($stderr) if $DEBUG
if uri.scheme == "https"
  h.use_ssl = true
  if ca_path
    h.verify_mode = OpenSSL::SSL::VERIFY_PEER
    h.ca_path = ca_path
  else
    $stderr.puts "!!! WARNING: PEER CERTIFICATE WON'T BE VERIFIED !!!"
  end
end

path = uri.path.empty? ? "/" : uri.path
h.get2(path){|resp|
  STDERR.puts h.peer_cert.inspect if h.peer_cert
  print resp.body
}
