#!/usr/bin/env ruby

require 'soap/rpc/standaloneServer'
require 'exchange'

class ExchangeServer < SOAP::RPC::StandaloneServer
  def initialize(*arg)
    super
    servant = Exchange.new
    add_servant(servant)
  end
end

if $0 == __FILE__
  status = ExchangeServer.new('SampleStructServer', ExchangeServiceNamespace, '0.0.0.0', 7000).start
end
