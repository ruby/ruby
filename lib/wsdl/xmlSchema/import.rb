# WSDL4R - XMLSchema import definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL
module XMLSchema


class Import < Info
  attr_reader :namespace
  attr_reader :schemalocation

  def initialize
    super
    @namespace = nil
    @schemalocation = nil
  end

  def parse_element(element)
    nil
  end

  def parse_attr(attr, value)
    case attr
    when NamespaceAttrName
      @namespace = value.source
    when SchemaLocationAttrName
      @schemalocation = value.source
    else
      nil
    end
  end
end


end
end
