# WSDL4R - XMLSchema simpleType definition for WSDL.
# Copyright (C) 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'xsd/namedelements'


module WSDL
module XMLSchema


class SimpleRestriction < Info
  attr_reader :base
  attr_reader :enumeration

  def initialize
    super
    @base = nil
    @enumeration = []   # NamedElements?
  end
  
  def valid?(value)
    @enumeration.include?(value)
  end

  def parse_element(element)
    case element
    when EnumerationName
      Enumeration.new   # just a parsing handler
    end
  end

  def parse_attr(attr, value)
    case attr
    when BaseAttrName
      @base = value
    end
  end
end


end
end
