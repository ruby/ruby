#!/usr/local/bin/ruby

require 'soap/rpc/cgistub'
require 'sampleStruct'

class SampleStructServer < SOAP::RPC::CGIStub
  def initialize(*arg)
    super
    servant = SampleStructService.new
    add_servant(servant)
  end
end

status = SampleStructServer.new('SampleStructServer', SampleStructServiceNamespace).start
