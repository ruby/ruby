# WSDL4R - Creating MappingRegistry code from WSDL.
# Copyright (C) 2002, 2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/soap/classDefCreatorSupport'


module WSDL
module SOAP


class MappingRegistryCreator
  include ClassDefCreatorSupport

  attr_reader :definitions

  def initialize(definitions)
    @definitions = definitions
    @complextypes = @definitions.collect_complextypes
    @types = nil
  end

  def dump(types)
    @types = types
    map_cache = []
    map = ""
    @types.each do |type|
      if map_cache.index(type).nil?
	map_cache << type
	if type.namespace != XSD::Namespace
	  if typemap = dump_typemap(type)
            map << typemap
          end
	end
      end
   end
    return map
  end

private

  def dump_typemap(type)
    if definedtype = @complextypes[type]
      case definedtype.compoundtype
      when :TYPE_STRUCT
        dump_struct_typemap(definedtype)
      when :TYPE_ARRAY
        dump_array_typemap(definedtype)
      when :TYPE_MAP, :TYPE_EMPTY
        nil
      else
        raise NotImplementedError.new("must not reach here")
      end
    end
  end

  def dump_struct_typemap(definedtype)
    ele = definedtype.name
    return <<__EOD__
MappingRegistry.set(
  #{create_class_name(ele)},
  ::SOAP::SOAPStruct,
  ::SOAP::Mapping::Registry::TypedStructFactory,
  { :type => #{dqname(ele)} }
)
__EOD__
  end

  def dump_array_typemap(definedtype)
    ele = definedtype.name
    arytype = definedtype.find_arytype || XSD::AnyTypeName
    type = XSD::QName.new(arytype.namespace, arytype.name.sub(/\[(?:,)*\]$/, ''))
    @types << type
    return <<__EOD__
MappingRegistry.set(
  #{create_class_name(ele)},
  ::SOAP::SOAPArray,
  ::SOAP::Mapping::Registry::TypedArrayFactory,
  { :type => #{dqname(type)} }
)
__EOD__
  end
end


end
end
