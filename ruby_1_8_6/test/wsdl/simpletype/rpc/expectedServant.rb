require 'echo_version.rb'

class Echo_version_port_type
  # SYNOPSIS
  #   echo_version(version)
  #
  # ARGS
  #   version         Version - {urn:example.com:simpletype-rpc-type}version
  #
  # RETURNS
  #   version_struct  Version_struct - {urn:example.com:simpletype-rpc-type}version_struct
  #
  def echo_version(version)
    p [version]
    raise NotImplementedError.new
  end

  # SYNOPSIS
  #   echo_version_r(version_struct)
  #
  # ARGS
  #   version_struct  Version_struct - {urn:example.com:simpletype-rpc-type}version_struct
  #
  # RETURNS
  #   version         Version - {urn:example.com:simpletype-rpc-type}version
  #
  def echo_version_r(version_struct)
    p [version_struct]
    raise NotImplementedError.new
  end
end

