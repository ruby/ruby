=begin
WSDL4R - XMLSchema complexType definition for WSDL.
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


class Sequence < Info
  attr_reader :minoccurs
  attr_reader :maxoccurs
  attr_reader :elements

  def initialize
    super()
    @minoccurs = 1
    @maxoccurs = 1
    @elements = []
  end

  def targetnamespace
    parent.targetnamespace
  end

  def <<(element)
    @elements << element
  end

  def parse_element(element)
    case element
    when AnyName
      o = Any.new
      @elements << o
      o
    when ElementName
      o = Element.new
      @elements << o
      o
    else
      nil
    end
  end

  def parse_attr(attr, value)
    case attr
    when MaxOccursAttrName
      @maxoccurs = value
    when MinOccursAttrName
      @minoccurs = value
    else
      nil
    end
  end
end


end
end
