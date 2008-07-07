# SOAP4R - Ruby type mapping factory.
# Copyright (C) 2000-2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


module SOAP
module Mapping


class RubytypeFactory < Factory
  TYPE_STRING = XSD::QName.new(RubyTypeNamespace, 'String')
  TYPE_TIME = XSD::QName.new(RubyTypeNamespace, 'Time')
  TYPE_ARRAY = XSD::QName.new(RubyTypeNamespace, 'Array')
  TYPE_REGEXP = XSD::QName.new(RubyTypeNamespace, 'Regexp')
  TYPE_RANGE = XSD::QName.new(RubyTypeNamespace, 'Range')
  TYPE_CLASS = XSD::QName.new(RubyTypeNamespace, 'Class')
  TYPE_MODULE = XSD::QName.new(RubyTypeNamespace, 'Module')
  TYPE_SYMBOL = XSD::QName.new(RubyTypeNamespace, 'Symbol')
  TYPE_STRUCT = XSD::QName.new(RubyTypeNamespace, 'Struct')
  TYPE_HASH = XSD::QName.new(RubyTypeNamespace, 'Map')

  def initialize(config = {})
    @config = config
    @allow_untyped_struct = @config.key?(:allow_untyped_struct) ?
      @config[:allow_untyped_struct] : true
    @allow_original_mapping = @config.key?(:allow_original_mapping) ?
      @config[:allow_original_mapping] : false
    @string_factory = StringFactory_.new(true)
    @basetype_factory = BasetypeFactory_.new(true)
    @datetime_factory = DateTimeFactory_.new(true)
    @array_factory = ArrayFactory_.new(true)
    @hash_factory = HashFactory_.new(true)
  end

  def obj2soap(soap_class, obj, info, map)
    param = nil
    case obj
    when ::String
      unless @allow_original_mapping
        return nil
      end
      param = @string_factory.obj2soap(SOAPString, obj, info, map)
      if obj.class != String
        param.extraattr[RubyTypeName] = obj.class.name
      end
      addiv2soapattr(param, obj, map)
    when ::Time
      unless @allow_original_mapping
        return nil
      end
      param = @datetime_factory.obj2soap(SOAPDateTime, obj, info, map)
      if obj.class != Time
        param.extraattr[RubyTypeName] = obj.class.name
      end
      addiv2soapattr(param, obj, map)
    when ::Array
      unless @allow_original_mapping
        return nil
      end
      param = @array_factory.obj2soap(nil, obj, info, map)
      if obj.class != Array
        param.extraattr[RubyTypeName] = obj.class.name
      end
      addiv2soapattr(param, obj, map)
    when ::NilClass
      unless @allow_original_mapping
        return nil
      end
      param = @basetype_factory.obj2soap(SOAPNil, obj, info, map)
      addiv2soapattr(param, obj, map)
    when ::FalseClass, ::TrueClass
      unless @allow_original_mapping
        return nil
      end
      param = @basetype_factory.obj2soap(SOAPBoolean, obj, info, map)
      addiv2soapattr(param, obj, map)
    when ::Integer
      unless @allow_original_mapping
        return nil
      end
      param = @basetype_factory.obj2soap(SOAPInt, obj, info, map)
      param ||= @basetype_factory.obj2soap(SOAPInteger, obj, info, map)
      param ||= @basetype_factory.obj2soap(SOAPDecimal, obj, info, map)
      addiv2soapattr(param, obj, map)
    when ::Float
      unless @allow_original_mapping
        return nil
      end
      param = @basetype_factory.obj2soap(SOAPDouble, obj, info, map)
      if obj.class != Float
        param.extraattr[RubyTypeName] = obj.class.name
      end
      addiv2soapattr(param, obj, map)
    when ::Hash
      unless @allow_original_mapping
        return nil
      end
      if obj.respond_to?(:default_proc) && obj.default_proc
        raise TypeError.new("cannot dump hash with default proc")
      end
      param = SOAPStruct.new(TYPE_HASH)
      mark_marshalled_obj(obj, param)
      if obj.class != Hash
        param.extraattr[RubyTypeName] = obj.class.name
      end
      obj.each do |key, value|
        elem = SOAPStruct.new # Undefined type.
        elem.add("key", Mapping._obj2soap(key, map))
        elem.add("value", Mapping._obj2soap(value, map))
        param.add("item", elem)
      end
      param.add('default', Mapping._obj2soap(obj.default, map))
      addiv2soapattr(param, obj, map)
    when ::Regexp
      unless @allow_original_mapping
        return nil
      end
      param = SOAPStruct.new(TYPE_REGEXP)
      mark_marshalled_obj(obj, param)
      if obj.class != Regexp
        param.extraattr[RubyTypeName] = obj.class.name
      end
      param.add('source', SOAPBase64.new(obj.source))
      if obj.respond_to?('options')
        # Regexp#options is from Ruby/1.7
        options = obj.options
      else
        options = 0
        obj.inspect.sub(/^.*\//, '').each_byte do |c|
          options += case c
            when ?i
              1
            when ?x
              2
            when ?m
              4
            when ?n
              16
            when ?e
              32
            when ?s
              48
            when ?u
              64
            end
        end
      end
      param.add('options', SOAPInt.new(options))
      addiv2soapattr(param, obj, map)
    when ::Range
      unless @allow_original_mapping
        return nil
      end
      param = SOAPStruct.new(TYPE_RANGE)
      mark_marshalled_obj(obj, param)
      if obj.class != Range
        param.extraattr[RubyTypeName] = obj.class.name
      end
      param.add('begin', Mapping._obj2soap(obj.begin, map))
      param.add('end', Mapping._obj2soap(obj.end, map))
      param.add('exclude_end', SOAP::SOAPBoolean.new(obj.exclude_end?))
      addiv2soapattr(param, obj, map)
    when ::Class
      unless @allow_original_mapping
        return nil
      end
      if obj.to_s[0] == ?#
        raise TypeError.new("can't dump anonymous class #{obj}")
      end
      param = SOAPStruct.new(TYPE_CLASS)
      mark_marshalled_obj(obj, param)
      param.add('name', SOAPString.new(obj.name))
      addiv2soapattr(param, obj, map)
    when ::Module
      unless @allow_original_mapping
        return nil
      end
      if obj.to_s[0] == ?#
        raise TypeError.new("can't dump anonymous module #{obj}")
      end
      param = SOAPStruct.new(TYPE_MODULE)
      mark_marshalled_obj(obj, param)
      param.add('name', SOAPString.new(obj.name))
      addiv2soapattr(param, obj, map)
    when ::Symbol
      unless @allow_original_mapping
        return nil
      end
      param = SOAPStruct.new(TYPE_SYMBOL)
      mark_marshalled_obj(obj, param)
      param.add('id', SOAPString.new(obj.id2name))
      addiv2soapattr(param, obj, map)
    when ::Struct
      unless @allow_original_mapping
        # treat it as an user defined class. [ruby-talk:104980]
        #param = unknownobj2soap(soap_class, obj, info, map)
        param = SOAPStruct.new(XSD::AnyTypeName)
        mark_marshalled_obj(obj, param)
        obj.members.each do |member|
          param.add(Mapping.name2elename(member),
            Mapping._obj2soap(obj[member], map))
        end
      else
        param = SOAPStruct.new(TYPE_STRUCT)
        mark_marshalled_obj(obj, param)
        param.add('type', ele_type = SOAPString.new(obj.class.to_s))
        ele_member = SOAPStruct.new
        obj.members.each do |member|
          ele_member.add(Mapping.name2elename(member),
            Mapping._obj2soap(obj[member], map))
        end
        param.add('member', ele_member)
        addiv2soapattr(param, obj, map)
      end
    when ::IO, ::Binding, ::Continuation, ::Data, ::Dir, ::File::Stat,
        ::MatchData, Method, ::Proc, ::Thread, ::ThreadGroup
        # from 1.8: Process::Status, UnboundMethod
      return nil
    when ::SOAP::Mapping::Object
      param = SOAPStruct.new(XSD::AnyTypeName)
      mark_marshalled_obj(obj, param)
      obj.__xmlele.each do |key, value|
        param.add(key.name, Mapping._obj2soap(value, map))
      end
      obj.__xmlattr.each do |key, value|
        param.extraattr[key] = value
      end
    when ::Exception
      typestr = Mapping.name2elename(obj.class.to_s)
      param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, typestr))
      mark_marshalled_obj(obj, param)
      param.add('message', Mapping._obj2soap(obj.message, map))
      param.add('backtrace', Mapping._obj2soap(obj.backtrace, map))
      addiv2soapattr(param, obj, map)
    else
      param = unknownobj2soap(soap_class, obj, info, map)
    end
    param
  end

  def soap2obj(obj_class, node, info, map)
    rubytype = node.extraattr[RubyTypeName]
    if rubytype or node.type.namespace == RubyTypeNamespace
      rubytype2obj(node, info, map, rubytype)
    elsif node.type == XSD::AnyTypeName or node.type == XSD::AnySimpleTypeName
      anytype2obj(node, info, map)
    else
      unknowntype2obj(node, info, map)
    end
  end

private

  def addiv2soapattr(node, obj, map)
    return if obj.instance_variables.empty?
    ivars = SOAPStruct.new    # Undefined type.
    setiv2soap(ivars, obj, map)
    node.extraattr[RubyIVarName] = ivars
  end

  def unknownobj2soap(soap_class, obj, info, map)
    if obj.class.name.empty?
      raise TypeError.new("can't dump anonymous class #{obj}")
    end
    singleton_class = class << obj; self; end
    if !singleton_methods_true(obj).empty? or
	!singleton_class.instance_variables.empty?
      raise TypeError.new("singleton can't be dumped #{obj}")
    end
    if !(singleton_class.ancestors - obj.class.ancestors).empty?
      typestr = Mapping.name2elename(obj.class.to_s)
      type = XSD::QName.new(RubyTypeNamespace, typestr)
    else
      type = Mapping.class2element(obj.class)
    end
    param = SOAPStruct.new(type)
    mark_marshalled_obj(obj, param)
    setiv2soap(param, obj, map)
    param
  end

  if RUBY_VERSION >= '1.8.0'
    def singleton_methods_true(obj)
      obj.singleton_methods(true)
    end
  else
    def singleton_methods_true(obj)
      obj.singleton_methods
    end
  end

  def rubytype2obj(node, info, map, rubytype)
    klass = rubytype ? Mapping.class_from_name(rubytype) : nil
    obj = nil
    case node
    when SOAPString
      return @string_factory.soap2obj(klass || String, node, info, map)
    when SOAPDateTime
      #return @datetime_factory.soap2obj(klass || Time, node, info, map)
      klass ||= Time
      t = node.to_time
      arg = [t.year, t.month, t.mday, t.hour, t.min, t.sec, t.usec]
      obj = t.gmt? ? klass.gm(*arg) : klass.local(*arg)
      mark_unmarshalled_obj(node, obj)
      return true, obj
    when SOAPArray
      return @array_factory.soap2obj(klass || Array, node, info, map)
    when SOAPNil, SOAPBoolean, SOAPInt, SOAPInteger, SOAPDecimal, SOAPDouble
      return @basetype_factory.soap2obj(nil, node, info, map)
    when SOAPStruct
      return rubytypestruct2obj(node, info, map, rubytype)
    else
      raise
    end
  end

  def rubytypestruct2obj(node, info, map, rubytype)
    klass = rubytype ? Mapping.class_from_name(rubytype) : nil
    obj = nil
    case node.type
    when TYPE_HASH
      klass = rubytype ? Mapping.class_from_name(rubytype) : Hash
      obj = Mapping.create_empty_object(klass)
      mark_unmarshalled_obj(node, obj)
      node.each do |key, value|
        next unless key == 'item'
        obj[Mapping._soap2obj(value['key'], map)] =
          Mapping._soap2obj(value['value'], map)
      end
      if node.key?('default')
        obj.default = Mapping._soap2obj(node['default'], map)
      end
    when TYPE_REGEXP
      klass = rubytype ? Mapping.class_from_name(rubytype) : Regexp
      obj = Mapping.create_empty_object(klass)
      mark_unmarshalled_obj(node, obj)
      source = node['source'].string
      options = node['options'].data || 0
      Regexp.instance_method(:initialize).bind(obj).call(source, options)
    when TYPE_RANGE
      klass = rubytype ? Mapping.class_from_name(rubytype) : Range
      obj = Mapping.create_empty_object(klass)
      mark_unmarshalled_obj(node, obj)
      first = Mapping._soap2obj(node['begin'], map)
      last = Mapping._soap2obj(node['end'], map)
      exclude_end = node['exclude_end'].data
      Range.instance_method(:initialize).bind(obj).call(first, last, exclude_end)
    when TYPE_CLASS
      obj = Mapping.class_from_name(node['name'].data)
    when TYPE_MODULE
      obj = Mapping.class_from_name(node['name'].data)
    when TYPE_SYMBOL
      obj = node['id'].data.intern
    when TYPE_STRUCT
      typestr = Mapping.elename2name(node['type'].data)
      klass = Mapping.class_from_name(typestr)
      if klass.nil?
        return false
      end
      unless klass <= ::Struct
        return false
      end
      obj = Mapping.create_empty_object(klass)
      mark_unmarshalled_obj(node, obj)
      node['member'].each do |name, value|
        obj[Mapping.elename2name(name)] = Mapping._soap2obj(value, map)
      end
    else
      return unknowntype2obj(node, info, map)
    end
    return true, obj
  end

  def anytype2obj(node, info, map)
    case node
    when SOAPBasetype
      return true, node.data
    when SOAPStruct
      klass = ::SOAP::Mapping::Object
      obj = klass.new
      mark_unmarshalled_obj(node, obj)
      node.each do |name, value|
        obj.__add_xmlele_value(XSD::QName.new(nil, name),
          Mapping._soap2obj(value, map))
      end
      unless node.extraattr.empty?
        obj.instance_variable_set('@__xmlattr', node.extraattr)
      end
      return true, obj
    else
      return false
    end
  end

  def unknowntype2obj(node, info, map)
    case node
    when SOAPBasetype
      return true, node.data
    when SOAPArray
      return @array_factory.soap2obj(Array, node, info, map)
    when SOAPStruct
      obj = unknownstruct2obj(node, info, map)
      return true, obj if obj
      if !@allow_untyped_struct
        return false
      end
      return anytype2obj(node, info, map)
    else
      # Basetype which is not defined...
      return false
    end
  end

  def unknownstruct2obj(node, info, map)
    unless node.type.name
      return nil
    end
    typestr = Mapping.elename2name(node.type.name)
    klass = Mapping.class_from_name(typestr)
    if klass.nil? and @allow_untyped_struct
      klass = Mapping.class_from_name(typestr, true)    # lenient
    end
    if klass.nil?
      return nil
    end
    if klass <= ::Exception
      return exception2obj(klass, node, map)
    end
    klass_type = Mapping.class2qname(klass)
    return nil unless node.type.match(klass_type)
    obj = nil
    begin
      obj = Mapping.create_empty_object(klass)
    rescue
      # type name "data" tries Data.new which raises TypeError
      nil
    end
    mark_unmarshalled_obj(node, obj)
    setiv2obj(obj, node, map)
    obj
  end

  def exception2obj(klass, node, map)
    message = Mapping._soap2obj(node['message'], map)
    backtrace = Mapping._soap2obj(node['backtrace'], map)
    obj = Mapping.create_empty_object(klass)
    obj = obj.exception(message)
    mark_unmarshalled_obj(node, obj)
    obj.set_backtrace(backtrace)
    obj
  end

  # Only creates empty array.  Do String#replace it with real string.
  def array2obj(node, map, rubytype)
    klass = rubytype ? Mapping.class_from_name(rubytype) : Array
    obj = Mapping.create_empty_object(klass)
    mark_unmarshalled_obj(node, obj)
    obj
  end

  # Only creates empty string.  Do String#replace it with real string.
  def string2obj(node, map, rubytype)
    klass = rubytype ? Mapping.class_from_name(rubytype) : String
    obj = Mapping.create_empty_object(klass)
    mark_unmarshalled_obj(node, obj)
    obj
  end
end


end
end
