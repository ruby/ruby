#!/usr/local/bin/ruby

require 'soap/rpc/cgistub'
require 'exchange'

class ExchangeServer < SOAP::RPC::CGIStub
  def initialize(*arg)
    super
    servant = Exchange.new
    add_servant(servant)
  end
end

status = ExchangeServer.new('SampleStructServer', ExchangeServiceNamespace).start
