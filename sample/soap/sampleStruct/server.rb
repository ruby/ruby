#!/usr/bin/env ruby

require 'soap/rpc/standaloneServer'
require 'sampleStruct'

class SampleStructServer < SOAP::RPC::StandaloneServer
  def initialize(*arg)
    super
    servant = SampleStructService.new
    add_servant(servant)
  end
end

if $0 == __FILE__
  server = SampleStructServer.new('SampleStructServer', SampleStructServiceNamespace, '0.0.0.0', 7000)
  trap(:INT) do
    server.shutdown
  end
  server.start
end
