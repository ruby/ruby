# WSDL4R - XMLSchema complexContent definition for WSDL.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


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

  def targetnamespace
    parent.targetnamespace
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
