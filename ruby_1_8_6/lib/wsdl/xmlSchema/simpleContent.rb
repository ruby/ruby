# WSDL4R - XMLSchema simpleContent definition for WSDL.
# Copyright (C) 2004, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'xsd/namedelements'


module WSDL
module XMLSchema


class SimpleContent < Info
  attr_reader :restriction
  attr_reader :extension

  def check_lexical_format(value)
    check(value)
  end

  def initialize
    super
    @restriction = nil
    @extension = nil
  end

  def base
    content.base
  end

  def targetnamespace
    parent.targetnamespace
  end

  def parse_element(element)
    case element
    when RestrictionName
      @restriction = SimpleRestriction.new
      @restriction
    when ExtensionName
      @extension = SimpleExtension.new
      @extension
    end
  end

private

  def content
    @restriction || @extension
  end

  def check(value)
    unless content.valid?(value)
      raise XSD::ValueSpaceError.new("#{@name}: cannot accept '#{value}'")
    end
  end
end


end
end
