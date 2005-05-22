# XSD4R - XML Mapping for Ruby
# Copyright (C) 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require "soap/parser"
require 'soap/encodingstyle/literalHandler'
require "soap/generator"
require "soap/mapping"
require "soap/mapping/wsdlliteralregistry"


module XSD


module Mapping
  MappingRegistry = SOAP::Mapping::WSDLLiteralRegistry.new
  MappingOpt = {:default_encodingstyle => SOAP::LiteralNamespace}

  def self.obj2xml(obj, elename = nil, io = nil)
    if !elename.nil? and !elename.is_a?(XSD::QName)
      elename = XSD::QName.new(nil, elename)
    end
    elename ||= XSD::QName.new(nil, SOAP::Mapping.name2elename(obj.class.to_s))
    soap = SOAP::Mapping.obj2soap(obj, MappingRegistry)
    soap.elename = elename
    generator = SOAP::SOAPGenerator.new(MappingOpt)
    generator.generate(soap, io)
  end

  def self.xml2obj(stream)
    parser = SOAP::Parser.new(MappingOpt)
    soap = parser.parse(stream)
    SOAP::Mapping.soap2obj(soap, MappingRegistry)
  end
end


end
