#
# ping.rb -- check a host for upness
#
#= SYNOPSIS
#
#   require 'ping'
#    print "'jimmy' is alive and kicking\n" if Ping.pingecho('jimmy', 10) ;
#
#= DESCRIPTION
#
# This module contains routines to test for the reachability of remote hosts.
# Currently the only routine implemented is pingecho(). 
#
# pingecho() uses a TCP echo (I<not> an ICMP one) to determine if the
# remote host is reachable. This is usually adequate to tell that a remote
# host is available to rsh(1), ftp(1), or telnet(1) onto.
#
#== Parameters
#
#  : hostname
#
#    The remote host to check, specified either as a hostname or as an
#    IP address.
#
#  : timeout
#
#    The timeout in seconds. If not specified it will default to 5 seconds.
#
#  : service
#
#    The service port to connect.  The default is "echo".
#
#= WARNING
#
# pingecho() uses user-level thread to implement the timeout, so it may block
# for long period if named does not respond for some reason.
#
#=end

require 'timeout'
require "socket"

module Ping
  def pingecho(host, timeout=5, service="echo")
    begin
      timeout(timeout) do
	s = TCPsocket.new(host, service)
	s.close
      end
    rescue Errno::ECONNREFUSED
      return true
    rescue
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
