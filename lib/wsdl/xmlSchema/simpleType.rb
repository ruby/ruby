# WSDL4R - XMLSchema simpleType definition for WSDL.
# Copyright (C) 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'xsd/namedelements'


module WSDL
module XMLSchema


class SimpleType < Info
  attr_accessor :name
  attr_reader :derivetype
  attr_reader :restriction

  def check_lexical_format(value)
    if @restriction
      check_restriction(value)
    elsif @extension
      raise NotImplementedError
      # ToDo
    else
      raise ArgumentError.new("incomplete simpleType")
    end
  end

  def base
    if @restriction
      @restriction.base
    elsif @extension
      @extension.base
    else
      raise ArgumentError.new("incomplete simpleType")
    end
  end

  def initialize(name = nil)
    super()
    @name = name
    @derivetype = nil
    @restriction = nil
  end

  def targetnamespace
    parent.targetnamespace
  end

  def parse_element(element)
    case element
    when RestrictionName
      @restriction = SimpleRestriction.new
      @derivetype = element.name
      @restriction
    end
  end

  def parse_attr(attr, value)
    case attr
    when NameAttrName
      @name = XSD::QName.new(targetnamespace, value.source)
    end
  end

private

  def check_restriction(value)
    unless @restriction.valid?(value)
      raise ::XSD::ValueSpaceError.new("#{@name}: cannot accept '#{value}'.")
    end
  end
end


end
end
