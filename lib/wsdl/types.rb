# WSDL4R - WSDL types definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL


class Types < Info
  attr_reader :schemas

  def initialize
    super
    @schemas = []
  end

  def parse_element(element)
    case element
    when SchemaName
      o = XMLSchema::Schema.new
      @schemas << o
      o
    when DocumentationName
      o = Documentation.new
      o
    else
      nil
    end
  end

  def parse_attr(attr, value)
    nil
  end
end


end
