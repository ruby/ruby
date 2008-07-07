# WSDL4R - WSDL service definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'xsd/namedelements'


module WSDL


class Service < Info
  attr_reader :name		# required
  attr_reader :ports
  attr_reader :soap_address

  def initialize
    super
    @name = nil
    @ports = XSD::NamedElements.new
    @soap_address = nil
  end

  def targetnamespace
    parent.targetnamespace
  end

  def parse_element(element)
    case element
    when PortName
      o = Port.new
      @ports << o
      o
    when SOAPAddressName
      o = WSDL::SOAP::Address.new
      @soap_address = o
      o
    when DocumentationName
      o = Documentation.new
      o
    else
      nil
    end
  end

  def parse_attr(attr, value)
    case attr
    when NameAttrName
      @name = XSD::QName.new(targetnamespace, value.source)
    else
      nil
    end
  end
end


end
