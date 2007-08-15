# soap/baseData.rb: SOAP4R - Base type library
# Copyright (C) 2000, 2001, 2003-2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/datatypes'
require 'soap/soap'


module SOAP


###
## Mix-in module for SOAP base type classes.
#
module SOAPModuleUtils
  include SOAP

public

  def decode(elename)
    d = self.new
    d.elename = elename
    d
  end
end


###
## for SOAP type(base and compound)
#
module SOAPType
  attr_accessor :encodingstyle
  attr_accessor :elename
  attr_accessor :id
  attr_reader :precedents
  attr_accessor :root
  attr_accessor :parent
  attr_accessor :position
  attr_reader :extraattr
  attr_accessor :definedtype

  def initialize(*arg)
    super
    @encodingstyle = nil
    @elename = XSD::QName::EMPTY
    @id = nil
    @precedents = []
    @root = false
    @parent = nil
    @position = nil
    @definedtype = nil
    @extraattr = {}
  end

  def inspect
    if self.is_a?(XSD::NSDBase)
      sprintf("#<%s:0x%x %s %s>", self.class.name, __id__, self.elename, self.type)
    else
      sprintf("#<%s:0x%x %s>", self.class.name, __id__, self.elename)
    end
  end

  def rootnode
    node = self
    while node = node.parent
      break if SOAPEnvelope === node
    end
    node
  end
end


###
## for SOAP base type
#
module SOAPBasetype
  include SOAPType
  include SOAP

  def initialize(*arg)
    super
  end
end


###
## for SOAP compound type
#
module SOAPCompoundtype
  include SOAPType
  include SOAP

  def initialize(*arg)
    super
  end
end


###
## Convenience datatypes.
#
class SOAPReference < XSD::NSDBase
  include SOAPBasetype
  extend SOAPModuleUtils

public

  attr_accessor :refid

  # Override the definition in SOAPBasetype.
  def initialize(obj = nil)
    super()
    @type = XSD::QName::EMPTY
    @refid = nil
    @obj = nil
    __setobj__(obj) if obj
  end

  def __getobj__
    @obj
  end

  def __setobj__(obj)
    @obj = obj
    @refid = @obj.id || SOAPReference.create_refid(@obj)
    @obj.id = @refid unless @obj.id
    @obj.precedents << self
    # Copies NSDBase information
    @obj.type = @type unless @obj.type
  end

  # Why don't I use delegate.rb?
  # -> delegate requires target object type at initialize time.
  # Why don't I use forwardable.rb?
  # -> forwardable requires a list of forwarding methods.
  #
  # ToDo: Maybe I should use forwardable.rb and give it a methods list like
  # delegate.rb...
  #
  def method_missing(msg_id, *params)
    if @obj
      @obj.send(msg_id, *params)
    else
      nil
    end
  end

  def refidstr
    '#' + @refid
  end

  def self.create_refid(obj)
    'id' + obj.__id__.to_s
  end

  def self.decode(elename, refidstr)
    if /\A#(.*)\z/ =~ refidstr
      refid = $1
    elsif /\Acid:(.*)\z/ =~ refidstr
      refid = $1
    else
      raise ArgumentError.new("illegal refid #{refidstr}")
    end
    d = super(elename)
    d.refid = refid
    d
  end
end


class SOAPExternalReference < XSD::NSDBase
  include SOAPBasetype
  extend SOAPModuleUtils

  def initialize
    super()
    @type = XSD::QName::EMPTY
  end

  def referred
    rootnode.external_content[external_contentid] = self
  end

  def refidstr
    'cid:' + external_contentid
  end

private

  def external_contentid
    raise NotImplementedError.new
  end
end


class SOAPNil < XSD::XSDNil
  include SOAPBasetype
  extend SOAPModuleUtils
end

# SOAPRawString is for sending raw string.  In contrast to SOAPString,
# SOAP4R does not do XML encoding and does not convert its CES.  The string it
# holds is embedded to XML instance directly as a 'xsd:string'.
class SOAPRawString < XSD::XSDString
  include SOAPBasetype
  extend SOAPModuleUtils
end


###
## Basic datatypes.
#
class SOAPAnySimpleType < XSD::XSDAnySimpleType
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPString < XSD::XSDString
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPBoolean < XSD::XSDBoolean
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPDecimal < XSD::XSDDecimal
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPFloat < XSD::XSDFloat
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPDouble < XSD::XSDDouble
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPDuration < XSD::XSDDuration
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPDateTime < XSD::XSDDateTime
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPTime < XSD::XSDTime
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPDate < XSD::XSDDate
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPGYearMonth < XSD::XSDGYearMonth
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPGYear < XSD::XSDGYear
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPGMonthDay < XSD::XSDGMonthDay
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPGDay < XSD::XSDGDay
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPGMonth < XSD::XSDGMonth
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPHexBinary < XSD::XSDHexBinary
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPBase64 < XSD::XSDBase64Binary
  include SOAPBasetype
  extend SOAPModuleUtils
  Type = QName.new(EncodingNamespace, Base64Literal)

public
  # Override the definition in SOAPBasetype.
  def initialize(value = nil)
    super(value)
    @type = Type
  end

  def as_xsd
    @type = XSD::XSDBase64Binary::Type
  end
end

class SOAPAnyURI < XSD::XSDAnyURI
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPQName < XSD::XSDQName
  include SOAPBasetype
  extend SOAPModuleUtils
end


class SOAPInteger < XSD::XSDInteger
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPNonPositiveInteger < XSD::XSDNonPositiveInteger
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPNegativeInteger < XSD::XSDNegativeInteger
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPLong < XSD::XSDLong
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPInt < XSD::XSDInt
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPShort < XSD::XSDShort
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPByte < XSD::XSDByte
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPNonNegativeInteger < XSD::XSDNonNegativeInteger
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPUnsignedLong < XSD::XSDUnsignedLong
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPUnsignedInt < XSD::XSDUnsignedInt
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPUnsignedShort < XSD::XSDUnsignedShort
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPUnsignedByte < XSD::XSDUnsignedByte
  include SOAPBasetype
  extend SOAPModuleUtils
end

class SOAPPositiveInteger < XSD::XSDPositiveInteger
  include SOAPBasetype
  extend SOAPModuleUtils
end


###
## Compound datatypes.
#
class SOAPStruct < XSD::NSDBase
  include SOAPCompoundtype
  include Enumerable

public

  def initialize(type = nil)
    super()
    @type = type || XSD::QName::EMPTY
    @array = []
    @data = []
  end

  def to_s()
    str = ''
    self.each do |key, data|
      str << "#{key}: #{data}\n"
    end
    str
  end

  def add(name, value)
    add_member(name, value)
  end

  def [](idx)
    if idx.is_a?(Range)
      @data[idx]
    elsif idx.is_a?(Integer)
      if (idx > @array.size)
        raise ArrayIndexOutOfBoundsError.new('In ' << @type.name)
      end
      @data[idx]
    else
      if @array.include?(idx)
	@data[@array.index(idx)]
      else
	nil
      end
    end
  end

  def []=(idx, data)
    if @array.include?(idx)
      data.parent = self if data.respond_to?(:parent=)
      @data[@array.index(idx)] = data
    else
      add(idx, data)
    end
  end

  def key?(name)
    @array.include?(name)
  end

  def members
    @array
  end

  def to_obj
    hash = {}
    proptype = {}
    each do |k, v|
      value = v.respond_to?(:to_obj) ? v.to_obj : v.to_s
      case proptype[k]
      when :single
        hash[k] = [hash[k], value]
        proptype[k] = :multi
      when :multi
        hash[k] << value
      else
        hash[k] = value
        proptype[k] = :single
      end
    end
    hash
  end

  def each
    idx = 0
    while idx < @array.length
      yield(@array[idx], @data[idx])
      idx += 1
    end
  end

  def replace
    members.each do |member|
      self[member] = yield(self[member])
    end
  end

  def self.decode(elename, type)
    s = SOAPStruct.new(type)
    s.elename = elename
    s
  end

private

  def add_member(name, value = nil)
    value = SOAPNil.new() if value.nil?
    @array.push(name)
    value.elename = value.elename.dup_name(name)
    @data.push(value)
    value.parent = self if value.respond_to?(:parent=)
    value
  end
end


# SOAPElement is not typed so it is not derived from NSDBase.
class SOAPElement
  include Enumerable

  attr_accessor :encodingstyle

  attr_accessor :elename
  attr_accessor :id
  attr_reader :precedents
  attr_accessor :root
  attr_accessor :parent
  attr_accessor :position
  attr_accessor :extraattr

  attr_accessor :qualified

  def initialize(elename, text = nil)
    if !elename.is_a?(XSD::QName)
      elename = XSD::QName.new(nil, elename)
    end
    @encodingstyle = LiteralNamespace
    @elename = elename
    @id = nil
    @precedents = []
    @root = false
    @parent = nil
    @position = nil
    @extraattr = {}

    @qualified = nil

    @array = []
    @data = []
    @text = text
  end

  def inspect
    sprintf("#<%s:0x%x %s>", self.class.name, __id__, self.elename)
  end

  # Text interface.
  attr_accessor :text
  alias data text

  # Element interfaces.
  def add(value)
    add_member(value.elename.name, value)
  end

  def [](idx)
    if @array.include?(idx)
      @data[@array.index(idx)]
    else
      nil
    end
  end

  def []=(idx, data)
    if @array.include?(idx)
      data.parent = self if data.respond_to?(:parent=)
      @data[@array.index(idx)] = data
    else
      add(data)
    end
  end

  def key?(name)
    @array.include?(name)
  end

  def members
    @array
  end

  def to_obj
    if members.empty?
      @text
    else
      hash = {}
      proptype = {}
      each do |k, v|
        value = v.respond_to?(:to_obj) ? v.to_obj : v.to_s
        case proptype[k]
        when :single
          hash[k] = [hash[k], value]
          proptype[k] = :multi
        when :multi
          hash[k] << value
        else
          hash[k] = value
          proptype[k] = :single
        end
      end
      hash
    end
  end

  def each
    idx = 0
    while idx < @array.length
      yield(@array[idx], @data[idx])
      idx += 1
    end
  end

  def self.decode(elename)
    o = SOAPElement.new(elename)
    o
  end

  def self.from_obj(obj, namespace = nil)
    o = SOAPElement.new(nil)
    case obj
    when nil
      o.text = nil
    when Hash
      obj.each do |elename, value|
        if value.is_a?(Array)
          value.each do |subvalue|
            child = from_obj(subvalue, namespace)
            child.elename = to_elename(elename, namespace)
            o.add(child)
          end
        else
          child = from_obj(value, namespace)
          child.elename = to_elename(elename, namespace)
          o.add(child)
        end
      end
    else
      o.text = obj.to_s
    end
    o
  end

  def self.to_elename(obj, namespace = nil)
    if obj.is_a?(XSD::QName)
      obj
    elsif /\A(.+):([^:]+)\z/ =~ obj.to_s
      XSD::QName.new($1, $2)
    else
      XSD::QName.new(namespace, obj.to_s)
    end
  end

private

  def add_member(name, value)
    add_accessor(name)
    @array.push(name)
    @data.push(value)
    value.parent = self if value.respond_to?(:parent=)
    value
  end

  if RUBY_VERSION > "1.7.0"
    def add_accessor(name)
      methodname = name
      if self.respond_to?(methodname)
        methodname = safe_accessor_name(methodname)
      end
      Mapping.define_singleton_method(self, methodname) do
        @data[@array.index(name)]
      end
      Mapping.define_singleton_method(self, methodname + '=') do |value|
        @data[@array.index(name)] = value
      end
    end
  else
    def add_accessor(name)
      methodname = safe_accessor_name(name)
      instance_eval <<-EOS
        def #{methodname}
          @data[@array.index(#{name.dump})]
        end

        def #{methodname}=(value)
          @data[@array.index(#{name.dump})] = value
        end
      EOS
    end
  end

  def safe_accessor_name(name)
    "var_" << name.gsub(/[^a-zA-Z0-9_]/, '')
  end
end


class SOAPArray < XSD::NSDBase
  include SOAPCompoundtype
  include Enumerable

public

  attr_accessor :sparse

  attr_reader :offset, :rank
  attr_accessor :size, :size_fixed
  attr_reader :arytype

  def initialize(type = nil, rank = 1, arytype = nil)
    super()
    @type = type || ValueArrayName
    @rank = rank
    @data = Array.new
    @sparse = false
    @offset = Array.new(rank, 0)
    @size = Array.new(rank, 0)
    @size_fixed = false
    @position = nil
    @arytype = arytype
  end

  def offset=(var)
    @offset = var
    @sparse = true
  end

  def add(value)
    self[*(@offset)] = value
  end

  def [](*idxary)
    if idxary.size != @rank
      raise ArgumentError.new("given #{idxary.size} params does not match rank: #{@rank}")
    end

    retrieve(idxary)
  end

  def []=(*idxary)
    value = idxary.slice!(-1)

    if idxary.size != @rank
      raise ArgumentError.new("given #{idxary.size} params(#{idxary})" +
        " does not match rank: #{@rank}")
    end

    idx = 0
    while idx < idxary.size
      if idxary[idx] + 1 > @size[idx]
	@size[idx] = idxary[idx] + 1
      end
      idx += 1
    end

    data = retrieve(idxary[0, idxary.size - 1])
    data[idxary.last] = value

    if value.is_a?(SOAPType)
      value.elename = ITEM_NAME
      # Sync type
      unless @type.name
	@type = XSD::QName.new(value.type.namespace,
	  SOAPArray.create_arytype(value.type.name, @rank))
      end
      value.type ||= @type
    end

    @offset = idxary
    value.parent = self if value.respond_to?(:parent=)
    offsetnext
  end

  def each
    @data.each do |data|
      yield(data)
    end
  end

  def to_a
    @data.dup
  end

  def replace
    @data = deep_map(@data) do |ele|
      yield(ele)
    end
  end

  def deep_map(ary, &block)
    ary.collect do |ele|
      if ele.is_a?(Array)
	deep_map(ele, &block)
      else
	new_obj = block.call(ele)
	new_obj.elename = ITEM_NAME
	new_obj
      end
    end
  end

  def include?(var)
    traverse_data(@data) do |v, *rank|
      if v.is_a?(SOAPBasetype) && v.data == var
	return true
      end
    end
    false
  end

  def traverse
    traverse_data(@data) do |v, *rank|
      unless @sparse
       yield(v)
      else
       yield(v, *rank) if v && !v.is_a?(SOAPNil)
      end
    end
  end

  def soap2array(ary)
    traverse_data(@data) do |v, *position|
      iteary = ary
      rank = 1
      while rank < position.size
	idx = position[rank - 1]
	if iteary[idx].nil?
	  iteary = iteary[idx] = Array.new
	else
	  iteary = iteary[idx]
	end
        rank += 1
      end
      if block_given?
	iteary[position.last] = yield(v)
      else
	iteary[position.last] = v
      end
    end
  end

  def position
    @position
  end

private

  ITEM_NAME = XSD::QName.new(nil, 'item')

  def retrieve(idxary)
    data = @data
    rank = 1
    while rank <= idxary.size
      idx = idxary[rank - 1]
      if data[idx].nil?
	data = data[idx] = Array.new
      else
	data = data[idx]
      end
      rank += 1
    end
    data
  end

  def traverse_data(data, rank = 1)
    idx = 0
    while idx < ranksize(rank)
      if rank < @rank
	traverse_data(data[idx], rank + 1) do |*v|
	  v[1, 0] = idx
       	  yield(*v)
	end
      else
	yield(data[idx], idx)
      end
      idx += 1
    end
  end

  def ranksize(rank)
    @size[rank - 1]
  end

  def offsetnext
    move = false
    idx = @offset.size - 1
    while !move && idx >= 0
      @offset[idx] += 1
      if @size_fixed
	if @offset[idx] < @size[idx]
	  move = true
	else
	  @offset[idx] = 0
	  idx -= 1
	end
      else
	move = true
      end
    end
  end

  # Module function

public

  def self.decode(elename, type, arytype)
    typestr, nofary = parse_type(arytype.name)
    rank = nofary.count(',') + 1
    plain_arytype = XSD::QName.new(arytype.namespace, typestr)
    o = SOAPArray.new(type, rank, plain_arytype)
    size = []
    nofary.split(',').each do |s|
      if s.empty?
	size.clear
	break
      else
	size << s.to_i
      end
    end
    unless size.empty?
      o.size = size
      o.size_fixed = true
    end
    o.elename = elename
    o
  end

private

  def self.create_arytype(typename, rank)
    "#{typename}[" << ',' * (rank - 1) << ']'
  end

  TypeParseRegexp = Regexp.new('^(.+)\[([\d,]*)\]$')

  def self.parse_type(string)
    TypeParseRegexp =~ string
    return $1, $2
  end
end


require 'soap/mapping/typeMap'


end
