#!/usr/bin/env ruby

require 'soap/rpc/standaloneServer'
require 'calc2'

class CalcServer2 < SOAP::RPC::StandaloneServer
  def on_init
    servant = CalcService2.new
    add_method(servant, 'set', 'newValue')
    add_method(servant, 'get')
    add_method_as(servant, '+', 'add', 'lhs')
    add_method_as(servant, '-', 'sub', 'lhs')
    add_method_as(servant, '*', 'multi', 'lhs')
    add_method_as(servant, '/', 'div', 'lhs')
  end
end

if $0 == __FILE__
  server = CalcServer2.new('CalcServer', 'http://tempuri.org/calcService', '0.0.0.0', 7000)
  trap(:INT) do
    server.shutdown
  end
  status = server.start
end
