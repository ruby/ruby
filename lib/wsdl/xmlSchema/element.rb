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
    @maxoccurs = 1
    @minoccurs = 1
    @nillable = nil
  end

  def targetnamespace
    parent.targetnamespace
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
      #@name = XSD::QName.new(nil, value)
      @name = XSD::QName.new(targetnamespace, value)
    when TypeAttrName
      @type = if value.is_a?(XSD::QName)
	  value
	else
	  XSD::QName.new(XSD::Namespace, value)
	end
    when MaxOccursAttrName
      case parent
      when All
	if value != '1'
	  raise Parser::AttrConstraintError.new(
	    "Cannot parse #{ value } for #{ attr }.")
	end
	@maxoccurs = value
      when Sequence
	@maxoccurs = value
      else
	raise NotImplementedError.new
      end
      @maxoccurs
    when MinOccursAttrName
      case parent
      when All
	if ['0', '1'].include?(value)
	  @minoccurs = value
	else
	  raise Parser::AttrConstraintError.new(
	    "Cannot parse #{ value } for #{ attr }.")
	end
      when Sequence
	@minoccurs = value
      else
	raise NotImplementedError.new
      end
      @minoccurs
    when NillableAttrName
      @nillable = (value == 'true')
    else
      nil
    end
  end
end


end
end
