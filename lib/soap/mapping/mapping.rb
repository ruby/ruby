# SOAP4R - Ruby type mapping utility.
# Copyright (C) 2000, 2001, 2003 NAKAMURA Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


module SOAP


module Mapping
  RubyTypeNamespace = 'http://www.ruby-lang.org/xmlns/ruby/type/1.6'
  RubyTypeInstanceNamespace =
    'http://www.ruby-lang.org/xmlns/ruby/type-instance'
  RubyCustomTypeNamespace = 'http://www.ruby-lang.org/xmlns/ruby/type/custom'
  ApacheSOAPTypeNamespace = 'http://xml.apache.org/xml-soap'


  # TraverseSupport breaks Thread.current[:SOAPMarshalDataKey].
  module TraverseSupport
    def mark_marshalled_obj(obj, soap_obj)
      Thread.current[:SOAPMarshalDataKey][obj.__id__] = soap_obj
    end

    def mark_unmarshalled_obj(node, obj)
      # node.id is not Object#id but SOAPReference#id
      Thread.current[:SOAPMarshalDataKey][node.id] = obj
    end
  end


  def self.obj2soap(obj, registry = nil, type = nil)
    registry ||= Mapping::DefaultRegistry
    Thread.current[:SOAPMarshalDataKey] = {}
    soap_obj = _obj2soap(obj, registry, type)
    Thread.current[:SOAPMarshalDataKey] = nil
    soap_obj
  end

  def self.soap2obj(node, registry = nil)
    registry ||= Mapping::DefaultRegistry
    Thread.current[:SOAPMarshalDataKey] = {}
    obj = _soap2obj(node, registry)
    Thread.current[:SOAPMarshalDataKey] = nil
    obj
  end

  def self.ary2soap(ary, type_ns = XSD::Namespace, typename = XSD::AnyTypeLiteral, registry = nil)
    registry ||= Mapping::DefaultRegistry
    type = XSD::QName.new(type_ns, typename)
    soap_ary = SOAPArray.new(ValueArrayName, 1, type)
    Thread.current[:SOAPMarshalDataKey] = {}
    ary.each do |ele|
      soap_ary.add(_obj2soap(ele, registry, type))
    end
    Thread.current[:SOAPMarshalDataKey] = nil
    soap_ary
  end

  def self.ary2md(ary, rank, type_ns = XSD::Namespace, typename = XSD::AnyTypeLiteral, registry = nil)
    registry ||= Mapping::DefaultRegistry
    type = XSD::QName.new(type_ns, typename)
    md_ary = SOAPArray.new(ValueArrayName, rank, type)
    Thread.current[:SOAPMarshalDataKey] = {}
    add_md_ary(md_ary, ary, [], registry)
    Thread.current[:SOAPMarshalDataKey] = nil
    md_ary
  end

  def self.fault2exception(e, registry = nil)
    registry ||= Mapping::DefaultRegistry
    detail = if e.detail
        soap2obj(e.detail, registry) || ""
      else
        ""
      end
    if detail.is_a?(Mapping::SOAPException)
      begin
	remote_backtrace = detail.to_e.backtrace
        raise detail.to_e
      rescue Exception => e2
	e2.set_backtrace(remote_backtrace + e2.backtrace)
        raise
      end
    else
      e.detail = detail
      e.set_backtrace(
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
    if referent = Thread.current[:SOAPMarshalDataKey][obj.__id__]
      soap_obj = SOAPReference.new
      soap_obj.__setobj__(referent)
      soap_obj
    else
      registry.obj2soap(obj.class, obj, type)
    end
  end

  def self._soap2obj(node, registry)
    if node.is_a?(SOAPReference)
      target = node.__getobj__
      # target.id is not Object#id but SOAPReference#id
      if referent = Thread.current[:SOAPMarshalDataKey][target.id]
        return referent
      else
        return _soap2obj(target, registry)
      end
    end
    return registry.soap2obj(node.class, node)
  end

  def self.set_instance_vars(obj, values)
    values.each do |name, value|
      setter = name + "="
      if obj.respond_to?(setter)
	obj.__send__(setter, value)
      else
	obj.instance_eval("@#{ name } = value")
      end
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

  def self.class_from_name(name)
    if /^[A-Z]/ !~ name
      return nil
    end
    klass = ::Object
    name.split('::').each do |klass_str|
      if klass.const_defined?(klass_str)
        klass = klass.const_get(klass_str)
      else
        return nil
      end
    end
    klass
  end

  def self.class2qname(klass)
    name = if klass.class_variables.include?("@@schema_type")
        klass.class_eval("@@schema_type")
      else
        nil
      end
    namespace = if klass.class_variables.include?("@@schema_ns")
        klass.class_eval("@@schema_ns")
      else
        nil
      end
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
    if ivars.include?("@schema_type")
      name = obj.instance_eval("@schema_type")
    end
    if ivars.include?("@schema_ns")
      namespace = obj.instance_eval("@schema_ns")
    end
    if !name or !namespace
      class2qname(obj.class)
    else
      XSD::QName.new(namespace, name)
    end
  end

  class << Mapping
  private
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
