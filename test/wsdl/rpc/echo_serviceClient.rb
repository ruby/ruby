#!/usr/bin/env ruby
require 'echoDriver.rb'

endpoint_url = ARGV.shift
obj = Echo_port_type.new(endpoint_url)

# Uncomment the below line to see SOAP wiredumps.
# obj.wiredump_dev = STDERR

# SYNOPSIS
#   echo(arg1, arg2)
#
# ARGS
#   arg1            Person - {urn:rpc-type}person
#   arg2            Person - {urn:rpc-type}person
#
# RETURNS
#   v_return        Person - {urn:rpc-type}person
#
arg1 = arg2 = nil
puts obj.echo(arg1, arg2)


