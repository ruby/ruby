#!/usr/bin/env ruby

text = ARGV.shift || 'Hello world.'
lang = ARGV.shift || 'en_fr'

require 'soap/rpc/driver'

server = 'http://services.xmethods.net/perl/soaplite.cgi'
InterfaceNS = 'urn:xmethodsBabelFish'
wireDumpDev = nil	# STDERR

drv = SOAP::RPC::Driver.new(server, InterfaceNS)
drv.wiredump_dev = wireDumpDev
drv.add_method_with_soapaction('BabelFish', InterfaceNS + "#BabelFish", 'translationmode', 'sourcedata')

p drv.BabelFish(lang, text)
