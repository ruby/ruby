#!/usr/bin/env ruby

key = ARGV.shift

require 'soap/rpc/driver'

server = 'http://www.SoapClient.com/xml/SQLDataSoap.WSDL'
interface = 'http://www.SoapClient.com/xml/SQLDataSoap.xsd'

whois = SOAP::RPC::Driver.new(server, interface)
whois.wiredump_dev = STDERR
whois.add_method('ProcessSRL', 'SRLFile', 'RequestName', 'key')

p whois.ProcessSRL('WHOIS.SRI', 'whois', key)
