# WSDL4R - Creating class definition from WSDL
# Copyright (C) 2002, 2003, 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

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
    @faulttypes = nil
    if definitions.respond_to?(:collect_faulttypes)
      @faulttypes = definitions.collect_faulttypes
    end
  end

  def dump(type = nil)
    result = "require 'xsd/qname'\n"
    if type
      result = dump_classdef(type.name, type)
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
      if ele.local_complextype
        dump_classdef(ele.name, ele.local_complextype,
          ele.elementform == 'qualified')
      elsif ele.local_simpletype
        dump_simpletypedef(ele.name, ele.local_simpletype)
      else
        nil
      end
    }.compact.join("\n")
  end

  def dump_simpletype
    @simpletypes.collect { |type|
      dump_simpletypedef(type.name, type)
    }.compact.join("\n")
  end

  def dump_complextype
    @complextypes.collect { |type|
      case type.compoundtype
      when :TYPE_STRUCT, :TYPE_EMPTY
        dump_classdef(type.name, type)
      when :TYPE_ARRAY
        dump_arraydef(type)
      when :TYPE_SIMPLE
        dump_simpleclassdef(type)
      when :TYPE_MAP
        # mapped as a general Hash
        nil
      else
        raise RuntimeError.new(
          "unknown kind of complexContent: #{type.compoundtype}")
      end
    }.compact.join("\n")
  end

  def dump_simpletypedef(qname, simpletype)
    if !simpletype.restriction or simpletype.restriction.enumeration.empty?
      return nil
    end
    c = XSD::CodeGen::ModuleDef.new(create_class_name(qname))
    c.comment = "#{qname}"
    const = {}
    simpletype.restriction.enumeration.each do |value|
      constname = safeconstname(value)
      const[constname] ||= 0
      if (const[constname] += 1) > 1
        constname += "_#{const[constname]}"
      end
      c.def_const(constname, ndq(value))
    end
    c.dump
  end

  def dump_simpleclassdef(type_or_element)
    qname = type_or_element.name
    base = create_class_name(type_or_element.simplecontent.base)
    c = XSD::CodeGen::ClassDef.new(create_class_name(qname), base)
    c.comment = "#{qname}"
    c.dump
  end

  def dump_classdef(qname, typedef, qualified = false)
    if @faulttypes and @faulttypes.index(qname)
      c = XSD::CodeGen::ClassDef.new(create_class_name(qname),
        '::StandardError')
    else
      c = XSD::CodeGen::ClassDef.new(create_class_name(qname))
    end
    c.comment = "#{qname}"
    c.def_classvar('schema_type', ndq(qname.name))
    c.def_classvar('schema_ns', ndq(qname.namespace))
    c.def_classvar('schema_qualified', dq('true')) if qualified
    schema_element = []
    init_lines = ''
    params = []
    typedef.each_element do |element|
      if element.type == XSD::AnyTypeName
        type = nil
      elsif klass = element_basetype(element)
        type = klass.name
      elsif element.type
        type = create_class_name(element.type)
      else
        type = nil      # means anyType.
        # do we define a class for local complexType from it's name?
        #   type = create_class_name(element.name)
        # <element>
        #   <complexType>
        #     <seq...>
        #   </complexType>
        # </element>
      end
      name = name_element(element).name
      attrname = safemethodname?(name) ? name : safemethodname(name)
      varname = safevarname(name)
      c.def_attr(attrname, true, varname)
      init_lines << "@#{varname} = #{varname}\n"
      if element.map_as_array?
        params << "#{varname} = []"
        type << '[]' if type
      else
        params << "#{varname} = nil"
      end
      # nil means @@schema_ns + varname
      eleqname =
        (varname == name && element.name.namespace == qname.namespace) ?
        nil : element.name
      schema_element << [varname, eleqname, type]
    end
    unless typedef.attributes.empty?
      define_attribute(c, typedef.attributes)
      init_lines << "@__xmlattr = {}\n"
    end
    c.def_classvar('schema_element',
      '[' +
        schema_element.collect { |varname, name, type|
          '[' +
            (
              if name
                varname.dump + ', [' + ndq(type) + ', ' + dqname(name) + ']'
              else
                varname.dump + ', ' + ndq(type)
              end
            ) +
          ']'
        }.join(', ') +
      ']'
    )
    c.def_method('initialize', *params) do
      init_lines
    end
    c.dump
  end

  def element_basetype(ele)
    if klass = basetype_class(ele.type)
      klass
    elsif ele.local_simpletype
      basetype_class(ele.local_simpletype.base)
    else
      nil
    end
  end

  def attribute_basetype(attr)
    if klass = basetype_class(attr.type)
      klass
    elsif attr.local_simpletype
      basetype_class(attr.local_simpletype.base)
    else
      nil
    end
  end

  def basetype_class(type)
    return nil if type.nil?
    if simpletype = @simpletypes[type]
      basetype_mapped_class(simpletype.base)
    else
      basetype_mapped_class(type)
    end
  end

  def define_attribute(c, attributes)
    schema_attribute = []
    attributes.each do |attribute|
      name = name_attribute(attribute)
      if klass = attribute_basetype(attribute)
        type = klass.name
      else
        type = nil
      end
      methodname = safemethodname('xmlattr_' + name.name)
      c.def_method(methodname) do <<-__EOD__
          (@__xmlattr ||= {})[#{dqname(name)}]
        __EOD__
      end
      c.def_method(methodname + '=', 'value') do <<-__EOD__
          (@__xmlattr ||= {})[#{dqname(name)}] = value
        __EOD__
      end
      schema_attribute << [name, type]
    end
    c.def_classvar('schema_attribute',
      '{' +
        schema_attribute.collect { |name, type|
          dqname(name) + ' => ' + ndq(type)
        }.join(', ') +
      '}'
    )
  end

  def name_element(element)
    return element.name if element.name
    return element.ref if element.ref
    raise RuntimeError.new("cannot define name of #{element}")
  end

  def name_attribute(attribute)
    return attribute.name if attribute.name
    return attribute.ref if attribute.ref
    raise RuntimeError.new("cannot define name of #{attribute}")
  end

  DEFAULT_ITEM_NAME = XSD::QName.new(nil, 'item')

  def dump_arraydef(complextype)
    qname = complextype.name
    c = XSD::CodeGen::ClassDef.new(create_class_name(qname), '::Array')
    c.comment = "#{qname}"
    child_type = complextype.child_type
    c.def_classvar('schema_type', ndq(child_type.name))
    c.def_classvar('schema_ns', ndq(child_type.namespace))
    child_element = complextype.find_aryelement
    schema_element = []
    if child_type == XSD::AnyTypeName
      type = nil
    elsif child_element and (klass = element_basetype(child_element))
      type = klass.name
    elsif child_type
      type = create_class_name(child_type)
    else
      type = nil
    end
    if child_element
      if child_element.map_as_array?
        type << '[]' if type
      end
      child_element_name = child_element.name
    else
      child_element_name = DEFAULT_ITEM_NAME
    end
    schema_element << [child_element_name.name, child_element_name, type]
    c.def_classvar('schema_element',
      '[' +
        schema_element.collect { |varname, name, type|
          '[' +
            (
              if name
                varname.dump + ', [' + ndq(type) + ', ' + dqname(name) + ']'
              else
                varname.dump + ', ' + ndq(type)
              end
            ) +
          ']'
        }.join(', ') +
      ']'
    )
    c.dump
  end
end


end
end
