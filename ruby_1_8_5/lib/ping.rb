#
# ping.rb -- check a host for upness
#

require 'timeout'
require "socket"

#= SYNOPSIS
#
#   require 'ping'
#   
#   puts "'jimmy' is alive and kicking" if Ping.pingecho('jimmy', 10)
#
#= DESCRIPTION
#
# This module contains routines to test for the reachability of remote hosts.
# Currently the only routine implemented is pingecho(). 
#
# pingecho() uses a TCP echo (_not_ an ICMP echo) to determine if the
# remote host is reachable. This is usually adequate to tell that a remote
# host is available to rsh(1), ftp(1), or telnet(1) to.
#
#= WARNING
#
# pingecho() may block for a long period if name resolution is slow.  Require
# 'resolv-replace' to use non-blocking name resolution.
#
module Ping

  # return true if we can open a connection to the hostname or IP address
  # +host+ on port +service+ (which defaults to the "echo" port) waiting up to
  # +timeout+ seconds.
  def pingecho(host, timeout=5, service="echo")
    begin
      timeout(timeout) do
	s = TCPSocket.new(host, service)
	s.close
      end
    rescue Errno::ECONNREFUSED
      return true
    rescue Timeout::Error, StandardError
      return false
    end
    return true
  end
  module_function :pingecho
end

if $0 == __FILE__
  host = ARGV[0]
  host ||= "localhost"
  printf("%s alive? - %s\n", host,  Ping::pingecho(host, 5))
end
