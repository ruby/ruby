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
    @elements = definitions.collect_elements
    @simpletypes = definitions.collect_simpletypes
    @complextypes = definitions.collect_complextypes
    @faulttypes = definitions.collect_faulttypes if definitions.respond_to?(:collect_faulttypes)
  end

  def dump(class_name = nil)
    result = ''
    if class_name
      result = dump_classdef(class_name)
    else
      str = dump_element
      unless str.empty?
        result << "\n" unless result.empty?
        result << str
      end
      str = dump_complextype
      unless str.empty?
        result << "\n" unless result.empty?
        result << str
      end
      str = dump_simpletype
      unless str.empty?
        result << "\n" unless result.empty?
        result << str
      end
    end
    result
  end

private

  def dump_element
    @elements.collect { |ele|
      ele.local_complextype ? dump_classdef(ele) : ''
    }.join("\n")
  end

  def dump_simpletype
    @simpletypes.collect { |type|
      dump_simpletypedef(type)
    }.join("\n")
  end

  def dump_complextype
    @complextypes.collect { |type|
      case type.compoundtype
      when :TYPE_STRUCT
        dump_classdef(type)
      when :TYPE_ARRAY
        dump_arraydef(type)
      when :TYPE_SIMPLE
        STDERR.puts("not implemented: ToDo")
      else
        raise RuntimeError.new(
          "Unknown kind of complexContent: #{type.compoundtype}")
      end
    }.join("\n")
  end

  def dump_simpletypedef(simpletype)
    qname = simpletype.name
    if simpletype.restriction.enumeration.empty?
      STDERR.puts("#{qname}: simpleType which is not enum type not supported.")
      return ''
    end
    c = XSD::CodeGen::ModuleDef.new(create_class_name(qname))
    c.comment = "#{ qname.namespace }"
    simpletype.restriction.enumeration.each do |value|
      c.def_const(safeconstname(value), value.dump)
    end
    c.dump
  end

  def dump_classdef(type_or_element)
    qname = type_or_element.name
    if @faulttypes and @faulttypes.index(qname)
      c = XSD::CodeGen::ClassDef.new(create_class_name(qname),
        '::StandardError')
    else
      c = XSD::CodeGen::ClassDef.new(create_class_name(qname))
    end
    c.comment = "#{ qname.namespace }"
    c.def_classvar('schema_type', qname.name.dump)
    c.def_classvar('schema_ns', qname.namespace.dump)
    schema_attribute = []
    schema_element = []
    init_lines = ''
    params = []
    type_or_element.each_element do |element|
      next unless element.name
      name = element.name.name
      if element.type == XSD::AnyTypeName
        type = nil
      elsif basetype = basetype_class(element.type)
        type = basetype.name
      else
        type = create_class_name(element.type)
      end
      attrname = safemethodname?(name) ? name : safemethodname(name)
      varname = safevarname(name)
      c.def_attr(attrname, true, varname)
      init_lines << "@#{ varname } = #{ varname }\n"
      if element.map_as_array?
        params << "#{ varname } = []"
        type << '[]'
      else
        params << "#{ varname } = nil"
      end
      schema_element << [name, type]
    end
    unless type_or_element.attributes.empty?
      type_or_element.attributes.each do |attribute|
        name = attribute.name.name
        if basetype = basetype_class(attribute.type)
          type = basetype_class(attribute.type).name
        else
          type = nil
        end
        varname = safevarname('attr_' + name)
        c.def_method(varname) do <<-__EOD__
            @__soap_attribute[#{name.dump}]
          __EOD__
        end
        c.def_method(varname + '=', 'value') do <<-__EOD__
            @__soap_attribute[#{name.dump}] = value
          __EOD__
        end
        schema_attribute << [name, type]
      end
      init_lines << "@__soap_attribute = {}\n"
    end
    c.def_classvar('schema_attribute',
      '{' +
        schema_attribute.collect { |name, type|
          name.dump + ' => ' + ndq(type)
        }.join(', ') +
      '}'
    )
    c.def_classvar('schema_element',
      '{' +
        schema_element.collect { |name, type|
          name.dump + ' => ' + ndq(type)
        }.join(', ') +
      '}'
    )
    c.def_method('initialize', *params) do
      init_lines
    end
    c.dump
  end

  def basetype_class(type)
    if @simpletypes[type]
      basetype_mapped_class(@simpletypes[type].base)
    else
      basetype_mapped_class(type)
    end
  end

  def dump_arraydef(complextype)
    qname = complextype.name
    c = XSD::CodeGen::ClassDef.new(create_class_name(qname), '::Array')
    c.comment = "#{ qname.namespace }"
    c.def_classvar('schema_type', qname.name.dump)
    c.def_classvar('schema_ns', qname.namespace.dump)
    c.dump
  end
end


end
end
