# SOAP4R - Ruby type mapping utility.
# Copyright (C) 2000, 2001, 2003-2005  NAKAMURA Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/codegen/gensupport'


module SOAP


module Mapping
  RubyTypeNamespace = 'http://www.ruby-lang.org/xmlns/ruby/type/1.6'
  RubyTypeInstanceNamespace =
    'http://www.ruby-lang.org/xmlns/ruby/type-instance'
  RubyCustomTypeNamespace = 'http://www.ruby-lang.org/xmlns/ruby/type/custom'
  ApacheSOAPTypeNamespace = 'http://xml.apache.org/xml-soap'


  # TraverseSupport breaks following thread variables.
  #   Thread.current[:SOAPMarshalDataKey]
  module TraverseSupport
    def mark_marshalled_obj(obj, soap_obj)
      raise if obj.nil?
      Thread.current[:SOAPMarshalDataKey][obj.__id__] = soap_obj
    end

    def mark_unmarshalled_obj(node, obj)
      return if obj.nil?
      # node.id is not Object#id but SOAPReference#id
      Thread.current[:SOAPMarshalDataKey][node.id] = obj
    end
  end


  EMPTY_OPT = {}
  def self.obj2soap(obj, registry = nil, type = nil, opt = EMPTY_OPT)
    registry ||= Mapping::DefaultRegistry
    soap_obj = nil
    protect_threadvars(:SOAPMarshalDataKey, :SOAPExternalCES, :SOAPMarshalNoReference) do
      Thread.current[:SOAPMarshalDataKey] = {}
      Thread.current[:SOAPExternalCES] = opt[:external_ces] || $KCODE
      Thread.current[:SOAPMarshalNoReference] = opt[:no_reference]
      soap_obj = _obj2soap(obj, registry, type)
    end
    soap_obj
  end

  def self.soap2obj(node, registry = nil, klass = nil, opt = EMPTY_OPT)
    registry ||= Mapping::DefaultRegistry
    obj = nil
    protect_threadvars(:SOAPMarshalDataKey, :SOAPExternalCES, :SOAPMarshalNoReference) do
      Thread.current[:SOAPMarshalDataKey] = {}
      Thread.current[:SOAPExternalCES] = opt[:external_ces] || $KCODE
      Thread.current[:SOAPMarshalNoReference] = opt[:no_reference]
      obj = _soap2obj(node, registry, klass)
    end
    obj
  end

  def self.ary2soap(ary, type_ns = XSD::Namespace, typename = XSD::AnyTypeLiteral, registry = nil, opt = EMPTY_OPT)
    registry ||= Mapping::DefaultRegistry
    type = XSD::QName.new(type_ns, typename)
    soap_ary = SOAPArray.new(ValueArrayName, 1, type)
    protect_threadvars(:SOAPMarshalDataKey, :SOAPExternalCES, :SOAPMarshalNoReference) do
      Thread.current[:SOAPMarshalDataKey] = {}
      Thread.current[:SOAPExternalCES] = opt[:external_ces] || $KCODE
      Thread.current[:SOAPMarshalNoReference] = opt[:no_reference]
      ary.each do |ele|
        soap_ary.add(_obj2soap(ele, registry, type))
      end
    end
    soap_ary
  end

  def self.ary2md(ary, rank, type_ns = XSD::Namespace, typename = XSD::AnyTypeLiteral, registry = nil, opt = EMPTY_OPT)
    registry ||= Mapping::DefaultRegistry
    type = XSD::QName.new(type_ns, typename)
    md_ary = SOAPArray.new(ValueArrayName, rank, type)
    protect_threadvars(:SOAPMarshalDataKey, :SOAPExternalCES, :SOAPMarshalNoReference) do
      Thread.current[:SOAPMarshalDataKey] = {}
      Thread.current[:SOAPExternalCES] = opt[:external_ces] || $KCODE
      Thread.current[:SOAPMarshalNoReference] = opt[:no_reference]
      add_md_ary(md_ary, ary, [], registry)
    end
    md_ary
  end

  def self.fault2exception(fault, registry = nil)
    registry ||= Mapping::DefaultRegistry
    detail = if fault.detail
        soap2obj(fault.detail, registry) || ""
      else
        ""
      end
    if detail.is_a?(Mapping::SOAPException)
      begin
        e = detail.to_e
	remote_backtrace = e.backtrace
        e.set_backtrace(nil)
        raise e # ruby sets current caller as local backtrace of e => e2.
      rescue Exception => e
	e.set_backtrace(remote_backtrace + e.backtrace[1..-1])
        raise
      end
    else
      fault.detail = detail
      fault.set_backtrace(
        if detail.is_a?(Array)
	  detail
        else
          [detail.to_s]
        end
      )
      raise
    end
  end

  def self._obj2soap(obj, registry, type = nil)
    if referent = Thread.current[:SOAPMarshalDataKey][obj.__id__] and
        !Thread.current[:SOAPMarshalNoReference]
      SOAPReference.new(referent)
    elsif registry
      registry.obj2soap(obj, type)
    else
      raise MappingError.new("no mapping registry given")
    end
  end

  def self._soap2obj(node, registry, klass = nil)
    if node.nil?
      return nil
    elsif node.is_a?(SOAPReference)
      target = node.__getobj__
      # target.id is not Object#id but SOAPReference#id
      if referent = Thread.current[:SOAPMarshalDataKey][target.id] and
          !Thread.current[:SOAPMarshalNoReference]
        return referent
      else
        return _soap2obj(target, registry, klass)
      end
    end
    return registry.soap2obj(node, klass)
  end

  if Object.respond_to?(:allocate)
    # ruby/1.7 or later.
    def self.create_empty_object(klass)
      klass.allocate
    end
  else
    MARSHAL_TAG = {
      String => ['"', 1],
      Regexp => ['/', 2],
      Array => ['[', 1],
      Hash => ['{', 1]
    }
    def self.create_empty_object(klass)
      if klass <= Struct
	name = klass.name
	return ::Marshal.load(sprintf("\004\006S:%c%s\000", name.length + 5, name))
      end
      if MARSHAL_TAG.has_key?(klass)
	tag, terminate = MARSHAL_TAG[klass]
	return ::Marshal.load(sprintf("\004\006%s%s", tag, "\000" * terminate))
      end
      MARSHAL_TAG.each do |k, v|
	if klass < k
	  name = klass.name
	  tag, terminate = v
	  return ::Marshal.load(sprintf("\004\006C:%c%s%s%s", name.length + 5, name, tag, "\000" * terminate))
	end
      end
      name = klass.name
      ::Marshal.load(sprintf("\004\006o:%c%s\000", name.length + 5, name))
    end
  end

  # Allow only (Letter | '_') (Letter | Digit | '-' | '_')* here.
  # Caution: '.' is not allowed here.
  # To follow XML spec., it should be NCName.
  #   (denied chars) => .[0-F][0-F]
  #   ex. a.b => a.2eb
  #
  def self.name2elename(name)
    name.gsub(/([^a-zA-Z0-9:_\-]+)/n) {
      '.' << $1.unpack('H2' * $1.size).join('.')
    }.gsub(/::/n, '..')
  end

  def self.elename2name(name)
    name.gsub(/\.\./n, '::').gsub(/((?:\.[0-9a-fA-F]{2})+)/n) {
      [$1.delete('.')].pack('H*')
    }
  end

  def self.const_from_name(name, lenient = false)
    const = ::Object
    name.sub(/\A::/, '').split('::').each do |const_str|
      if XSD::CodeGen::GenSupport.safeconstname?(const_str)
        if const.const_defined?(const_str)
          const = const.const_get(const_str)
          next
        end
      elsif lenient
        const_str = XSD::CodeGen::GenSupport.safeconstname(const_str)
        if const.const_defined?(const_str)
          const = const.const_get(const_str)
          next
        end
      end
      return nil
    end
    const
  end

  def self.class_from_name(name, lenient = false)
    const = const_from_name(name, lenient)
    if const.is_a?(::Class)
      const
    else
      nil
    end
  end

  def self.module_from_name(name, lenient = false)
    const = const_from_name(name, lenient)
    if const.is_a?(::Module)
      const
    else
      nil
    end
  end

  def self.class2qname(klass)
    name = schema_type_definition(klass)
    namespace = schema_ns_definition(klass)
    XSD::QName.new(namespace, name)
  end

  def self.class2element(klass)
    type = Mapping.class2qname(klass)
    type.name ||= Mapping.name2elename(klass.name)
    type.namespace ||= RubyCustomTypeNamespace
    type
  end

  def self.obj2element(obj)
    name = namespace = nil
    ivars = obj.instance_variables
    if ivars.include?('@schema_type')
      name = obj.instance_variable_get('@schema_type')
    end
    if ivars.include?('@schema_ns')
      namespace = obj.instance_variable_get('@schema_ns')
    end
    if !name or !namespace
      class2qname(obj.class)
    else
      XSD::QName.new(namespace, name)
    end
  end

  def self.define_singleton_method(obj, name, &block)
    sclass = (class << obj; self; end)
    sclass.class_eval {
      define_method(name, &block)
    }
  end

  def self.get_attribute(obj, attr_name)
    if obj.is_a?(::Hash)
      obj[attr_name] || obj[attr_name.intern]
    else
      name = XSD::CodeGen::GenSupport.safevarname(attr_name)
      if obj.instance_variables.include?('@' + name)
        obj.instance_variable_get('@' + name)
      elsif ((obj.is_a?(::Struct) or obj.is_a?(Marshallable)) and
          obj.respond_to?(name))
        obj.__send__(name)
      end
    end
  end

  def self.set_attributes(obj, values)
    if obj.is_a?(::SOAP::Mapping::Object)
      values.each do |attr_name, value|
        obj.__add_xmlele_value(attr_name, value)
      end
    else
      values.each do |attr_name, value|
        name = XSD::CodeGen::GenSupport.safevarname(attr_name)
        setter = name + "="
        if obj.respond_to?(setter)
          obj.__send__(setter, value)
        else
          obj.instance_variable_set('@' + name, value)
          begin
            define_attr_accessor(obj, name,
              proc { instance_variable_get('@' + name) },
              proc { |value| instance_variable_set('@' + name, value) })
          rescue TypeError
            # singleton class may not exist (e.g. Float)
          end
        end
      end
    end
  end

  def self.define_attr_accessor(obj, name, getterproc, setterproc = nil)
    define_singleton_method(obj, name, &getterproc)
    define_singleton_method(obj, name + '=', &setterproc) if setterproc
  end

  def self.schema_type_definition(klass)
    class_schema_variable(:schema_type, klass)
  end

  def self.schema_ns_definition(klass)
    class_schema_variable(:schema_ns, klass)
  end

  def self.schema_element_definition(klass)
    schema_element = class_schema_variable(:schema_element, klass) or return nil
    schema_ns = schema_ns_definition(klass)
    elements = []
    as_array = []
    schema_element.each do |varname, definition|
      class_name, name = definition
      if /\[\]$/ =~ class_name
        class_name = class_name.sub(/\[\]$/, '')
        as_array << (name ? name.name : varname)
      end
      elements << [name || XSD::QName.new(schema_ns, varname), class_name]
    end
    [elements, as_array]
  end

  def self.schema_attribute_definition(klass)
    class_schema_variable(:schema_attribute, klass)
  end

  class << Mapping
  private

    def class_schema_variable(sym, klass)
      var = "@@#{sym}"
      klass.class_variables.include?(var) ? klass.class_eval(var) : nil
    end

    def protect_threadvars(*symbols)
      backup = {}
      begin
        symbols.each do |sym|
          backup[sym] = Thread.current[sym]
        end
        yield
      ensure
        symbols.each do |sym|
          Thread.current[sym] = backup[sym]
        end
      end
    end

    def add_md_ary(md_ary, ary, indices, registry)
      for idx in 0..(ary.size - 1)
        if ary[idx].is_a?(Array)
          add_md_ary(md_ary, ary[idx], indices + [idx], registry)
        else
          md_ary[*(indices + [idx])] = _obj2soap(ary[idx], registry)
        end
      end
    end
  end
end


end
