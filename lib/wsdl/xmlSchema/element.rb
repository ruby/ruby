# WSDL4R - XMLSchema element definition for WSDL.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL
module XMLSchema


class Element < Info
  attr_accessor :name	# required
  attr_accessor :type
  attr_accessor :local_complextype
  attr_accessor :constraint
  attr_accessor :maxoccurs
  attr_accessor :minoccurs
  attr_accessor :nillable

  def initialize(name = nil, type = XSD::AnyTypeName)
    super()
    @name = name
    @type = type
    @local_complextype = nil
    @constraint = nil
    @maxoccurs = '1'
    @minoccurs = '1'
    @nillable = nil
  end

  def targetnamespace
    parent.targetnamespace
  end

  def elementform
    # ToDo: must be overwritten.
    parent.elementformdefault
  end

  def parse_element(element)
    case element
    when ComplexTypeName
      @type = nil
      @local_complextype = ComplexType.new
      @local_complextype
    when UniqueName
      @constraint = Unique.new
      @constraint
    else
      nil
    end
  end

  def parse_attr(attr, value)
    case attr
    when NameAttrName
      @name = XSD::QName.new(targetnamespace, value.source)
    when TypeAttrName
      @type = value
    when MaxOccursAttrName
      if parent.is_a?(All)
	if value.source != '1'
	  raise Parser::AttrConstraintError.new(
	    "Cannot parse #{ value } for #{ attr }.")
	end
      end
      @maxoccurs = value.source
    when MinOccursAttrName
      if parent.is_a?(All)
	unless ['0', '1'].include?(value.source)
	  raise Parser::AttrConstraintError.new(
	    "Cannot parse #{ value } for #{ attr }.")
	end
      end
      @minoccurs = value.source
    when NillableAttrName
      @nillable = (value.source == 'true')
    else
      nil
    end
  end
end


end
end
