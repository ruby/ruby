=begin
WSDL4R - XMLSchema schema definition for WSDL.
Copyright (C) 2002, 2003  NAKAMURA, Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end


require 'wsdl/info'
require 'xsd/namedelements'


module WSDL
module XMLSchema


class Schema < Info
  attr_reader :targetnamespace	# required
  attr_reader :complextypes
  attr_reader :elements
  attr_reader :attributes
  attr_reader :imports
  attr_accessor :attributeformdefault
  attr_accessor :elementformdefault

  def initialize
    super
    @targetnamespace = nil
    @complextypes = XSD::NamedElements.new
    @elements = XSD::NamedElements.new
    @attributes = XSD::NamedElements.new
    @imports = []
    @elementformdefault = nil
  end

  def parse_element(element)
    case element
    when ImportName
      o = Import.new
      @imports << o
      o
    when ComplexTypeName
      o = ComplexType.new
      @complextypes << o
      o
    when ElementName
      o = Element.new
      @elements << o
      o
    when AttributeName
      o = Attribute.new
      o
    else
      nil
    end
  end

  def parse_attr(attr, value)
    case attr
    when TargetNamespaceAttrName
      @targetnamespace = value
    when AttributeFormDefaultAttrName
      @attributeformdefault = value
    when ElementFormDefaultAttrName
      @elementformdefault = value
    else
      nil
    end
  end

  def collect_elements
    result = XSD::NamedElements.new
    result.concat(@elements)
    result
  end

  def collect_complextypes
    result = XSD::NamedElements.new
    result.concat(@complextypes)
    result
  end

  def self.parse_element(element)
    if element == SchemaName
      Schema.new
    else
      nil
    end
  end
end


end
end
