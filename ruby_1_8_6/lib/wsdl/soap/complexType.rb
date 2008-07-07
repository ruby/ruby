# WSDL4R - SOAP complexType definition for WSDL.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/xmlSchema/complexType'
require 'soap/mapping'


module WSDL
module XMLSchema


class ComplexType < Info
  def compoundtype
    @compoundtype ||= check_type
  end

  def check_type
    if content
      if attributes.empty? and
          content.elements.size == 1 and content.elements[0].maxoccurs != '1'
        if name == ::SOAP::Mapping::MapQName
          :TYPE_MAP
        else
          :TYPE_ARRAY
        end
      else
	:TYPE_STRUCT
      end
    elsif complexcontent
      if complexcontent.base == ::SOAP::ValueArrayName
        :TYPE_ARRAY
      else
        complexcontent.basetype.check_type
      end
    elsif simplecontent
      :TYPE_SIMPLE
    elsif !attributes.empty?
      :TYPE_STRUCT
    else # empty complexType definition (seen in partner.wsdl of salesforce)
      :TYPE_EMPTY
    end
  end

  def child_type(name = nil)
    case compoundtype
    when :TYPE_STRUCT
      if ele = find_element(name)
        ele.type
      elsif ele = find_element_by_name(name.name)
	ele.type
      end
    when :TYPE_ARRAY
      @contenttype ||= content_arytype
    when :TYPE_MAP
      item_ele = find_element_by_name("item") or
        raise RuntimeError.new("'item' element not found in Map definition.")
      content = item_ele.local_complextype or
        raise RuntimeError.new("No complexType definition for 'item'.")
      if ele = content.find_element(name)
        ele.type
      elsif ele = content.find_element_by_name(name.name)
        ele.type
      end
    else
      raise NotImplementedError.new("Unknown kind of complexType.")
    end
  end

  def child_defined_complextype(name)
    ele = nil
    case compoundtype
    when :TYPE_STRUCT, :TYPE_MAP
      unless ele = find_element(name)
       	if name.namespace.nil?
  	  ele = find_element_by_name(name.name)
   	end
      end
    when :TYPE_ARRAY
      if content.elements.size == 1
	ele = content.elements[0]
      else
	raise RuntimeError.new("Assert: must not reach.")
      end
    else
      raise RuntimeError.new("Assert: Not implemented.")
    end
    unless ele
      raise RuntimeError.new("Cannot find #{name} as a children of #{@name}.")
    end
    ele.local_complextype
  end

  def find_arytype
    unless compoundtype == :TYPE_ARRAY
      raise RuntimeError.new("Assert: not for array")
    end
    if complexcontent
      complexcontent.attributes.each do |attribute|
	if attribute.ref == ::SOAP::AttrArrayTypeName
	  return attribute.arytype
	end
      end
      if check_array_content(complexcontent.content)
        return element_simpletype(complexcontent.content.elements[0])
      end
    elsif check_array_content(content)
      return element_simpletype(content.elements[0])
    end
    raise RuntimeError.new("Assert: Unknown array definition.")
  end

  def find_aryelement
    unless compoundtype == :TYPE_ARRAY
      raise RuntimeError.new("Assert: not for array")
    end
    if complexcontent
      if check_array_content(complexcontent.content)
        return complexcontent.content.elements[0]
      end
    elsif check_array_content(content)
      return content.elements[0]
    end
    nil # use default item name
  end

private

  def element_simpletype(element)
    if element.type
      element.type 
    elsif element.local_simpletype
      element.local_simpletype.base
    else
      nil
    end
  end

  def check_array_content(content)
    content and content.elements.size == 1 and
      content.elements[0].maxoccurs != '1'
  end

  def content_arytype
    if arytype = find_arytype
      ns = arytype.namespace
      name = arytype.name.sub(/\[(?:,)*\]$/, '')
      XSD::QName.new(ns, name)
    else
      nil
    end
  end
end


end
end
