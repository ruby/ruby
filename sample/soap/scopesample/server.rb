#!/usr/bin/env ruby

require 'soap/rpc/standaloneServer'
require 'servant'

class Server < SOAP::RPC::StandaloneServer
  def initialize(*arg)
    super
    add_rpc_servant(Servant.new, 'http://tempuri.org/applicationScopeService')
    add_rpc_request_servant(Servant, 'http://tempuri.org/requestScopeService')
  end
end

if $0 == __FILE__
  server = Server.new('Server', nil, '0.0.0.0', 7000)
  trap(:INT) do
    server.shutdown
  end
  server.start
end
