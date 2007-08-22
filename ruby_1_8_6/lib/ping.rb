#
# = ping.rb: Check a host for upness
#
# Author:: Yukihiro Matsumoto
# Documentation:: Konrad Meyer
# 
# Performs the function of the basic network testing tool, ping.
# See: Ping.
#

require 'timeout'
require "socket"

# 
# Ping contains routines to test for the reachability of remote hosts.
# Currently the only routine implemented is pingecho().
#
# Ping.pingecho uses a TCP echo (not an ICMP echo) to determine if the
# remote host is reachable. This is usually adequate to tell that a remote
# host is available to telnet, ftp, or ssh to.
#
# Warning: Ping.pingecho may block for a long time if DNS resolution is
# slow. Requiring 'resolv-replace' allows non-blocking name resolution.
#
# Usage:
# 
#   require 'ping'
#
#   puts "'jimmy' is alive and kicking" if Ping.pingecho('jimmy', 10)
#
module Ping

  # 
  # Return true if we can open a connection to the hostname or IP address
  # +host+ on port +service+ (which defaults to the "echo" port) waiting up
  # to +timeout+ seconds.
  #
  # Example:
  #
  #   require 'ping'
  #
  #   Ping.pingecho "google.com", 10, 80
  #
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
