# soap/baseData.rb: SOAP4R - Base type library
# Copyright (C) 2000, 2001, 2003, 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

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
    super(*arg)
    @encodingstyle = nil
    @elename = XSD::QName.new
    @id = nil
    @precedents = []
    @root = false
    @parent = nil
    @position = nil
    @definedtype = nil
    @extraattr = {}
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
    super(*arg)
  end
end


###
## for SOAP compound type
#
module SOAPCompoundtype
  include SOAPType
  include SOAP

  def initialize(*arg)
    super(*arg)
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
    @type = XSD::QName.new
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
    @type = XSD::QName.new
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
    @type = type || XSD::QName.new
    @array = []
    @data = []
  end

  def to_s()
    str = ''
    self.each do |key, data|
      str << "#{ key }: #{ data }\n"
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

  def each
    for i in 0..(@array.length - 1)
      yield(@array[i], @data[i])
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

    @qualified = false

    @array = []
    @data = []
    @text = text
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
      each do |k, v|
	hash[k] = v.is_a?(SOAPElement) ? v.to_obj : v.to_s
      end
      hash
    end
  end

  def each
    for i in 0..(@array.length - 1)
      yield(@array[i], @data[i])
    end
  end

  def self.decode(elename)
    o = SOAPElement.new(elename)
    o
  end

  def self.from_obj(hash_or_string)
    o = SOAPElement.new(nil)
    if hash_or_string.is_a?(Hash)
      hash_or_string.each do |k, v|
	child = self.from_obj(v)
	child.elename = k.is_a?(XSD::QName) ? k : XSD::QName.new(nil, k.to_s)
	o.add(child)
      end
    else
      o.text = hash_or_string
    end
    o
  end

private

  def add_member(name, value)
    add_accessor(name)
    @array.push(name)
    @data.push(value)
    value.parent = self if value.respond_to?(:parent=)
    value
  end

  def add_accessor(name)
    methodname = name
    if self.respond_to?(methodname)
      methodname = safe_accessor_name(methodname)
    end
    sclass = class << self; self; end
    sclass.__send__(:define_method, methodname, proc {
      @data[@array.index(name)]
    })
    sclass.__send__(:define_method, methodname + '=', proc { |value|
      @data[@array.index(name)] = value
    })
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
    @type = type || XSD::QName.new
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
      raise ArgumentError.new("Given #{ idxary.size } params does not match rank: #{ @rank }")
    end

    retrieve(idxary)
  end

  def []=(*idxary)
    value = idxary.slice!(-1)

    if idxary.size != @rank
      raise ArgumentError.new("Given #{ idxary.size } params(#{ idxary }) does not match rank: #{ @rank }")
    end

    for i in 0..(idxary.size - 1)
      if idxary[i] + 1 > @size[i]
	@size[i] = idxary[i] + 1
      end
    end

    data = retrieve(idxary[0, idxary.size - 1])
    data[idxary.last] = value

    if value.is_a?(SOAPType)
      value.elename = value.elename.dup_name('item')
      
      # Sync type
      unless @type.name
	@type = XSD::QName.new(value.type.namespace,
	  SOAPArray.create_arytype(value.type.name, @rank))
      end

      unless value.type
	value.type = @type
      end
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
	new_obj.elename = new_obj.elename.dup_name('item')
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
      for rank in 1..(position.size - 1)
	idx = position[rank - 1]
	if iteary[idx].nil?
	  iteary = iteary[idx] = Array.new
	else
	  iteary = iteary[idx]
	end
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

  def retrieve(idxary)
    data = @data
    for rank in 1..(idxary.size)
      idx = idxary[rank - 1]
      if data[idx].nil?
	data = data[idx] = Array.new
      else
	data = data[idx]
      end
    end
    data
  end

  def traverse_data(data, rank = 1)
    for idx in 0..(ranksize(rank) - 1)
      if rank < @rank
	traverse_data(data[idx], rank + 1) do |*v|
	  v[1, 0] = idx
       	  yield(*v)
	end
      else
	yield(data[idx], idx)
      end
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
    "#{ typename }[" << ',' * (rank - 1) << ']'
  end

  TypeParseRegexp = Regexp.new('^(.+)\[([\d,]*)\]$')

  def self.parse_type(string)
    TypeParseRegexp =~ string
    return $1, $2
  end
end


require 'soap/mapping/typeMap'


end
