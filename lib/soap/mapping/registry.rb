# SOAP4R - Mapping registry.
# Copyright (C) 2000, 2001, 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/baseData'
require 'soap/mapping/mapping'
require 'soap/mapping/typeMap'
require 'soap/mapping/factory'
require 'soap/mapping/rubytypeFactory'


module SOAP


module Marshallable
  # @@type_ns = Mapping::RubyCustomTypeNamespace
end


module Mapping

  
module MappedException; end


RubyTypeName = XSD::QName.new(RubyTypeInstanceNamespace, 'rubyType')
RubyExtendName = XSD::QName.new(RubyTypeInstanceNamespace, 'extends')
RubyIVarName = XSD::QName.new(RubyTypeInstanceNamespace, 'ivars')


# Inner class to pass an exception.
class SOAPException; include Marshallable
  attr_reader :excn_type_name, :cause
  def initialize(e)
    @excn_type_name = Mapping.name2elename(e.class.to_s)
    @cause = e
  end

  def to_e
    if @cause.is_a?(::Exception)
      @cause.extend(::SOAP::Mapping::MappedException)
      return @cause
    elsif @cause.respond_to?(:message) and @cause.respond_to?(:backtrace)
      e = RuntimeError.new(@cause.message)
      e.set_backtrace(@cause.backtrace)
      return e
    end
    klass = Mapping.class_from_name(
      Mapping.elename2name(@excn_type_name.to_s))
    if klass.nil? or not klass <= ::Exception
      return RuntimeError.new(@cause.inspect)
    end
    obj = klass.new(@cause.message)
    obj.extend(::SOAP::Mapping::MappedException)
    obj
  end
end


# For anyType object: SOAP::Mapping::Object not ::Object
class Object; include Marshallable
  def initialize
    @__soap_value_type = {}
    @__soap_value = {}
  end

  def [](name)
    @__soap_value[name]
  end

  def []=(name, value)
    @__soap_value[name] = value
  end

  def __soap_set_property(name, value)
    unless @__soap_value.key?(name)
      __define_attr_accessor(name)
    end
    __soap_set_property_value(name, value)
  end

private

  def __soap_set_property_value(name, value)
    org = self[name]
    case @__soap_value_type[name]
    when :single
      self[name] = [org, value]
      @__soap_value_type[name] = :multi
    when :multi
      org << value
    else
      self[name] = value
      @__soap_value_type[name] = :single
    end
    value
  end

  def __define_attr_accessor(name)
    sclass = class << self; self; end
    sclass.__send__(:define_method, name, proc {
      self[name]
    })
    sclass.__send__(:define_method, name + '=', proc { |value|
      self[name] = value
    })
  end
end


class MappingError < Error; end


class Registry
  class Map
    def initialize(registry)
      @obj2soap = {}
      @soap2obj = {}
      @registry = registry
    end

    def obj2soap(obj, type_qname = nil)
      klass = obj.class
      if map = @obj2soap[klass]
        map.each do |soap_class, factory, info|
          ret = factory.obj2soap(soap_class, obj, info, @registry)
          return ret if ret
        end
      end
      ancestors = klass.ancestors[1..-3] # except itself, Object and Kernel
      ancestors.each do |klass|
        if map = @obj2soap[klass]
          map.each do |soap_class, factory, info|
            if info[:derived_class]
              ret = factory.obj2soap(soap_class, obj, info, @registry)
              return ret if ret
            end
          end
        end
      end
      nil
    end

    def soap2obj(node)
      klass = node.class
      if map = @soap2obj[klass]
        map.each do |obj_class, factory, info|
          conv, obj = factory.soap2obj(obj_class, node, info, @registry)
          return true, obj if conv
        end
      end
      return false, nil
    end

    # Give priority to former entry.
    def init(init_map = [])
      clear
      init_map.reverse_each do |obj_class, soap_class, factory, info|
        add(obj_class, soap_class, factory, info)
      end
    end

    # Give priority to latter entry.
    def add(obj_class, soap_class, factory, info)
      info ||= {}
      (@obj2soap[obj_class] ||= []).unshift([soap_class, factory, info])
      (@soap2obj[soap_class] ||= []).unshift([obj_class, factory, info])
    end

    def clear
      @obj2soap.clear
      @soap2obj.clear
    end

    def find_mapped_soap_class(target_obj_class)
      @obj2soap[target_obj_class][0]
    end

    def find_mapped_obj_class(target_soap_class)
      @soap2obj[target_soap_class][0]
    end
  end

  StringFactory = StringFactory_.new
  BasetypeFactory = BasetypeFactory_.new
  DateTimeFactory = DateTimeFactory_.new
  ArrayFactory = ArrayFactory_.new
  Base64Factory = Base64Factory_.new
  URIFactory = URIFactory_.new
  TypedArrayFactory = TypedArrayFactory_.new
  TypedStructFactory = TypedStructFactory_.new

  HashFactory = HashFactory_.new

  SOAPBaseMap = [
    [::NilClass,     ::SOAP::SOAPNil,        BasetypeFactory],
    [::TrueClass,    ::SOAP::SOAPBoolean,    BasetypeFactory],
    [::FalseClass,   ::SOAP::SOAPBoolean,    BasetypeFactory],
    [::String,       ::SOAP::SOAPString,     StringFactory],
    [::DateTime,     ::SOAP::SOAPDateTime,   DateTimeFactory],
    [::Date,         ::SOAP::SOAPDateTime,   DateTimeFactory],
    [::Date,         ::SOAP::SOAPDate,       DateTimeFactory],
    [::Time,         ::SOAP::SOAPDateTime,   DateTimeFactory],
    [::Time,         ::SOAP::SOAPTime,       DateTimeFactory],
    [::Float,        ::SOAP::SOAPDouble,     BasetypeFactory,
      {:derived_class => true}],
    [::Float,        ::SOAP::SOAPFloat,      BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPInt,        BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPLong,       BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPInteger,    BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPShort,      BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPByte,       BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPNonPositiveInteger, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPNegativeInteger, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPNonNegativeInteger, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPPositiveInteger, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPUnsignedLong, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPUnsignedInt, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPUnsignedShort, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPUnsignedByte, BasetypeFactory,
      {:derived_class => true}],
    [::URI::Generic, ::SOAP::SOAPAnyURI,     URIFactory,
      {:derived_class => true}],
    [::String,       ::SOAP::SOAPBase64,     Base64Factory],
    [::String,       ::SOAP::SOAPHexBinary,  Base64Factory],
    [::String,       ::SOAP::SOAPDecimal,    BasetypeFactory],
    [::String,       ::SOAP::SOAPDuration,   BasetypeFactory],
    [::String,       ::SOAP::SOAPGYearMonth, BasetypeFactory],
    [::String,       ::SOAP::SOAPGYear,      BasetypeFactory],
    [::String,       ::SOAP::SOAPGMonthDay,  BasetypeFactory],
    [::String,       ::SOAP::SOAPGDay,       BasetypeFactory],
    [::String,       ::SOAP::SOAPGMonth,     BasetypeFactory],
    [::String,       ::SOAP::SOAPQName,      BasetypeFactory],

    [::Hash,         ::SOAP::SOAPArray,      HashFactory],
    [::Hash,         ::SOAP::SOAPStruct,     HashFactory],

    [::Array,        ::SOAP::SOAPArray,      ArrayFactory,
      {:derived_class => true}],

    [::SOAP::Mapping::SOAPException,
		     ::SOAP::SOAPStruct,     TypedStructFactory,
      {:type => XSD::QName.new(RubyCustomTypeNamespace, "SOAPException")}],
 ]

  RubyOriginalMap = [
    [::NilClass,     ::SOAP::SOAPNil,        BasetypeFactory],
    [::TrueClass,    ::SOAP::SOAPBoolean,    BasetypeFactory],
    [::FalseClass,   ::SOAP::SOAPBoolean,    BasetypeFactory],
    [::String,       ::SOAP::SOAPString,     StringFactory],
    [::DateTime,     ::SOAP::SOAPDateTime,   DateTimeFactory],
    [::Date,         ::SOAP::SOAPDateTime,   DateTimeFactory],
    [::Date,         ::SOAP::SOAPDate,       DateTimeFactory],
    [::Time,         ::SOAP::SOAPDateTime,   DateTimeFactory],
    [::Time,         ::SOAP::SOAPTime,       DateTimeFactory],
    [::Float,        ::SOAP::SOAPDouble,     BasetypeFactory,
      {:derived_class => true}],
    [::Float,        ::SOAP::SOAPFloat,      BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPInt,        BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPLong,       BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPInteger,    BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPShort,      BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPByte,       BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPNonPositiveInteger, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPNegativeInteger, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPNonNegativeInteger, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPPositiveInteger, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPUnsignedLong, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPUnsignedInt, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPUnsignedShort, BasetypeFactory,
      {:derived_class => true}],
    [::Integer,      ::SOAP::SOAPUnsignedByte, BasetypeFactory,
      {:derived_class => true}],
    [::URI::Generic, ::SOAP::SOAPAnyURI,     URIFactory,
      {:derived_class => true}],
    [::String,       ::SOAP::SOAPBase64,     Base64Factory],
    [::String,       ::SOAP::SOAPHexBinary,  Base64Factory],
    [::String,       ::SOAP::SOAPDecimal,    BasetypeFactory],
    [::String,       ::SOAP::SOAPDuration,   BasetypeFactory],
    [::String,       ::SOAP::SOAPGYearMonth, BasetypeFactory],
    [::String,       ::SOAP::SOAPGYear,      BasetypeFactory],
    [::String,       ::SOAP::SOAPGMonthDay,  BasetypeFactory],
    [::String,       ::SOAP::SOAPGDay,       BasetypeFactory],
    [::String,       ::SOAP::SOAPGMonth,     BasetypeFactory],
    [::String,       ::SOAP::SOAPQName,      BasetypeFactory],

    [::Hash,         ::SOAP::SOAPArray,      HashFactory],
    [::Hash,         ::SOAP::SOAPStruct,     HashFactory],

    # Does not allow Array's subclass here.
    [::Array,        ::SOAP::SOAPArray,      ArrayFactory],

    [::SOAP::Mapping::SOAPException,
                     ::SOAP::SOAPStruct,     TypedStructFactory,
      {:type => XSD::QName.new(RubyCustomTypeNamespace, "SOAPException")}],
  ]

  attr_accessor :default_factory
  attr_accessor :excn_handler_obj2soap
  attr_accessor :excn_handler_soap2obj

  def initialize(config = {})
    @config = config
    @map = Map.new(self)
    if @config[:allow_original_mapping]
      @allow_original_mapping = true
      @map.init(RubyOriginalMap)
    else
      @allow_original_mapping = false
      @map.init(SOAPBaseMap)
    end
    @allow_untyped_struct = @config.key?(:allow_untyped_struct) ?
      @config[:allow_untyped_struct] : true
    @rubytype_factory = RubytypeFactory.new(
      :allow_untyped_struct => @allow_untyped_struct,
      :allow_original_mapping => @allow_original_mapping
    )
    @default_factory = @rubytype_factory
    @excn_handler_obj2soap = nil
    @excn_handler_soap2obj = nil
  end

  def add(obj_class, soap_class, factory, info = nil)
    @map.add(obj_class, soap_class, factory, info)
  end
  alias set add

  # This mapping registry ignores type hint.
  def obj2soap(obj, type_qname = nil)
    soap = _obj2soap(obj, type_qname)
    if @allow_original_mapping
      addextend2soap(soap, obj)
    end
    soap
  end

  def soap2obj(node)
    obj = _soap2obj(node)
    if @allow_original_mapping
      addextend2obj(obj, node.extraattr[RubyExtendName])
      addiv2obj(obj, node.extraattr[RubyIVarName])
    end
    obj
  end

  def find_mapped_soap_class(obj_class)
    @map.find_mapped_soap_class(obj_class)
  end

  def find_mapped_obj_class(soap_class)
    @map.find_mapped_obj_class(soap_class)
  end

private

  def _obj2soap(obj, type_qname)
    ret = nil
    if obj.is_a?(SOAPStruct) or obj.is_a?(SOAPArray)
      obj.replace do |ele|
        Mapping._obj2soap(ele, self)
      end
      return obj
    elsif obj.is_a?(SOAPBasetype)
      return obj
    end
    begin 
      ret = @map.obj2soap(obj, type_qname) ||
        @default_factory.obj2soap(nil, obj, nil, self)
      return ret if ret
    rescue MappingError
    end
    if @excn_handler_obj2soap
      ret = @excn_handler_obj2soap.call(obj) { |yield_obj|
        Mapping._obj2soap(yield_obj, self)
      }
      return ret if ret
    end
    raise MappingError.new("Cannot map #{ obj.class.name } to SOAP/OM.")
  end

  # Might return nil as a mapping result.
  def _soap2obj(node)
    if node.extraattr.key?(RubyTypeName)
      conv, obj = @rubytype_factory.soap2obj(nil, node, nil, self)
      return obj if conv
    else
      conv, obj = @map.soap2obj(node)
      return obj if conv
      conv, obj = @default_factory.soap2obj(nil, node, nil, self)
      return obj if conv
    end
    if @excn_handler_soap2obj
      begin
        return @excn_handler_soap2obj.call(node) { |yield_node|
	    Mapping._soap2obj(yield_node, self)
	  }
      rescue Exception
      end
    end
    raise MappingError.new("Cannot map #{ node.type.name } to Ruby object.")
  end

  def addiv2obj(obj, attr)
    return unless attr
    vars = {}
    attr.__getobj__.each do |name, value|
      vars[name] = Mapping._soap2obj(value, self)
    end
    Mapping.set_instance_vars(obj, vars)
  end

  if RUBY_VERSION >= '1.8.0'
    def addextend2obj(obj, attr)
      return unless attr
      attr.split(/ /).reverse_each do |mstr|
	obj.extend(Mapping.class_from_name(mstr))
      end
    end
  else
    # (class < false; self; end).ancestors includes "TrueClass" under 1.6...
    def addextend2obj(obj, attr)
      return unless attr
      attr.split(/ /).reverse_each do |mstr|
	m = Mapping.class_from_name(mstr)
	obj.extend(m) if m.class == Module
      end
    end
  end

  def addextend2soap(node, obj)
    return if obj.is_a?(Symbol) or obj.is_a?(Fixnum)
    list = (class << obj; self; end).ancestors - obj.class.ancestors
    unless list.empty?
      node.extraattr[RubyExtendName] = list.collect { |c|
	if c.name.empty?
  	  raise TypeError.new("singleton can't be dumped #{ obj }")
   	end
	c.name
      }.join(" ")
    end
  end

end


DefaultRegistry = Registry.new
RubyOriginalRegistry = Registry.new(:allow_original_mapping => true)


end
end
