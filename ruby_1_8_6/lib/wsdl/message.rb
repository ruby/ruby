# WSDL4R - WSDL message definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL


class Message < Info
  attr_reader :name	# required
  attr_reader :parts

  def initialize
    super
    @name = nil
    @parts = []
  end

  def targetnamespace
    parent.targetnamespace
  end

  def parse_element(element)
    case element
    when PartName
      o = Part.new
      @parts << o
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
      @name = XSD::QName.new(parent.targetnamespace, value.source)
    else
      nil
    end
  end
end


end
