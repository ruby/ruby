# WSDL4R - Creating class definition from WSDL
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/data'
require 'wsdl/soap/classDefCreatorSupport'
require 'xsd/codegen'


module WSDL
module SOAP


class ClassDefCreator
  include ClassDefCreatorSupport

  def initialize(definitions)
    @simpletypes = definitions.collect_simpletypes
    @complextypes = definitions.collect_complextypes
    @faulttypes = definitions.collect_faulttypes
  end

  def dump(class_name = nil)
    result = ""
    if class_name
      result = dump_classdef(class_name)
    else
      @complextypes.each do |type|
	case type.compoundtype
	when :TYPE_STRUCT
	  result << dump_classdef(type)
	when :TYPE_ARRAY
	  result << dump_arraydef(type)
       	else
	  raise RuntimeError.new("Unknown complexContent definition...")
	end
	result << "\n"
      end

      result << @simpletypes.collect { |type|
        dump_simpletypedef(type)
      }.join("\n")
    end
    result
  end

private

  def dump_simpletypedef(simpletype)
    qname = simpletype.name
    if simpletype.restriction.enumeration.empty?
      STDERR.puts("#{qname}: simpleType which is not enum type not supported.")
      return ""
    end
    c = XSD::CodeGen::ModuleDef.new(create_class_name(qname))
    c.comment = "#{ qname.namespace }"
    simpletype.restriction.enumeration.each do |value|
      c.def_const(safeconstname(value), value.dump)
    end
    c.dump
  end

  def dump_classdef(complextype)
    qname = complextype.name
    if @faulttypes.index(qname)
      c = XSD::CodeGen::ClassDef.new(create_class_name(qname),
        "::StandardError")
    else
      c = XSD::CodeGen::ClassDef.new(create_class_name(qname))
    end
    c.comment = "#{ qname.namespace }"
    c.def_classvar("schema_type", qname.name.dump)
    c.def_classvar("schema_ns", qname.namespace.dump)
    init_lines = ""
    params = []
    complextype.each_element do |element|
      name = element.name.name
      varname = safevarname(name)
      c.def_attr(name, true, varname)
      init_lines << "@#{ varname } = #{ varname }\n"
      params << "#{ varname } = nil"
    end
    complextype.attributes.each do |attribute|
      name = "attr_" + attribute.name
      varname = safevarname(name)
      c.def_attr(name, true, varname)
      init_lines << "@#{ varname } = #{ varname }\n"
      params << "#{ varname } = nil"
    end
    c.def_method("initialize", *params) do
      init_lines
    end
    c.dump
  end

  def dump_arraydef(complextype)
    qname = complextype.name
    c = XSD::CodeGen::ClassDef.new(create_class_name(qname), "::Array")
    c.comment = "#{ qname.namespace }"
    c.def_classvar("schema_type", qname.name.dump)
    c.def_classvar("schema_ns", qname.namespace.dump)
    c.dump
  end
end


end
end
