=begin
SOAP4R - Ruby type mapping factory.
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


module SOAP
module Mapping


class RubytypeFactory < Factory
  TYPE_STRING = 'String'
  TYPE_ARRAY = 'Array'
  TYPE_REGEXP = 'Regexp'
  TYPE_RANGE = 'Range'
  TYPE_CLASS = 'Class'
  TYPE_MODULE = 'Module'
  TYPE_SYMBOL = 'Symbol'
  TYPE_STRUCT = 'Struct'
  TYPE_HASH = 'Map'
  
  def initialize(config = {})
    @config = config
    @allow_untyped_struct = @config.key?(:allow_untyped_struct) ?
      @config[:allow_untyped_struct] : true
    @allow_original_mapping = @config.key?(:allow_original_mapping) ?
      @config[:allow_original_mapping] : false
  end

  def obj2soap(soap_class, obj, info, map)
    param = nil
    case obj
    when String
      unless @allow_original_mapping
        return nil
      end
      unless XSD::Charset.is_ces(obj, $KCODE)
        return nil
      end
      encoded = XSD::Charset.encoding_conv(obj, $KCODE, XSD::Charset.encoding)
      param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, TYPE_STRING))
      mark_marshalled_obj(obj, param)
      param.add('string', SOAPString.new(encoded))
      if obj.class != String
        param.extraattr[RubyTypeName] = obj.class.name
      end
      addiv2soap(param, obj, map)
    when Array
      unless @allow_original_mapping
        return nil
      end
      arytype = Mapping.obj2element(obj)
      if arytype.name
        arytype.namespace ||= RubyTypeNamespace
      else
        arytype = XSD::AnyTypeName
      end
      if obj.instance_variables.empty?
        param = SOAPArray.new(ValueArrayName, 1, arytype)
        mark_marshalled_obj(obj, param)
        obj.each do |var|
          param.add(Mapping._obj2soap(var, map))
        end
      else
        param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, TYPE_ARRAY))
        mark_marshalled_obj(obj, param)
        ary = SOAPArray.new(ValueArrayName, 1, arytype)
        obj.each do |var|
          ary.add(Mapping._obj2soap(var, map))
        end
        param.add('array', ary)
        addiv2soap(param, obj, map)
      end
      if obj.class != Array
        param.extraattr[RubyTypeName] = obj.class.name
      end
    when Regexp
      param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, TYPE_REGEXP))
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
      addiv2soap(param, obj, map)
    when Range
      param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, TYPE_RANGE))
      mark_marshalled_obj(obj, param)
      if obj.class != Range
        param.extraattr[RubyTypeName] = obj.class.name
      end
      param.add('begin', Mapping._obj2soap(obj.begin, map))
      param.add('end', Mapping._obj2soap(obj.end, map))
      param.add('exclude_end', SOAP::SOAPBoolean.new(obj.exclude_end?))
      addiv2soap(param, obj, map)
    when Hash
      unless @allow_original_mapping
        return nil
      end
      if obj.respond_to?(:default_proc) && obj.default_proc
        raise TypeError.new("cannot dump hash with default proc")
      end
      param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, TYPE_HASH))
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
      addiv2soap(param, obj, map)
    when Class
      if obj.name.empty?
        raise TypeError.new("Can't dump anonymous class #{ obj }.")
      end
      param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, TYPE_CLASS))
      mark_marshalled_obj(obj, param)
      param.add('name', SOAPString.new(obj.name))
      addiv2soap(param, obj, map)
    when Module
      if obj.name.empty?
        raise TypeError.new("Can't dump anonymous module #{ obj }.")
      end
      param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, TYPE_MODULE))
      mark_marshalled_obj(obj, param)
      param.add('name', SOAPString.new(obj.name))
      addiv2soap(param, obj, map)
    when Symbol
      param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, TYPE_SYMBOL))
      mark_marshalled_obj(obj, param)
      param.add('id', SOAPString.new(obj.id2name))
      addiv2soap(param, obj, map)
    when Exception
      typestr = Mapping.name2elename(obj.class.to_s)
      param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, typestr))
      mark_marshalled_obj(obj, param)
      param.add('message', Mapping._obj2soap(obj.message, map))
      param.add('backtrace', Mapping._obj2soap(obj.backtrace, map))
      addiv2soap(param, obj, map)
    when Struct
      param = SOAPStruct.new(XSD::QName.new(RubyTypeNamespace, TYPE_STRUCT))
      mark_marshalled_obj(obj, param)
      param.add('type', ele_type = SOAPString.new(obj.class.to_s))
      ele_member = SOAPStruct.new
      obj.members.each do |member|
        ele_member.add(Mapping.name2elename(member),
          Mapping._obj2soap(obj[member], map))
      end
      param.add('member', ele_member)
      addiv2soap(param, obj, map)
    when IO, Binding, Continuation, Data, Dir, File::Stat, MatchData, Method,
        Proc, Thread, ThreadGroup 
      return nil
    when ::SOAP::Mapping::Object
      param = SOAPStruct.new(XSD::AnyTypeName)
      mark_marshalled_obj(obj, param)
      setiv2soap(param, obj, map)   # addiv2soap?
    else
      if obj.class.name.empty?
        raise TypeError.new("Can't dump anonymous class #{ obj }.")
      end
      if check_singleton(obj)
        raise TypeError.new("singleton can't be dumped #{ obj }")
      end
      type = Mapping.class2element(obj.class)
      param = SOAPStruct.new(type)
      mark_marshalled_obj(obj, param)
      if obj.class <= Marshallable
        setiv2soap(param, obj, map)
      else
        setiv2soap(param, obj, map) # Should not be marshalled?
      end
    end
    param
  end

  def soap2obj(obj_class, node, info, map)
    rubytype = node.extraattr[RubyTypeName]
    if rubytype or node.type.namespace == RubyTypeNamespace
      rubytype2obj(node, map, rubytype)
    elsif node.type == XSD::AnyTypeName or node.type == XSD::AnySimpleTypeName
      anytype2obj(node, map)
    else
      unknowntype2obj(node, map)
    end
  end

private

  def check_singleton(obj)
    unless singleton_methods_true(obj).empty?
      return true
    end
    singleton_class = class << obj; self; end
    if !singleton_class.instance_variables.empty? or
	!(singleton_class.ancestors - obj.class.ancestors).empty?
      return true
    end
    false
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

  def rubytype2obj(node, map, rubytype)
    obj = nil
    case node.class
    when SOAPString
      obj = string2obj(node, map, rubytype)
      obj.replace(node.data)
      return true, obj
    when SOAPArray
      obj = array2obj(node, map, rubytype)
      node.soap2array(obj) do |elem|
        elem ? Mapping._soap2obj(elem, map) : nil
      end
      return true, obj
    end

    case node.type.name
    when TYPE_STRING
      obj = string2obj(node, map, rubytype)
      obj.replace(node['string'].data)
      setiv2obj(obj, node['ivars'], map)
    when TYPE_ARRAY
      obj = array2obj(node, map, rubytype)
      node['array'].soap2array(obj) do |elem|
        elem ? Mapping._soap2obj(elem, map) : nil
      end
      setiv2obj(obj, node['ivars'], map)
    when TYPE_REGEXP
      klass = rubytype ? Mapping.class_from_name(rubytype) : Regexp
      obj = create_empty_object(klass)
      mark_unmarshalled_obj(node, obj)
      source = node['source'].string
      options = node['options'].data || 0
      obj.instance_eval { initialize(source, options) }
      setiv2obj(obj, node['ivars'], map)
    when TYPE_RANGE
      klass = rubytype ? Mapping.class_from_name(rubytype) : Range
      obj = create_empty_object(klass)
      mark_unmarshalled_obj(node, obj)
      first = Mapping._soap2obj(node['begin'], map)
      last = Mapping._soap2obj(node['end'], map)
      exclude_end = node['exclude_end'].data
      obj.instance_eval { initialize(first, last, exclude_end) }
      setiv2obj(obj, node['ivars'], map)
    when TYPE_HASH
      unless @allow_original_mapping
        return false
      end
      klass = rubytype ? Mapping.class_from_name(rubytype) : Hash
      obj = create_empty_object(klass)
      mark_unmarshalled_obj(node, obj)
      node.each do |key, value|
        next unless key == 'item'
        obj[Mapping._soap2obj(value['key'], map)] =
          Mapping._soap2obj(value['value'], map)
      end
      if node.key?('default')
        obj.default = Mapping._soap2obj(node['default'], map)
      end
      setiv2obj(obj, node['ivars'], map)
    when TYPE_CLASS
      obj = Mapping.class_from_name(node['name'].data)
      setiv2obj(obj, node['ivars'], map)
    when TYPE_MODULE
      obj = Mapping.class_from_name(node['name'].data)
      setiv2obj(obj, node['ivars'], map)
    when TYPE_SYMBOL
      obj = node['id'].data.intern
      setiv2obj(obj, node['ivars'], map)
    when TYPE_STRUCT
      typestr = Mapping.elename2name(node['type'].data)
      klass = Mapping.class_from_name(typestr)
      if klass.nil?
        klass = Mapping.class_from_name(name2typename(typestr))
      end
      if klass.nil?
        return false
      end
      unless klass <= ::Struct
        return false
      end
      obj = create_empty_object(klass)
      mark_unmarshalled_obj(node, obj)
      node['member'].each do |name, value|
        obj[Mapping.elename2name(name)] =
          Mapping._soap2obj(value, map)
      end
      setiv2obj(obj, node['ivars'], map)
    else
      conv, obj = exception2obj(node, map)
      unless conv
        return false
      end
      setiv2obj(obj, node['ivars'], map)
    end
    return true, obj
  end

  def exception2obj(node, map)
    typestr = Mapping.elename2name(node.type.name)
    klass = Mapping.class_from_name(typestr)
    if klass.nil?
      return false
    end
    unless klass <= Exception
      return false
    end
    message = Mapping._soap2obj(node['message'], map)
    backtrace = Mapping._soap2obj(node['backtrace'], map)
    obj = create_empty_object(klass)
    obj = obj.exception(message)
    mark_unmarshalled_obj(node, obj)
    obj.set_backtrace(backtrace)
    setiv2obj(obj, node['ivars'], map)
    return true, obj
  end

  def anytype2obj(node, map)
    case node
    when SOAPBasetype
      return true, node.data
    when SOAPStruct
      klass = ::SOAP::Mapping::Object
      obj = klass.new
      mark_unmarshalled_obj(node, obj)
      node.each do |name, value|
        obj.set_property(name, Mapping._soap2obj(value, map))
      end
      return true, obj
    else
      return false
    end
  end

  def unknowntype2obj(node, map)
    if node.is_a?(SOAPStruct)
      obj = struct2obj(node, map)
      return true, obj if obj
      if !@allow_untyped_struct
        return false
      end
      return anytype2obj(node, map)
    else
      # Basetype which is not defined...
      return false
    end
  end

  def struct2obj(node, map)
    obj = nil
    typestr = Mapping.elename2name(node.type.name)
    klass = Mapping.class_from_name(typestr)
    if klass.nil?
      klass = Mapping.class_from_name(name2typename(typestr))
    end
    if klass.nil?
      return nil
    end
    klass_type = Mapping.class2qname(klass)
    return nil unless node.type.match(klass_type)
    obj = create_empty_object(klass)
    mark_unmarshalled_obj(node, obj)
    setiv2obj(obj, node, map)
    obj
  end

  # Only creates empty array.  Do String#replace it with real string.
  def array2obj(node, map, rubytype)
    klass = rubytype ? Mapping.class_from_name(rubytype) : Array
    obj = create_empty_object(klass)
    mark_unmarshalled_obj(node, obj)
    obj
  end

  # Only creates empty string.  Do String#replace it with real string.
  def string2obj(node, map, rubytype)
    klass = rubytype ? Mapping.class_from_name(rubytype) : String
    obj = create_empty_object(klass)
    mark_unmarshalled_obj(node, obj)
    obj
  end
end


end
end
