#!/usr/bin/env ruby

require 'soap/rpc/cgistub'
require 'servant'

class Server < SOAP::RPC::CGIStub
  class DummyServant
    def push(value)
      "Not supported"
    end

    def pop
      "Not supported"
    end
  end

  def initialize(*arg)
    super
    add_rpc_servant(Servant.new, 'http://tempuri.org/requestScopeService')

    # Application scope servant is not supported in CGI environment.
    # See server.rb to support application scope servant.
    dummy = DummyServant.new
    add_method_with_namespace('http://tempuri.org/applicationScopeService', dummy, 'push', 'value')
    add_method_with_namespace('http://tempuri.org/applicationScopeService', dummy, 'pop')
  end
end

status = Server.new('Server', nil).start
