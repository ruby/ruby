# WSDL4R - XMLSchema attribute definition for WSDL.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL
module XMLSchema


class Attribute < Info
  attr_accessor :ref
  attr_accessor :use
  attr_accessor :form
  attr_accessor :name
  attr_accessor :type
  attr_accessor :default
  attr_accessor :fixed

  attr_accessor :arytype

  def initialize
    super
    @ref = nil
    @use = nil
    @form = nil
    @name = nil
    @type = nil
    @default = nil
    @fixed = nil

    @arytype = nil
  end

  def parse_element(element)
    nil
  end

  def parse_attr(attr, value)
    case attr
    when RefAttrName
      @ref = value
    when UseAttrName
      @use = value
    when FormAttrName
      @form = value
    when NameAttrName
      @name = value
    when TypeAttrName
      @type = value
    when DefaultAttrName
      @default = value
    when FixedAttrName
      @fixed = value
    when ArrayTypeAttrName
      @arytype = if value.is_a?(XSD::QName)
	  value
	else
	  XSD::QName.new(XSD::Namespace, value)
	end
    else
      nil
    end
  end
end


end
end
