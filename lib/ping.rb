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
#= WARNING
#
# pingecho() uses user-level thread to implement the timeout, so it may block
# for long period if named does not respond for some reason.
#
#=end

module Ping
  require "socket"
  def pingecho(host, timeout=5)
    begin
      x = Thread.current
      y = Thread.start {
	sleep timeout
	x.raise RuntimeError if x.status
      }
      s = TCPsocket.new(host, "echo")
      s.close
      return TRUE
    rescue
      return FALSE;
    ensure
      Thread.kill y if y.status
    end
  end
  module_function "pingecho"
end
