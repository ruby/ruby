=begin
WSDL4R - XMLSchema complexContent definition for WSDL.
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


class ComplexContent < Info
  attr_accessor :base
  attr_reader :derivetype
  attr_reader :content
  attr_reader :attributes

  def initialize
    super
    @base = nil
    @derivetype = nil
    @content = nil
    @attributes = XSD::NamedElements.new
  end

  def parse_element(element)
    case element
    when RestrictionName, ExtensionName
      @derivetype = element.name
      self
    when AllName
      if @derivetype.nil?
	raise Parser::ElementConstraintError.new("base attr not found.")
      end
      @content = All.new
      @content
    when SequenceName
      if @derivetype.nil?
	raise Parser::ElementConstraintError.new("base attr not found.")
      end
      @content = Sequence.new
      @content
    when ChoiceName
      if @derivetype.nil?
	raise Parser::ElementConstraintError.new("base attr not found.")
      end
      @content = Choice.new
      @content
    when AttributeName
      if @derivetype.nil?
	raise Parser::ElementConstraintError.new("base attr not found.")
      end
      o = Attribute.new
      @attributes << o
      o
    end
  end

  def parse_attr(attr, value)
    if @derivetype.nil?
      return nil
    end
    case attr
    when BaseAttrName
      @base = value
    else
      nil
    end
  end
end


end
end
