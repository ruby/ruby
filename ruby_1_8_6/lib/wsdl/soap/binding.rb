# WSDL4R - WSDL SOAP binding definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL
module SOAP


class Binding < Info
  attr_reader :style
  attr_reader :transport

  def initialize
    super
    @style = nil
    @transport = nil
  end

  def parse_element(element)
    nil
  end

  def parse_attr(attr, value)
    case attr
    when StyleAttrName
      if ["document", "rpc"].include?(value.source)
	@style = value.source.intern
      else
	raise Parser::AttributeConstraintError.new(
          "Unexpected value #{ value }.")
      end
    when TransportAttrName
      @transport = value.source
    else
      nil
    end
  end
end


end
end
