#!/usr/bin/env ruby

require 'soap/wsdlDriver'
wsdl = 'http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/'
raa = SOAP::WSDLDriverFactory.new(wsdl).create_driver
raa.generate_explicit_type = true
p "WSDL loaded."

class Category
  def initialize(major, minor)
    @major = major
    @minor = minor
  end
end

p raa.getAllListings().sort

p raa.getProductTree()

p raa.getInfoFromCategory(Category.new("Library", "XML"))

t = Time.at(Time.now.to_i - 24 * 3600)
p raa.getModifiedInfoSince(t)

p raa.getModifiedInfoSince(DateTime.new(t.year, t.mon, t.mday, t.hour, t.min, t.sec))

o = raa.getInfoFromName("SOAP4R")
p o.type
p o.owner.name
p o

