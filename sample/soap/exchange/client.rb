#!/usr/bin/env ruby

require "soap/rpc/driver"

ExchangeServiceNamespace = 'http://tempuri.org/exchangeService'

server = ARGV.shift || "http://localhost:7000/"
# server = "http://localhost:8808/server.cgi"

logger = nil
wiredump_dev = nil
# logger = Logger.new(STDERR)
# wiredump_dev = STDERR

drv = SOAP::RPC::Driver.new(server, ExchangeServiceNamespace)
drv.wiredump_dev = wiredump_dev
drv.add_method("rate", "country1", "country2")

p drv.rate("USA", "Japan")
