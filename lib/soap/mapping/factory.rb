# SOAP4R - Mapping factory.
# Copyright (C) 2000, 2001, 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


module SOAP
module Mapping


class Factory
  include TraverseSupport

  def initialize
    # nothing to do
  end

  def obj2soap(soap_class, obj, info, map)
    raise NotImplementError.new
    # return soap_obj
  end

  def soap2obj(obj_class, node, info, map)
    raise NotImplementError.new
    # return convert_succeeded_or_not, obj
  end

  if Object.respond_to?(:allocate)
    # ruby/1.7 or later.
    def create_empty_object(klass)
      klass.allocate
    end
  else
    MARSHAL_TAG = {
      String => ['"', 1],
      Regexp => ['/', 2],
      Array => ['[', 1],
      Hash => ['{', 1]
    }
    def create_empty_object(klass)
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

  def setiv2obj(obj, node, map)
    return if node.nil?
    if obj.is_a?(Array)
      setiv2ary(obj, node, map)
    else
      setiv2struct(obj, node, map)
    end
  end

  def setiv2soap(node, obj, map)
    # should we sort instance_variables?
    obj.instance_variables.each do |var|
      name = var.sub(/^@/, '')
      node.add(Mapping.name2elename(name),
        Mapping._obj2soap(obj.instance_eval(var), map))
    end
  end

  # It breaks Thread.current[:SOAPMarshalDataKey].
  def mark_marshalled_obj(obj, soap_obj)
    Thread.current[:SOAPMarshalDataKey][obj.__id__] = soap_obj
  end

  # It breaks Thread.current[:SOAPMarshalDataKey].
  def mark_unmarshalled_obj(node, obj)
    Thread.current[:SOAPMarshalDataKey][node.id] = obj
  end

private

  def setiv2ary(obj, node, map)
    node.each do |name, value|
      Array.instance_method(:<<).bind(obj).call(Mapping._soap2obj(value, map))
    end
  end

  def setiv2struct(obj, node, map)
    vars = {}
    node.each do |name, value|
      vars[Mapping.elename2name(name)] = Mapping._soap2obj(value, map)
    end
    Mapping.set_instance_vars(obj, vars)
  end
end

class StringFactory_ < Factory
  def initialize(allow_original_mapping = false)
    super()
    @allow_original_mapping = allow_original_mapping
  end

  def obj2soap(soap_class, obj, info, map)
    if !@allow_original_mapping and !obj.instance_variables.empty?
      return nil
    end
    begin
      unless XSD::Charset.is_ces(obj, $KCODE)
	return nil
      end
      encoded = XSD::Charset.encoding_conv(obj, $KCODE, XSD::Charset.encoding)
      soap_obj = soap_class.new(encoded)
    rescue XSD::ValueSpaceError
      return nil
    end
    mark_marshalled_obj(obj, soap_obj)
    soap_obj
  end

  def soap2obj(obj_class, node, info, map)
    obj = create_empty_object(obj_class)
    decoded = XSD::Charset.encoding_conv(node.data, XSD::Charset.encoding, $KCODE)
    obj.replace(decoded)
    mark_unmarshalled_obj(node, obj)
    return true, obj
  end
end

class BasetypeFactory_ < Factory
  def initialize(allow_original_mapping = false)
    super()
    @allow_original_mapping = allow_original_mapping
  end

  def obj2soap(soap_class, obj, info, map)
    if !@allow_original_mapping and !obj.instance_variables.empty?
      return nil
    end
    soap_obj = nil
    begin
      soap_obj = soap_class.new(obj)
    rescue XSD::ValueSpaceError
      return nil
    end
    if @allow_original_mapping
      # Basetype except String should not be multiref-ed in SOAP/1.1.
      mark_marshalled_obj(obj, soap_obj)
    end
    soap_obj
  end

  def soap2obj(obj_class, node, info, map)
    obj = node.data
    mark_unmarshalled_obj(node, obj)
    return true, obj
  end
end

class DateTimeFactory_ < Factory
  def initialize(allow_original_mapping = false)
    super()
    @allow_original_mapping = allow_original_mapping
  end

  def obj2soap(soap_class, obj, info, map)
    if !@allow_original_mapping and
	Time === obj and !obj.instance_variables.empty?
      return nil
    end
    soap_obj = nil
    begin
      soap_obj = soap_class.new(obj)
    rescue XSD::ValueSpaceError
      return nil
    end
    mark_marshalled_obj(obj, soap_obj)
    soap_obj
  end

  def soap2obj(obj_class, node, info, map)
    obj = nil
    if obj_class == Time
      obj = node.to_time
      if obj.nil?
        # Is out of range as a Time
        return false
      end
    elsif obj_class == Date
      obj = node.data
    else
      return false
    end
    mark_unmarshalled_obj(node, obj)
    return true, obj
  end
end

class Base64Factory_ < Factory
  def obj2soap(soap_class, obj, info, map)
    return nil unless obj.instance_variables.empty?
    soap_obj = soap_class.new(obj)
    mark_marshalled_obj(obj, soap_obj) if soap_obj
    soap_obj
  end

  def soap2obj(obj_class, node, info, map)
    obj = node.string
    mark_unmarshalled_obj(node, obj)
    return true, obj
  end
end

class URIFactory_ < Factory
  def obj2soap(soap_class, obj, info, map)
    soap_obj = soap_class.new(obj)
    mark_marshalled_obj(obj, soap_obj) if soap_obj
    soap_obj
  end

  def soap2obj(obj_class, node, info, map)
    obj = node.data
    mark_unmarshalled_obj(node, obj)
    return true, obj
  end
end

class ArrayFactory_ < Factory
  def initialize(allow_original_mapping = false)
    super()
    @allow_original_mapping = allow_original_mapping
  end

  # [[1], [2]] is converted to Array of Array, not 2-D Array.
  # To create M-D Array, you must call Mapping.ary2md.
  def obj2soap(soap_class, obj, info, map)
    if !@allow_original_mapping and !obj.instance_variables.empty?
      return nil
    end
    arytype = Mapping.obj2element(obj)
    if arytype.name
      arytype.namespace ||= RubyTypeNamespace
    else
      arytype = XSD::AnyTypeName
    end
    param = SOAPArray.new(ValueArrayName, 1, arytype)
    mark_marshalled_obj(obj, param)
    obj.each do |var|
      param.add(Mapping._obj2soap(var, map))
    end
    param
  end

  def soap2obj(obj_class, node, info, map)
    obj = create_empty_object(obj_class)
    mark_unmarshalled_obj(node, obj)
    node.soap2array(obj) do |elem|
      elem ? Mapping._soap2obj(elem, map) : nil
    end
    return true, obj
  end
end

class TypedArrayFactory_ < Factory
  def initialize(allow_original_mapping = false)
    super()
    @allow_original_mapping = allow_original_mapping
  end

  def obj2soap(soap_class, obj, info, map)
    if !@allow_original_mapping and !obj.instance_variables.empty?
      return nil
    end
    arytype = info[:type] || info[0]
    param = SOAPArray.new(ValueArrayName, 1, arytype)
    mark_marshalled_obj(obj, param)
    obj.each do |var|
      param.add(Mapping._obj2soap(var, map))
    end
    param
  end

  def soap2obj(obj_class, node, info, map)
    if node.rank > 1
      return false
    end
    arytype = info[:type] || info[0]
    unless node.arytype == arytype
      return false
    end
    obj = create_empty_object(obj_class)
    mark_unmarshalled_obj(node, obj)
    node.soap2array(obj) do |elem|
      elem ? Mapping._soap2obj(elem, map) : nil
    end
    return true, obj
  end
end

class TypedStructFactory_ < Factory
  def obj2soap(soap_class, obj, info, map)
    type = info[:type] || info[0]
    param = soap_class.new(type)
    mark_marshalled_obj(obj, param)
    if obj.class <= SOAP::Marshallable
      setiv2soap(param, obj, map)
    else
      setiv2soap(param, obj, map)
    end
    param
  end

  def soap2obj(obj_class, node, info, map)
    type = info[:type] || info[0]
    unless node.type == type
      return false
    end
    obj = create_empty_object(obj_class)
    mark_unmarshalled_obj(node, obj)
    setiv2obj(obj, node, map)
    return true, obj
  end
end

MapQName = XSD::QName.new(ApacheSOAPTypeNamespace, 'Map')
class HashFactory_ < Factory
  def initialize(allow_original_mapping = false)
    super()
    @allow_original_mapping = allow_original_mapping
  end

  def obj2soap(soap_class, obj, info, map)
    if !@allow_original_mapping and !obj.instance_variables.empty?
      return nil
    end
    if !obj.default.nil? or
	(obj.respond_to?(:default_proc) and obj.default_proc)
      return nil
    end
    param = SOAPStruct.new(MapQName)
    mark_marshalled_obj(obj, param)
    obj.each do |key, value|
      elem = SOAPStruct.new
      elem.add("key", Mapping._obj2soap(key, map))
      elem.add("value", Mapping._obj2soap(value, map))
      # ApacheAxis allows only 'item' here.
      param.add("item", elem)
    end
    param
  end

  def soap2obj(obj_class, node, info, map)
    unless node.type == MapQName
      return false
    end
    if node.class == SOAPStruct and node.key?('default')
      return false
    end
    obj = create_empty_object(obj_class)
    mark_unmarshalled_obj(node, obj)
    if node.class == SOAPStruct
      node.each do |key, value|
	obj[Mapping._soap2obj(value['key'], map)] =
	  Mapping._soap2obj(value['value'], map)
      end
    else
      node.each do |value|
	obj[Mapping._soap2obj(value['key'], map)] =
	  Mapping._soap2obj(value['value'], map)
      end
    end
    return true, obj
  end
end


end
end
