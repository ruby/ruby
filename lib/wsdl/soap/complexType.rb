# WSDL4R - SOAP complexType definition for WSDL.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/xmlSchema/complexType'


module WSDL
module XMLSchema


class ComplexType < Info
  def compoundtype
    @compoundtype ||= check_type
  end

  def check_type
    if content
      if content.elements.size == 1 and content.elements[0].maxoccurs != 1
	:TYPE_ARRAY
      else
	:TYPE_STRUCT
      end
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
    ele = nil
    case compoundtype
    when :TYPE_STRUCT
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
    elsif content.elements.size == 1 and content.elements[0].maxoccurs != 1
      return content.elements[0].type
    else
      raise RuntimeError.new("Assert: Unknown array definition.")
    end
    nil
  end

private

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
