=begin
WSDL4R - XMLSchema attribute definition for WSDL.
Copyright (C) 2002, 2003  NAKAMURA, Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end


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
