# WSDL4R - WSDL portType definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'xsd/namedelements'


module WSDL


class PortType < Info
  attr_reader :name		# required
  attr_reader :operations

  def targetnamespace
    parent.targetnamespace
  end

  def initialize
    super
    @name = nil
    @operations = XSD::NamedElements.new
  end

  def find_binding
    root.bindings.find { |item| item.type == @name }
  end

  def locations
    bind_name = find_binding.name
    result = []
    root.services.each do |service|
      service.ports.each do |port|
        if port.binding == bind_name
          result << port.soap_address.location if port.soap_address
        end
      end
    end
    result
  end

  def parse_element(element)
    case element
    when OperationName
      o = Operation.new
      @operations << o
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
