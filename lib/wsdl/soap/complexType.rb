=begin
WSDL4R - SOAP complexType definition for WSDL.
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


require 'wsdl/xmlSchema/complexType'


module WSDL
module XMLSchema


class ComplexType < Info
  def compoundtype
    @compoundtype ||= check_type
  end

  def check_type
    if content
      :TYPE_STRUCT
    elsif complexcontent and complexcontent.base == ::SOAP::ValueArrayName
      :TYPE_ARRAY
    else
      raise NotImplementedError.new("Unknown kind of complexType.")
    end
  end

  def child_type(name = nil)
    case compoundtype
    when :TYPE_STRUCT
      if ele = find_element(name)
        ele.type
      elsif ele = find_element_by_name(name.name)
	ele.type
      else
        nil
      end
    when :TYPE_ARRAY
      @contenttype ||= content_arytype
    end
  end

  def child_defined_complextype(name)
    unless compoundtype == :TYPE_STRUCT
      raise RuntimeError.new("Assert: not for struct")
    end
    unless ele = find_element(name)
      if name.namespace.nil?
	ele = find_element_by_name(name.name)
      end
    end
    unless ele
      raise RuntimeError.new("Cannot find #{name} as a children of #{@name}.")
    end
    ele.local_complextype
  end

  def find_arytype
    complexcontent.attributes.each do |attribute|
      if attribute.ref == ::SOAP::AttrArrayTypeName
	return attribute.arytype
      end
    end
    nil
  end

private

  def content_arytype
    unless compoundtype == :TYPE_ARRAY
      raise RuntimeError.new("Assert: not for array")
    end
    arytype = find_arytype
    ns = arytype.namespace
    name = arytype.name.sub(/\[(?:,)*\]$/, '')
    XSD::QName.new(ns, name)
  end
end


end
end
