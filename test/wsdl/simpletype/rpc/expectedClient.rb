#!/usr/bin/env ruby
require 'echo_versionDriver.rb'

endpoint_url = ARGV.shift
obj = Echo_version_port_type.new(endpoint_url)

# run ruby with -d to see SOAP wiredumps.
obj.wiredump_dev = STDERR if $DEBUG

# SYNOPSIS
#   echo_version(version)
#
# ARGS
#   version         Version - {urn:example.com:simpletype-rpc-type}version
#
# RETURNS
#   version_struct  Version_struct - {urn:example.com:simpletype-rpc-type}version_struct
#
version = nil
puts obj.echo_version(version)

# SYNOPSIS
#   echo_version_r(version_struct)
#
# ARGS
#   version_struct  Version_struct - {urn:example.com:simpletype-rpc-type}version_struct
#
# RETURNS
#   version         Version - {urn:example.com:simpletype-rpc-type}version
#
version_struct = nil
puts obj.echo_version_r(version_struct)


