# WSDL4R - WSDL part definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL


class Part < Info
  attr_reader :name	# required
  attr_reader :element	# optional
  attr_reader :type	# optional

  def initialize
    super
    @name = nil
    @element = nil
    @type = nil
  end

  def parse_element(element)
    case element
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
      @name = value.source
    when ElementAttrName
      @element = value
    when TypeAttrName
      @type = value
    else
      nil
    end
  end
end


end
