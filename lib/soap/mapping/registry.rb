=begin
SOAP4R - Mapping registry.
Copyright (C) 2000, 2001, 2002, 2003  NAKAMURA, Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end


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


# Inner class to pass an exception.
class SOAPException; include Marshallable
  attr_reader :excn_type_name, :message, :backtrace, :cause
  def initialize(e)
    @excn_type_name = Mapping.name2elename(e.class.to_s)
    @message = e.message
    @backtrace = e.backtrace
    @cause = e
  end

  def to_e
    if @cause.is_a?(::Exception)
      @cause.extend(::SOAP::Mapping::MappedException)
      return @cause
    end
    klass = Mapping.class_from_name(
      Mapping.elename2name(@excn_type_name.to_s))
    if klass.nil?
      raise RuntimeError.new(@message)
    end
    unless klass <= ::Exception
      raise NameError.new
    end
    obj = klass.new(@message)
    obj.extend(::SOAP::Mapping::MappedException)
    obj
  end

  def set_backtrace(e)
    e.set_backtrace(
      if @backtrace.is_a?(Array)
        @backtrace
      else
        [@backtrace.inspect]
      end
  )
  end
end


# For anyType object: SOAP::Mapping::Object not ::Object
class Object; include Marshallable
  def set_property(name, value)
    var_name = name
    begin
      instance_eval <<-EOS
        def #{ var_name }
          @#{ var_name }
        end

        def #{ var_name }=(value)
          @#{ var_name } = value
        end
      EOS
      self.send(var_name + '=', value)
    rescue SyntaxError
      var_name = safe_name(var_name)
      retry
    end

    var_name
  end

  def members
    instance_variables.collect { |str| str[1..-1] }
  end

  def [](name)
    if self.respond_to?(name)
      self.send(name)
    else
      self.send(safe_name(name))
    end
  end

  def []=(name, value)
    if self.respond_to?(name)
      self.send(name + '=', value)
    else
      self.send(safe_name(name) + '=', value)
    end
  end

private

  def safe_name(name)
    require 'md5'
    "var_" << MD5.new(name).hexdigest
  end
end


class MappingError < Error; end


class Registry
  class Map
    def initialize(registry)
      @map = []
      @registry = registry
    end

    def obj2soap(klass, obj)
      @map.each do |obj_class, soap_class, factory, info|
        if klass == obj_class or
            (info[:derived_class] and klass <= obj_class)
          ret = factory.obj2soap(soap_class, obj, info, @registry)
          return ret if ret
        end
      end
      nil
    end

    def soap2obj(klass, node)
      @map.each do |obj_class, soap_class, factory, info|
        if klass == soap_class or
            (info[:derived_class] and klass <= soap_class)
          conv, obj = factory.soap2obj(obj_class, node, info, @registry)
          return true, obj if conv
        end
      end
      return false
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
      @map.unshift([obj_class, soap_class, factory, info])
    end

    def clear
      @map.clear
    end

    def find_mapped_soap_class(target_obj_class)
      @map.each do |obj_class, soap_class, factory, info|
        if obj_class == target_obj_class
          return soap_class
        end
      end
      nil
    end

    def find_mapped_obj_class(target_soap_class)
      @map.each do |obj_class, soap_class, factory, info|
        if soap_class == target_soap_class
          return obj_class
        end
      end
      nil
    end
  end

  StringFactory = StringFactory_.new
  BasetypeFactory = BasetypeFactory_.new
  DateTimeFactory = DateTimeFactory_.new
  ArrayFactory = ArrayFactory_.new
  Base64Factory = Base64Factory_.new
  TypedArrayFactory = TypedArrayFactory_.new
  TypedStructFactory = TypedStructFactory_.new

  HashFactory = HashFactory_.new

  SOAPBaseMap = [
    [::NilClass,     ::SOAP::SOAPNil,        BasetypeFactory],
    [::TrueClass,    ::SOAP::SOAPBoolean,    BasetypeFactory],
    [::FalseClass,   ::SOAP::SOAPBoolean,    BasetypeFactory],
    [::String,       ::SOAP::SOAPString,     StringFactory],
    [::DateTime,     ::SOAP::SOAPDateTime,   BasetypeFactory],
    [::Date,         ::SOAP::SOAPDateTime,   BasetypeFactory],
    [::Date,         ::SOAP::SOAPDate,       BasetypeFactory],
    [::Time,         ::SOAP::SOAPDateTime,   BasetypeFactory],
    [::Time,         ::SOAP::SOAPTime,       BasetypeFactory],
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
    [::URI::Generic, ::SOAP::SOAPAnyURI,     BasetypeFactory,
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

    [::Array,        ::SOAP::SOAPArray,      ArrayFactory,
      {:derived_class => true}],

    [::Hash,         ::SOAP::SOAPStruct,     HashFactory],
    [::SOAP::Mapping::SOAPException,
		     ::SOAP::SOAPStruct,     TypedStructFactory,
      {:type => XSD::QName.new(RubyCustomTypeNamespace, "SOAPException")}],
 ]

  RubyOriginalMap = [
    [::NilClass,     ::SOAP::SOAPNil,        BasetypeFactory],
    [::TrueClass,    ::SOAP::SOAPBoolean,    BasetypeFactory],
    [::FalseClass,   ::SOAP::SOAPBoolean,    BasetypeFactory],
    [::String,       ::SOAP::SOAPString,     StringFactory],
    [::DateTime,     ::SOAP::SOAPDateTime,   BasetypeFactory],
    [::Date,         ::SOAP::SOAPDateTime,   BasetypeFactory],
    [::Date,         ::SOAP::SOAPDate,       BasetypeFactory],
    [::Time,         ::SOAP::SOAPDateTime,   BasetypeFactory],
    [::Time,         ::SOAP::SOAPTime,       BasetypeFactory],
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
    [::URI::Generic, ::SOAP::SOAPAnyURI,     BasetypeFactory,
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

    # Does not allow Array's subclass here.
    [::Array,        ::SOAP::SOAPArray,      ArrayFactory],

    [::Hash,         ::SOAP::SOAPStruct,     HashFactory],
    [::SOAP::Mapping::SOAPException,
                     ::SOAP::SOAPStruct,     TypedStructFactory,
      {:type => XSD::QName.new(RubyCustomTypeNamespace, "SOAPException")}],
  ]

  def initialize(config = {})
    @config = config
    @map = Map.new(self)
    if @config[:allow_original_mapping]
      allow_original_mapping = true
      @map.init(RubyOriginalMap)
    else
      allow_original_mapping = false
      @map.init(SOAPBaseMap)
    end

    allow_untyped_struct = @config.key?(:allow_untyped_struct) ?
      @config[:allow_untyped_struct] : true
    @rubytype_factory = RubytypeFactory.new(
      :allow_untyped_struct => allow_untyped_struct,
      :allow_original_mapping => allow_original_mapping
    )
    @default_factory = @rubytype_factory
    @excn_handler_obj2soap = nil
    @excn_handler_soap2obj = nil
  end

  def add(obj_class, soap_class, factory, info = nil)
    @map.add(obj_class, soap_class, factory, info)
  end
  alias :set :add

  # This mapping registry ignores type hint.
  def obj2soap(klass, obj, type = nil)
    ret = nil
    if obj.is_a?(SOAPStruct) || obj.is_a?(SOAPArray)
      obj.replace do |ele|
        Mapping._obj2soap(ele, self)
      end
      return obj
    elsif obj.is_a?(SOAPBasetype)
      return obj
    end
    begin 
      ret = @map.obj2soap(klass, obj) ||
        @default_factory.obj2soap(klass, obj, nil, self)
    rescue MappingError
    end
    return ret if ret

    if @excn_handler_obj2soap
      ret = @excn_handler_obj2soap.call(obj) { |yield_obj|
        Mapping._obj2soap(yield_obj, self)
      }
    end
    return ret if ret

    raise MappingError.new("Cannot map #{ klass.name } to SOAP/OM.")
  end

  def soap2obj(klass, node)
    if node.extraattr.key?(RubyTypeName)
      conv, obj = @rubytype_factory.soap2obj(klass, node, nil, self)
      return obj if conv
    else
      conv, obj = @map.soap2obj(klass, node)
      return obj if conv
      conv, obj = @default_factory.soap2obj(klass, node, nil, self)
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

  def default_factory=(factory)
    @default_factory = factory
  end

  def excn_handler_obj2soap=(handler)
    @excn_handler_obj2soap = handler
  end

  def excn_handler_soap2obj=(handler)
    @excn_handler_soap2obj = handler
  end

  def find_mapped_soap_class(obj_class)
    @map.find_mapped_soap_class(obj_class)
  end

  def find_mapped_obj_class(soap_class)
    @map.find_mapped_obj_class(soap_class)
  end
end


DefaultRegistry = Registry.new
RubyOriginalRegistry = Registry.new(:allow_original_mapping => true)


end
end
