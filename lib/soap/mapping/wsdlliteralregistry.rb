# SOAP4R - WSDL literal mapping registry.
# Copyright (C) 2004, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/baseData'
require 'soap/mapping/mapping'
require 'soap/mapping/typeMap'
require 'xsd/codegen/gensupport'
require 'xsd/namedelements'


module SOAP
module Mapping


class WSDLLiteralRegistry < Registry
  attr_reader :definedelements
  attr_reader :definedtypes
  attr_accessor :excn_handler_obj2soap
  attr_accessor :excn_handler_soap2obj

  def initialize(definedtypes = XSD::NamedElements::Empty,
      definedelements = XSD::NamedElements::Empty)
    @definedtypes = definedtypes
    @definedelements = definedelements
    @excn_handler_obj2soap = nil
    @excn_handler_soap2obj = nil
    @schema_element_cache = {}
    @schema_attribute_cache = {}
  end

  def obj2soap(obj, qname)
    soap_obj = nil
    if ele = @definedelements[qname]
      soap_obj = obj2elesoap(obj, ele)
    elsif type = @definedtypes[qname]
      soap_obj = obj2typesoap(obj, type, true)
    else
      soap_obj = any2soap(obj, qname)
    end
    return soap_obj if soap_obj
    if @excn_handler_obj2soap
      soap_obj = @excn_handler_obj2soap.call(obj) { |yield_obj|
        Mapping.obj2soap(yield_obj, nil, nil, MAPPING_OPT)
      }
      return soap_obj if soap_obj
    end
    raise MappingError.new("cannot map #{obj.class.name} as #{qname}")
  end

  # node should be a SOAPElement
  def soap2obj(node, obj_class = nil)
    # obj_class is given when rpc/literal service.  but ignored for now.
    begin
      return any2obj(node)
    rescue MappingError
    end
    if @excn_handler_soap2obj
      begin
        return @excn_handler_soap2obj.call(node) { |yield_node|
	    Mapping.soap2obj(yield_node, nil, nil, MAPPING_OPT)
	  }
      rescue Exception
      end
    end
    if node.respond_to?(:type)
      raise MappingError.new("cannot map #{node.type.name} to Ruby object")
    else
      raise MappingError.new("cannot map #{node.elename.name} to Ruby object")
    end
  end

private

  MAPPING_OPT = { :no_reference => true }

  def obj2elesoap(obj, ele)
    o = nil
    qualified = (ele.elementform == 'qualified')
    if ele.type
      if type = @definedtypes[ele.type]
        o = obj2typesoap(obj, type, qualified)
      elsif type = TypeMap[ele.type]
        o = base2soap(obj, type)
      else
        raise MappingError.new("cannot find type #{ele.type}")
      end
    elsif ele.local_complextype
      o = obj2typesoap(obj, ele.local_complextype, qualified)
      add_attributes2soap(obj, o)
    elsif ele.local_simpletype
      o = obj2typesoap(obj, ele.local_simpletype, qualified)
    else
      raise MappingError.new('illegal schema?')
    end
    o.elename = ele.name
    o
  end

  def obj2typesoap(obj, type, qualified)
    if type.is_a?(::WSDL::XMLSchema::SimpleType)
      simpleobj2soap(obj, type)
    else
      complexobj2soap(obj, type, qualified)
    end
  end

  def simpleobj2soap(obj, type)
    type.check_lexical_format(obj)
    return SOAPNil.new if obj.nil?      # ToDo: check nillable.
    o = base2soap(obj, TypeMap[type.base])
    o
  end

  def complexobj2soap(obj, type, qualified)
    o = SOAPElement.new(type.name)
    o.qualified = qualified
    type.each_element do |child_ele|
      child = Mapping.get_attribute(obj, child_ele.name.name)
      if child.nil?
        if child_ele.nillable
          # ToDo: test
          # add empty element
          child_soap = obj2elesoap(nil, child_ele)
          o.add(child_soap)
        elsif Integer(child_ele.minoccurs) == 0
          # nothing to do
        else
          raise MappingError.new("nil not allowed: #{child_ele.name.name}")
        end
      elsif child_ele.map_as_array?
        child.each do |item|
          child_soap = obj2elesoap(item, child_ele)
          o.add(child_soap)
        end
      else
        child_soap = obj2elesoap(child, child_ele)
        o.add(child_soap)
      end
    end
    o
  end

  def any2soap(obj, qname)
    if obj.is_a?(SOAPElement)
      obj
    elsif obj.class.class_variables.include?('@@schema_element')
      stubobj2soap(obj, qname)
    elsif obj.is_a?(SOAP::Mapping::Object)
      mappingobj2soap(obj, qname)
    elsif obj.is_a?(Hash)
      ele = SOAPElement.from_obj(obj)
      ele.elename = qname
      ele
    else
      # expected to be a basetype or an anyType.
      # SOAPStruct, etc. is used instead of SOAPElement.
      begin
        ele = Mapping.obj2soap(obj, nil, nil, MAPPING_OPT)
        ele.elename = qname
        ele
      rescue MappingError
        ele = SOAPElement.new(qname, obj.to_s)
      end
      if obj.respond_to?(:__xmlattr)
        obj.__xmlattr.each do |key, value|
          ele.extraattr[key] = value
        end
      end
      ele
    end
  end

  def stubobj2soap(obj, qname)
    ele = SOAPElement.new(qname)
    ele.qualified =
      (obj.class.class_variables.include?('@@schema_qualified') and
      obj.class.class_eval('@@schema_qualified'))
    add_elements2soap(obj, ele)
    add_attributes2soap(obj, ele)
    ele
  end

  def mappingobj2soap(obj, qname)
    ele = SOAPElement.new(qname)
    obj.__xmlele.each do |key, value|
      if value.is_a?(::Array)
        value.each do |item|
          ele.add(obj2soap(item, key))
        end
      else
        ele.add(obj2soap(value, key))
      end
    end
    obj.__xmlattr.each do |key, value|
      ele.extraattr[key] = value
    end
    ele
  end

  def add_elements2soap(obj, ele)
    elements, as_array = schema_element_definition(obj.class)
    if elements
      elements.each do |elename, type|
        if child = Mapping.get_attribute(obj, elename.name)
          if as_array.include?(elename.name)
            child.each do |item|
              ele.add(obj2soap(item, elename))
            end
          else
            ele.add(obj2soap(child, elename))
          end
        elsif obj.is_a?(::Array) and as_array.include?(elename.name)
          obj.each do |item|
            ele.add(obj2soap(item, elename))
          end
        end
      end
    end
  end
  
  def add_attributes2soap(obj, ele)
    attributes = schema_attribute_definition(obj.class)
    if attributes
      attributes.each do |qname, param|
        attr = obj.__send__('xmlattr_' +
          XSD::CodeGen::GenSupport.safevarname(qname.name))
        ele.extraattr[qname] = attr
      end
    end
  end

  def base2soap(obj, type)
    soap_obj = nil
    if type <= XSD::XSDString
      str = XSD::Charset.encoding_conv(obj.to_s,
        Thread.current[:SOAPExternalCES], XSD::Charset.encoding)
      soap_obj = type.new(str)
    else
      soap_obj = type.new(obj)
    end
    soap_obj
  end

  def anytype2obj(node)
    if node.is_a?(::SOAP::SOAPBasetype)
      return node.data
    end
    klass = ::SOAP::Mapping::Object
    obj = klass.new
    obj
  end

  def any2obj(node, obj_class = nil)
    unless obj_class
      typestr = XSD::CodeGen::GenSupport.safeconstname(node.elename.name)
      obj_class = Mapping.class_from_name(typestr)
    end
    if obj_class and obj_class.class_variables.include?('@@schema_element')
      soapele2stubobj(node, obj_class)
    elsif node.is_a?(SOAPElement) or node.is_a?(SOAPStruct)
        # SOAPArray for literal?
      soapele2plainobj(node)
    else
      obj = Mapping.soap2obj(node, nil, obj_class, MAPPING_OPT)
      add_attributes2plainobj(node, obj)
      obj
    end
  end

  def soapele2stubobj(node, obj_class)
    obj = Mapping.create_empty_object(obj_class)
    add_elements2stubobj(node, obj)
    add_attributes2stubobj(node, obj)
    obj
  end

  def soapele2plainobj(node)
    obj = anytype2obj(node)
    add_elements2plainobj(node, obj)
    add_attributes2plainobj(node, obj)
    obj
  end

  def add_elements2stubobj(node, obj)
    elements, as_array = schema_element_definition(obj.class)
    vars = {}
    node.each do |name, value|
      item = elements.find { |k, v| k.name == name }
      if item
        elename, class_name = item
        if klass = Mapping.class_from_name(class_name)
          # klass must be a SOAPBasetype or a class
          if klass.ancestors.include?(::SOAP::SOAPBasetype)
            if value.respond_to?(:data)
              child = klass.new(value.data).data
            else
              child = klass.new(nil).data
            end
          else
            child = any2obj(value, klass)
          end
        elsif klass = Mapping.module_from_name(class_name)
          # simpletype
          if value.respond_to?(:data)
            child = value.data
          else
            raise MappingError.new(
              "cannot map to a module value: #{class_name}")
          end
        else
          raise MappingError.new("unknown class/module: #{class_name}")
        end
      else      # untyped element is treated as anyType.
        child = any2obj(value)
      end
      if as_array.include?(elename.name)
        (vars[name] ||= []) << child
      else
        vars[name] = child
      end
    end
    Mapping.set_attributes(obj, vars)
  end

  def add_attributes2stubobj(node, obj)
    if attributes = schema_attribute_definition(obj.class)
      define_xmlattr(obj)
      attributes.each do |qname, class_name|
        attr = node.extraattr[qname]
        next if attr.nil? or attr.empty?
        klass = Mapping.class_from_name(class_name)
        if klass.ancestors.include?(::SOAP::SOAPBasetype)
          child = klass.new(attr).data
        else
          child = attr
        end
        obj.__xmlattr[qname] = child
        define_xmlattr_accessor(obj, qname)
      end
    end
  end

  def add_elements2plainobj(node, obj)
    node.each do |name, value|
      obj.__add_xmlele_value(value.elename, any2obj(value))
    end
  end

  def add_attributes2plainobj(node, obj)
    return if node.extraattr.empty?
    define_xmlattr(obj)
    node.extraattr.each do |qname, value|
      obj.__xmlattr[qname] = value
      define_xmlattr_accessor(obj, qname)
    end
  end

  if RUBY_VERSION > "1.7.0"
    def define_xmlattr_accessor(obj, qname)
      name = XSD::CodeGen::GenSupport.safemethodname(qname.name)
      Mapping.define_attr_accessor(obj, 'xmlattr_' + name,
        proc { @__xmlattr[qname] },
        proc { |value| @__xmlattr[qname] = value })
    end
  else
    def define_xmlattr_accessor(obj, qname)
      name = XSD::CodeGen::GenSupport.safemethodname(qname.name)
      obj.instance_eval <<-EOS
        def #{name}
          @__xmlattr[#{qname.dump}]
        end

        def #{name}=(value)
          @__xmlattr[#{qname.dump}] = value
        end
      EOS
    end
  end

  if RUBY_VERSION > "1.7.0"
    def define_xmlattr(obj)
      obj.instance_variable_set('@__xmlattr', {})
      unless obj.respond_to?(:__xmlattr)
        Mapping.define_attr_accessor(obj, :__xmlattr, proc { @__xmlattr })
      end
    end
  else
    def define_xmlattr(obj)
      obj.instance_variable_set('@__xmlattr', {})
      unless obj.respond_to?(:__xmlattr)
        obj.instance_eval <<-EOS
          def __xmlattr
            @__xmlattr
          end
        EOS
      end
    end
  end

  # it caches @@schema_element.  this means that @@schema_element must not be
  # changed while a lifetime of a WSDLLiteralRegistry.
  def schema_element_definition(klass)
    @schema_element_cache[klass] ||= Mapping.schema_element_definition(klass)
  end

  def schema_attribute_definition(klass)
    @schema_attribute_cache[klass] ||= Mapping.schema_attribute_definition(klass)
  end
end


end
end
