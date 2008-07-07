# XSD4R - XML Schema Datatype implementation.
# Copyright (C) 2000, 2001, 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/qname'
require 'xsd/charset'
require 'uri'


###
## XMLSchamaDatatypes general definitions.
#
module XSD


Namespace = 'http://www.w3.org/2001/XMLSchema'
InstanceNamespace = 'http://www.w3.org/2001/XMLSchema-instance'

AttrType = 'type'
NilValue = 'true'

AnyTypeLiteral = 'anyType'
AnySimpleTypeLiteral = 'anySimpleType'
NilLiteral = 'nil'
StringLiteral = 'string'
BooleanLiteral = 'boolean'
DecimalLiteral = 'decimal'
FloatLiteral = 'float'
DoubleLiteral = 'double'
DurationLiteral = 'duration'
DateTimeLiteral = 'dateTime'
TimeLiteral = 'time'
DateLiteral = 'date'
GYearMonthLiteral = 'gYearMonth'
GYearLiteral = 'gYear'
GMonthDayLiteral = 'gMonthDay'
GDayLiteral = 'gDay'
GMonthLiteral = 'gMonth'
HexBinaryLiteral = 'hexBinary'
Base64BinaryLiteral = 'base64Binary'
AnyURILiteral = 'anyURI'
QNameLiteral = 'QName'

NormalizedStringLiteral = 'normalizedString'
#3.3.2 token
#3.3.3 language
#3.3.4 NMTOKEN
#3.3.5 NMTOKENS
#3.3.6 Name
#3.3.7 NCName
#3.3.8 ID
#3.3.9 IDREF
#3.3.10 IDREFS
#3.3.11 ENTITY
#3.3.12 ENTITIES
IntegerLiteral = 'integer'
NonPositiveIntegerLiteral = 'nonPositiveInteger'
NegativeIntegerLiteral = 'negativeInteger'
LongLiteral = 'long'
IntLiteral = 'int'
ShortLiteral = 'short'
ByteLiteral = 'byte'
NonNegativeIntegerLiteral = 'nonNegativeInteger'
UnsignedLongLiteral = 'unsignedLong'
UnsignedIntLiteral = 'unsignedInt'
UnsignedShortLiteral = 'unsignedShort'
UnsignedByteLiteral = 'unsignedByte'
PositiveIntegerLiteral = 'positiveInteger'

AttrTypeName = QName.new(InstanceNamespace, AttrType)
AttrNilName = QName.new(InstanceNamespace, NilLiteral)

AnyTypeName = QName.new(Namespace, AnyTypeLiteral)
AnySimpleTypeName = QName.new(Namespace, AnySimpleTypeLiteral)

class Error < StandardError; end
class ValueSpaceError < Error; end


###
## The base class of all datatypes with Namespace.
#
class NSDBase
  @@types = []

  attr_accessor :type

  def self.inherited(klass)
    @@types << klass
  end

  def self.types
    @@types
  end

  def initialize
  end

  def init(type)
    @type = type
  end
end


###
## The base class of XSD datatypes.
#
class XSDAnySimpleType < NSDBase
  include XSD
  Type = QName.new(Namespace, AnySimpleTypeLiteral)

  # @data represents canonical space (ex. Integer: 123).
  attr_reader :data
  # @is_nil represents this data is nil or not.
  attr_accessor :is_nil

  def initialize(value = nil)
    init(Type, value)
  end

  # true or raise
  def check_lexical_format(value)
    screen_data(value)
    true
  end

  # set accepts a string which follows lexical space (ex. String: "+123"), or
  # an object which follows canonical space (ex. Integer: 123).
  def set(value)
    if value.nil?
      @is_nil = true
      @data = nil
      _set(nil)
    else
      @is_nil = false
      _set(screen_data(value))
    end
  end

  # to_s creates a string which follows lexical space (ex. String: "123").
  def to_s()
    if @is_nil
      ""
    else
      _to_s
    end
  end

private

  def init(type, value)
    super(type)
    set(value)
  end

  # raises ValueSpaceError if check failed
  def screen_data(value)
    value
  end

  def _set(value)
    @data = value
  end

  def _to_s
    @data.to_s
  end
end

class XSDNil < XSDAnySimpleType
  Type = QName.new(Namespace, NilLiteral)
  Value = 'true'

  def initialize(value = nil)
    init(Type, value)
  end
end


###
## Primitive datatypes.
#
class XSDString < XSDAnySimpleType
  Type = QName.new(Namespace, StringLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data(value)
    unless XSD::Charset.is_ces(value, XSD::Charset.encoding)
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ value }'.")
    end
    value
  end
end

class XSDBoolean < XSDAnySimpleType
  Type = QName.new(Namespace, BooleanLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data(value)
    if value.is_a?(String)
      str = value.strip
      if str == 'true' || str == '1'
	true
      elsif str == 'false' || str == '0'
	false
      else
	raise ValueSpaceError.new("#{ type }: cannot accept '#{ str }'.")
      end
    else
      value ? true : false
    end
  end
end

class XSDDecimal < XSDAnySimpleType
  Type = QName.new(Namespace, DecimalLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

  def nonzero?
    (@number != '0')
  end

private

  def screen_data(d)
    if d.is_a?(String)
      # Integer("00012") => 10 in Ruby.
      d.sub!(/^([+\-]?)0*(?=\d)/, "\\1")
    end
    screen_data_str(d)
  end

  def screen_data_str(str)
    /^([+\-]?)(\d*)(?:\.(\d*)?)?$/ =~ str.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ str }'.")
    end
    sign = $1 || '+'
    int_part = $2
    frac_part = $3
    int_part = '0' if int_part.empty?
    frac_part = frac_part ? frac_part.sub(/0+$/, '') : ''
    point = - frac_part.size
    number = int_part + frac_part
    # normalize
    if sign == '+'
      sign = ''
    elsif sign == '-'
      if number == '0'
	sign = ''
      end
    end
    [sign, point, number]
  end

  def _set(data)
    if data.nil?
      @sign = @point = @number = @data = nil
      return
    end
    @sign, @point, @number = data
    @data = _to_s
    @data.freeze
  end

  # 0.0 -> 0; right?
  def _to_s
    str = @number.dup
    if @point.nonzero?
      str[@number.size + @point, 0] = '.'
    end
    @sign + str
  end
end

module FloatConstants
  NaN = 0.0/0.0
  POSITIVE_INF = +1.0/0.0
  NEGATIVE_INF = -1.0/0.0
  POSITIVE_ZERO = +1.0/POSITIVE_INF
  NEGATIVE_ZERO = -1.0/POSITIVE_INF
  MIN_POSITIVE_SINGLE = 2.0 ** -149
end

class XSDFloat < XSDAnySimpleType
  include FloatConstants
  Type = QName.new(Namespace, FloatLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data(value)
    # "NaN".to_f => 0 in some environment.  libc?
    if value.is_a?(Float)
      return narrow32bit(value)
    end
    str = value.to_s.strip
    if str == 'NaN'
      NaN
    elsif str == 'INF'
      POSITIVE_INF
    elsif str == '-INF'
      NEGATIVE_INF
    else
      if /^[+\-\.\deE]+$/ !~ str
	raise ValueSpaceError.new("#{ type }: cannot accept '#{ str }'.")
      end
      # Float("-1.4E") might fail on some system.
      str << '0' if /e$/i =~ str
      begin
  	return narrow32bit(Float(str))
      rescue ArgumentError
  	raise ValueSpaceError.new("#{ type }: cannot accept '#{ str }'.")
      end
    end
  end

  def _to_s
    if @data.nan?
      'NaN'
    elsif @data.infinite? == 1
      'INF'
    elsif @data.infinite? == -1
      '-INF'
    else
      sign = XSDFloat.positive?(@data) ? '+' : '-'
      sign + sprintf("%.10g", @data.abs).sub(/[eE]([+-])?0+/) { 'e' + $1 }
    end
  end

  # Convert to single-precision 32-bit floating point value.
  def narrow32bit(f)
    if f.nan? || f.infinite?
      f
    elsif f.abs < MIN_POSITIVE_SINGLE
      XSDFloat.positive?(f) ? POSITIVE_ZERO : NEGATIVE_ZERO
    else
      f
    end
  end

  def self.positive?(value)
    (1 / value) > 0.0
  end
end

# Ruby's Float is double-precision 64-bit floating point value.
class XSDDouble < XSDAnySimpleType
  include FloatConstants
  Type = QName.new(Namespace, DoubleLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data(value)
    # "NaN".to_f => 0 in some environment.  libc?
    if value.is_a?(Float)
      return value
    end
    str = value.to_s.strip
    if str == 'NaN'
      NaN
    elsif str == 'INF'
      POSITIVE_INF
    elsif str == '-INF'
      NEGATIVE_INF
    else
      begin
	return Float(str)
      rescue ArgumentError
	# '1.4e' cannot be parsed on some architecture.
	if /e\z/i =~ str
	  begin
	    return Float(str + '0')
	  rescue ArgumentError
	    raise ValueSpaceError.new("#{ type }: cannot accept '#{ str }'.")
	  end
	else
	  raise ValueSpaceError.new("#{ type }: cannot accept '#{ str }'.")
	end
      end
    end
  end

  def _to_s
    if @data.nan?
      'NaN'
    elsif @data.infinite? == 1
      'INF'
    elsif @data.infinite? == -1
      '-INF'
    else
      sign = (1 / @data > 0.0) ? '+' : '-'
      sign + sprintf("%.16g", @data.abs).sub(/[eE]([+-])?0+/) { 'e' + $1 }
    end
  end
end

class XSDDuration < XSDAnySimpleType
  Type = QName.new(Namespace, DurationLiteral)

  attr_accessor :sign
  attr_accessor :year
  attr_accessor :month
  attr_accessor :day
  attr_accessor :hour
  attr_accessor :min
  attr_accessor :sec

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data(value)
    /^([+\-]?)P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)D)?(T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$/ =~ value.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ value }'.")
    end
    if ($5 and ((!$2 and !$3 and !$4) or (!$6 and !$7 and !$8)))
      # Should we allow 'PT5S' here?
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ value }'.")
    end
    sign = $1
    year = $2.to_i
    month = $3.to_i
    day = $4.to_i
    hour = $6.to_i
    min = $7.to_i
    sec = $8 ? XSDDecimal.new($8) : 0
    [sign, year, month, day, hour, min, sec]
  end

  def _set(data)
    if data.nil?
      @sign = @year = @month = @day = @hour = @min = @sec = @data = nil
      return
    end
    @sign, @year, @month, @day, @hour, @min, @sec = data
    @data = _to_s
    @data.freeze
  end

  def _to_s
    str = ''
    str << @sign if @sign
    str << 'P'
    l = ''
    l << "#{ @year }Y" if @year.nonzero?
    l << "#{ @month }M" if @month.nonzero?
    l << "#{ @day }D" if @day.nonzero?
    r = ''
    r << "#{ @hour }H" if @hour.nonzero?
    r << "#{ @min }M" if @min.nonzero?
    r << "#{ @sec }S" if @sec.nonzero?
    str << l
    if l.empty?
      str << "0D"
    end
    unless r.empty?
      str << "T" << r
    end
    str
  end
end


require 'rational'
require 'date'

module XSDDateTimeImpl
  SecInDay = 86400	# 24 * 60 * 60

  def to_obj(klass)
    if klass == Time
      to_time
    elsif klass == Date
      to_date
    elsif klass == DateTime
      to_datetime
    else
      nil
    end
  end

  def to_time
    begin
      if @data.offset * SecInDay == Time.now.utc_offset
        d = @data
	usec = (d.sec_fraction * SecInDay * 1000000).round
        Time.local(d.year, d.month, d.mday, d.hour, d.min, d.sec, usec)
      else
        d = @data.newof
	usec = (d.sec_fraction * SecInDay * 1000000).round
        Time.gm(d.year, d.month, d.mday, d.hour, d.min, d.sec, usec)
      end
    rescue ArgumentError
      nil
    end
  end

  def to_date
    Date.new0(@data.class.jd_to_ajd(@data.jd, 0, 0), 0, @data.start)
  end

  def to_datetime
    data
  end

  def tz2of(str)
    /^(?:Z|(?:([+\-])(\d\d):(\d\d))?)$/ =~ str
    sign = $1
    hour = $2.to_i
    min = $3.to_i

    of = case sign
      when '+'
	of = +(hour.to_r * 60 + min) / 1440	# 24 * 60
      when '-'
	of = -(hour.to_r * 60 + min) / 1440	# 24 * 60
      else
	0
      end
    of
  end

  def of2tz(offset)
    diffmin = offset * 24 * 60
    if diffmin.zero?
      'Z'
    else
      ((diffmin < 0) ? '-' : '+') << format('%02d:%02d',
    	(diffmin.abs / 60.0).to_i, (diffmin.abs % 60.0).to_i)
    end
  end

  def screen_data(t)
    # convert t to a DateTime as an internal representation.
    if t.respond_to?(:to_datetime)      # 1.9 or later
      t.to_datetime
    elsif t.is_a?(DateTime)
      t
    elsif t.is_a?(Date)
      t = screen_data_str(t)
      t <<= 12 if t.year < 0
      t
    elsif t.is_a?(Time)
      jd = DateTime.civil_to_jd(t.year, t.mon, t.mday, DateTime::ITALY)
      fr = DateTime.time_to_day_fraction(t.hour, t.min, [t.sec, 59].min) +
        t.usec.to_r / 1000000 / SecInDay
      of = t.utc_offset.to_r / SecInDay
      DateTime.new0(DateTime.jd_to_ajd(jd, fr, of), of, DateTime::ITALY)
    else
      screen_data_str(t)
    end
  end

  def add_tz(s)
    s + of2tz(@data.offset)
  end
end

class XSDDateTime < XSDAnySimpleType
  include XSDDateTimeImpl
  Type = QName.new(Namespace, DateTimeLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data_str(t)
    /^([+\-]?\d{4,})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d(?:\.(\d*))?)(Z|(?:[+\-]\d\d:\d\d)?)?$/ =~ t.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ t }'.")
    end
    if $1 == '0000'
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ t }'.")
    end
    year = $1.to_i
    if year < 0
      year += 1
    end
    mon = $2.to_i
    mday = $3.to_i
    hour = $4.to_i
    min = $5.to_i
    sec = $6.to_i
    secfrac = $7
    zonestr = $8
    data = DateTime.civil(year, mon, mday, hour, min, sec, tz2of(zonestr))
    if secfrac
      diffday = secfrac.to_i.to_r / (10 ** secfrac.size) / SecInDay
      data += diffday
      # FYI: new0 and jd_to_rjd are not necessary to use if you don't have
      # exceptional reason.
    end
    [data, secfrac]
  end

  def _set(data)
    if data.nil?
      @data = @secfrac = nil
      return
    end
    @data, @secfrac = data
  end

  def _to_s
    year = (@data.year > 0) ? @data.year : @data.year - 1
    s = format('%.4d-%02d-%02dT%02d:%02d:%02d',
      year, @data.mon, @data.mday, @data.hour, @data.min, @data.sec)
    if @data.sec_fraction.nonzero?
      if @secfrac
  	s << ".#{ @secfrac }"
      else
	s << sprintf("%.16f",
          (@data.sec_fraction * SecInDay).to_f).sub(/^0/, '').sub(/0*$/, '')
      end
    end
    add_tz(s)
  end
end

class XSDTime < XSDAnySimpleType
  include XSDDateTimeImpl
  Type = QName.new(Namespace, TimeLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data_str(t)
    /^(\d\d):(\d\d):(\d\d(?:\.(\d*))?)(Z|(?:([+\-])(\d\d):(\d\d))?)?$/ =~ t.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ t }'.")
    end
    hour = $1.to_i
    min = $2.to_i
    sec = $3.to_i
    secfrac = $4
    zonestr = $5
    data = DateTime.civil(1, 1, 1, hour, min, sec, tz2of(zonestr))
    if secfrac
      diffday = secfrac.to_i.to_r / (10 ** secfrac.size) / SecInDay
      data += diffday
    end
    [data, secfrac]
  end

  def _set(data)
    if data.nil?
      @data = @secfrac = nil
      return
    end
    @data, @secfrac = data
  end

  def _to_s
    s = format('%02d:%02d:%02d', @data.hour, @data.min, @data.sec)
    if @data.sec_fraction.nonzero?
      if @secfrac
  	s << ".#{ @secfrac }"
      else
	s << sprintf("%.16f",
          (@data.sec_fraction * SecInDay).to_f).sub(/^0/, '').sub(/0*$/, '')
      end
    end
    add_tz(s)
  end
end

class XSDDate < XSDAnySimpleType
  include XSDDateTimeImpl
  Type = QName.new(Namespace, DateLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data_str(t)
    /^([+\-]?\d{4,})-(\d\d)-(\d\d)(Z|(?:([+\-])(\d\d):(\d\d))?)?$/ =~ t.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ t }'.")
    end
    year = $1.to_i
    if year < 0
      year += 1
    end
    mon = $2.to_i
    mday = $3.to_i
    zonestr = $4
    DateTime.civil(year, mon, mday, 0, 0, 0, tz2of(zonestr))
  end

  def _to_s
    year = (@data.year > 0) ? @data.year : @data.year - 1
    s = format('%.4d-%02d-%02d', year, @data.mon, @data.mday)
    add_tz(s)
  end
end

class XSDGYearMonth < XSDAnySimpleType
  include XSDDateTimeImpl
  Type = QName.new(Namespace, GYearMonthLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data_str(t)
    /^([+\-]?\d{4,})-(\d\d)(Z|(?:([+\-])(\d\d):(\d\d))?)?$/ =~ t.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ t }'.")
    end
    year = $1.to_i
    if year < 0
      year += 1
    end
    mon = $2.to_i
    zonestr = $3
    DateTime.civil(year, mon, 1, 0, 0, 0, tz2of(zonestr))
  end

  def _to_s
    year = (@data.year > 0) ? @data.year : @data.year - 1
    s = format('%.4d-%02d', year, @data.mon)
    add_tz(s)
  end
end

class XSDGYear < XSDAnySimpleType
  include XSDDateTimeImpl
  Type = QName.new(Namespace, GYearLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data_str(t)
    /^([+\-]?\d{4,})(Z|(?:([+\-])(\d\d):(\d\d))?)?$/ =~ t.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ t }'.")
    end
    year = $1.to_i
    if year < 0
      year += 1
    end
    zonestr = $2
    DateTime.civil(year, 1, 1, 0, 0, 0, tz2of(zonestr))
  end

  def _to_s
    year = (@data.year > 0) ? @data.year : @data.year - 1
    s = format('%.4d', year)
    add_tz(s)
  end
end

class XSDGMonthDay < XSDAnySimpleType
  include XSDDateTimeImpl
  Type = QName.new(Namespace, GMonthDayLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data_str(t)
    /^(\d\d)-(\d\d)(Z|(?:[+\-]\d\d:\d\d)?)?$/ =~ t.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ t }'.")
    end
    mon = $1.to_i
    mday = $2.to_i
    zonestr = $3
    DateTime.civil(1, mon, mday, 0, 0, 0, tz2of(zonestr))
  end

  def _to_s
    s = format('%02d-%02d', @data.mon, @data.mday)
    add_tz(s)
  end
end

class XSDGDay < XSDAnySimpleType
  include XSDDateTimeImpl
  Type = QName.new(Namespace, GDayLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data_str(t)
    /^(\d\d)(Z|(?:[+\-]\d\d:\d\d)?)?$/ =~ t.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ t }'.")
    end
    mday = $1.to_i
    zonestr = $2
    DateTime.civil(1, 1, mday, 0, 0, 0, tz2of(zonestr))
  end

  def _to_s
    s = format('%02d', @data.mday)
    add_tz(s)
  end
end

class XSDGMonth < XSDAnySimpleType
  include XSDDateTimeImpl
  Type = QName.new(Namespace, GMonthLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data_str(t)
    /^(\d\d)(Z|(?:[+\-]\d\d:\d\d)?)?$/ =~ t.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ t }'.")
    end
    mon = $1.to_i
    zonestr = $2
    DateTime.civil(1, mon, 1, 0, 0, 0, tz2of(zonestr))
  end

  def _to_s
    s = format('%02d', @data.mon)
    add_tz(s)
  end
end

class XSDHexBinary < XSDAnySimpleType
  Type = QName.new(Namespace, HexBinaryLiteral)

  # String in Ruby could be a binary.
  def initialize(value = nil)
    init(Type, value)
  end

  def set_encoded(value)
    if /^[0-9a-fA-F]*$/ !~ value
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ value }'.")
    end
    @data = String.new(value).strip
    @is_nil = false
  end

  def string
    [@data].pack("H*")
  end

private

  def screen_data(value)
    value.unpack("H*")[0].tr('a-f', 'A-F')
  end
end

class XSDBase64Binary < XSDAnySimpleType
  Type = QName.new(Namespace, Base64BinaryLiteral)

  # String in Ruby could be a binary.
  def initialize(value = nil)
    init(Type, value)
  end

  def set_encoded(value)
    if /^[A-Za-z0-9+\/=]*$/ !~ value
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ value }'.")
    end
    @data = String.new(value).strip
    @is_nil = false
  end

  def string
    @data.unpack("m")[0]
  end

private

  def screen_data(value)
    [value].pack("m").strip
  end
end

class XSDAnyURI < XSDAnySimpleType
  Type = QName.new(Namespace, AnyURILiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data(value)
    begin
      URI.parse(value.to_s.strip)
    rescue URI::InvalidURIError
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ value }'.")
    end
  end
end

class XSDQName < XSDAnySimpleType
  Type = QName.new(Namespace, QNameLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data(value)
    /^(?:([^:]+):)?([^:]+)$/ =~ value.to_s.strip
    unless Regexp.last_match
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ value }'.")
    end
    prefix = $1
    localpart = $2
    [prefix, localpart]
  end

  def _set(data)
    if data.nil?
      @prefix = @localpart = @data = nil
      return
    end
    @prefix, @localpart = data
    @data = _to_s
    @data.freeze
  end

  def _to_s
    if @prefix
      "#{ @prefix }:#{ @localpart }"
    else
      "#{ @localpart }"
    end
  end
end


###
## Derived types
#
class XSDNormalizedString < XSDString
  Type = QName.new(Namespace, NormalizedStringLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data(value)
    if /[\t\r\n]/ =~ value
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ value }'.")
    end
    super
  end
end

class XSDInteger < XSDDecimal
  Type = QName.new(Namespace, IntegerLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def screen_data_str(str)
    begin
      data = Integer(str)
    rescue ArgumentError
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ str }'.")
    end
    unless validate(data)
      raise ValueSpaceError.new("#{ type }: cannot accept '#{ str }'.")
    end
    data
  end

  def _set(value)
    @data = value
  end

  def _to_s()
    @data.to_s
  end

  def validate(v)
    max = maxinclusive
    min = mininclusive
    (max.nil? or v <= max) and (min.nil? or v >= min)
  end

  def maxinclusive
    nil
  end

  def mininclusive
    nil
  end

  PositiveMinInclusive = 1
  def positive(v)
    PositiveMinInclusive <= v
  end
end

class XSDNonPositiveInteger < XSDInteger
  Type = QName.new(Namespace, NonPositiveIntegerLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    0
  end

  def mininclusive
    nil
  end
end

class XSDNegativeInteger < XSDNonPositiveInteger
  Type = QName.new(Namespace, NegativeIntegerLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    -1
  end

  def mininclusive
    nil
  end
end

class XSDLong < XSDInteger
  Type = QName.new(Namespace, LongLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    +9223372036854775807
  end

  def mininclusive
    -9223372036854775808
  end
end

class XSDInt < XSDLong
  Type = QName.new(Namespace, IntLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    +2147483647
  end

  def mininclusive
    -2147483648
  end
end

class XSDShort < XSDInt
  Type = QName.new(Namespace, ShortLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    +32767
  end

  def mininclusive
    -32768
  end
end

class XSDByte < XSDShort
  Type = QName.new(Namespace, ByteLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    +127
  end

  def mininclusive
    -128
  end
end

class XSDNonNegativeInteger < XSDInteger
  Type = QName.new(Namespace, NonNegativeIntegerLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    nil
  end

  def mininclusive
    0
  end
end

class XSDUnsignedLong < XSDNonNegativeInteger
  Type = QName.new(Namespace, UnsignedLongLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    +18446744073709551615
  end

  def mininclusive
    0
  end
end

class XSDUnsignedInt < XSDUnsignedLong
  Type = QName.new(Namespace, UnsignedIntLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    +4294967295
  end

  def mininclusive
    0
  end
end

class XSDUnsignedShort < XSDUnsignedInt
  Type = QName.new(Namespace, UnsignedShortLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    +65535
  end

  def mininclusive
    0
  end
end

class XSDUnsignedByte < XSDUnsignedShort
  Type = QName.new(Namespace, UnsignedByteLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    +255
  end

  def mininclusive
    0
  end
end

class XSDPositiveInteger < XSDNonNegativeInteger
  Type = QName.new(Namespace, PositiveIntegerLiteral)

  def initialize(value = nil)
    init(Type, value)
  end

private

  def maxinclusive
    nil
  end

  def mininclusive
    1
  end
end


end
