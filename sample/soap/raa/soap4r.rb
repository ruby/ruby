#!/usr/bin/env ruby

require 'iRAA'
require 'soap/rpc/driver'


server = ARGV.shift || 'http://raa.ruby-lang.org/soap/1.0.2/'

raa = SOAP::RPC::Driver.new(server, RAA::InterfaceNS)
raa.mapping_registry = RAA::MappingRegistry
RAA::Methods.each do |name, *params|
  raa.add_method(name, params)
end
# raa.wiredump_dev = STDOUT

p raa.getAllListings().sort

p raa.getProductTree()

p raa.getInfoFromCategory(RAA::Category.new("Library", "XML"))

t = Time.at(Time.now.to_i - 24 * 3600)
p raa.getModifiedInfoSince(t)

p raa.getModifiedInfoSince(DateTime.new(t.year, t.mon, t.mday, t.hour, t.min, t.sec))

o = raa.getInfoFromName("SOAP4R")
p o.class
p o.owner.name
p o
