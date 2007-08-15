# WSDL4R - WSDL binding definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'xsd/namedelements'


module WSDL


class Binding < Info
  attr_reader :name		# required
  attr_reader :type		# required
  attr_reader :operations
  attr_reader :soapbinding

  def initialize
    super
    @name = nil
    @type = nil
    @operations = XSD::NamedElements.new
    @soapbinding = nil
  end

  def targetnamespace
    parent.targetnamespace
  end

  def parse_element(element)
    case element
    when OperationName
      o = OperationBinding.new
      @operations << o
      o
    when SOAPBindingName
      o = WSDL::SOAP::Binding.new
      @soapbinding = o
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
    when TypeAttrName
      @type = value
    else
      nil
    end
  end
end


end
