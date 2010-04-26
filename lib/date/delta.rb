# delta.rb: Written by Tadayoshi Funaba 2004-2009

require 'date'
require 'date/delta/parser'

class Date

  class Delta

    include Comparable

    UNIT_PREFIXES = {
      'yotta'      => Rational(10**24),
      'zetta'      => Rational(10**21),
      'exa'        => Rational(10**18),
      'peta'       => Rational(10**15),
      'tera'       => Rational(10**12),
      'giga'       => Rational(10**9),
      'mega'       => Rational(10**6),
      'kilo'       => Rational(10**3),
      'hecto'      => Rational(10**2),
      'deca'       => Rational(10**1),
      'deka'       => Rational(10**1),
      'deci'       => Rational(1, 10**1),
      'centi'      => Rational(1, 10**2),
      'milli'      => Rational(1, 10**3),
      'decimilli'  => Rational(1, 10**4),
      'centimilli' => Rational(1, 10**5),
      'micro'      => Rational(1, 10**6),
      'nano'       => Rational(1, 10**9),
      'millimicro' => Rational(1, 10**9),
      'pico'       => Rational(1, 10**12),
      'micromicro' => Rational(1, 10**12),
      'femto'      => Rational(1, 10**15),
      'atto'       => Rational(1, 10**18),
      'zepto'      => Rational(1, 10**21),
      'yocto'      => Rational(1, 10**24)
    }

    IUNITS = {
      'year'       => Complex(0, 12),
      'month'      => Complex(0, 1)
    }

    RUNITS = {
      'day'        => Rational(1),
      'week'       => Rational(7),
      'sennight'   => Rational(7),
      'fortnight'  => Rational(14),
      'hour'       => Rational(1, 24),
      'minute'     => Rational(1, 1440),
      'second'     => Rational(1, 86400)
    }

    UNIT_PREFIXES.each do |k, v|
      RUNITS[k + 'second'] = v * RUNITS['second']
    end

    remove_const :UNIT_PREFIXES

    UNITS = {}

    IUNITS.each do |k, v|
      UNITS[k] = v
    end

    RUNITS.each do |k, v|
      UNITS[k] = v
    end

    UNITS4KEY = {}

    UNITS.each do |k, v|
      UNITS4KEY[k] = UNITS4KEY[k + 's'] = v
    end

    UNITS4KEY['y'] = UNITS4KEY['years']
    UNITS4KEY['yr'] = UNITS4KEY['years']
    UNITS4KEY['yrs'] = UNITS4KEY['years']
    UNITS4KEY['m'] = UNITS4KEY['months']
    UNITS4KEY['mo'] = UNITS4KEY['months']
    UNITS4KEY['mon'] = UNITS4KEY['months']
    UNITS4KEY['mnth'] = UNITS4KEY['months']
    UNITS4KEY['mnths'] = UNITS4KEY['months']
    UNITS4KEY['w'] = UNITS4KEY['weeks']
    UNITS4KEY['wk'] = UNITS4KEY['weeks']
    UNITS4KEY['d'] = UNITS4KEY['days']
    UNITS4KEY['dy'] = UNITS4KEY['days']
    UNITS4KEY['dys'] = UNITS4KEY['days']
    UNITS4KEY['h'] = UNITS4KEY['hours']
    UNITS4KEY['hr'] = UNITS4KEY['hours']
    UNITS4KEY['hrs'] = UNITS4KEY['hours']
    UNITS4KEY['min'] = UNITS4KEY['minutes']
    UNITS4KEY['mins'] = UNITS4KEY['minutes']
    UNITS4KEY['s'] = UNITS4KEY['seconds']
    UNITS4KEY['sec'] = UNITS4KEY['seconds']
    UNITS4KEY['secs'] = UNITS4KEY['seconds']
    UNITS4KEY['ms'] = UNITS4KEY['milliseconds']
    UNITS4KEY['msec'] = UNITS4KEY['milliseconds']
    UNITS4KEY['msecs'] = UNITS4KEY['milliseconds']
    UNITS4KEY['milli'] = UNITS4KEY['milliseconds']
    UNITS4KEY['us'] = UNITS4KEY['microseconds']
    UNITS4KEY['usec'] = UNITS4KEY['microseconds']
    UNITS4KEY['usecs'] = UNITS4KEY['microseconds']
    UNITS4KEY['micro'] = UNITS4KEY['microseconds']
    UNITS4KEY['ns'] = UNITS4KEY['nanoseconds']
    UNITS4KEY['nsec'] = UNITS4KEY['nanoseconds']
    UNITS4KEY['nsecs'] = UNITS4KEY['nanoseconds']
    UNITS4KEY['nano'] = UNITS4KEY['nanoseconds']

    def self.delta_to_dhms(delta)
      fr = delta.imag.abs
      y,   fr = fr.divmod(12)
      m,   fr = fr.divmod(1)

      if delta.imag < 0
	y = -y
	m = -m
      end

      fr = delta.real.abs
      ss,  fr = fr.divmod(SECONDS_IN_DAY) # 4p
      d,   ss = ss.divmod(86400)
      h,   ss = ss.divmod(3600)
      min, s  = ss.divmod(60)

      if delta.real < 0
	d = -d
	h = -h
	min = -min
	s = -s
      end

      return y, m, d, h, min, s, fr
    end

    def self.dhms_to_delta(y, m, d, h, min, s, fr)
      fr = 0 if fr == 0
      Complex(0, y.to_i * 12 + m.to_i) +
	Rational(d * 86400 + h * 3600 + min * 60 + (s + fr), 86400) # 4p
    end

    def initialize(delta)
      @delta = delta
      @__ca__ = {}
    end

    class << self; alias_method :new!, :new end

    def self.new(arg=0, h=0, min=0, s=0)
      if Hash === arg
	d = Complex(0)
	arg.each do |k, v|
	  k = k.to_s.downcase
	  unless UNITS4KEY[k]
	    raise ArgumentError, "unknown keyword #{k}"
	  end
	  d += v * UNITS4KEY[k]
	end
      else
	d = dhms_to_delta(0, 0, arg, h, min, s, 0)
      end
      new!(d)
    end

    UNITS.each_key do |k|
      module_eval <<-"end;"
	def self.#{k}s(n=1)
	  new(:d=>n * UNITS['#{k}'])
	end
      end;
    end

    class << self; alias_method :mins, :minutes end
    class << self; alias_method :secs, :seconds end

    def self.parse(str)
      d = begin (@@pa ||= Parser.new).parse(str)
	  rescue Racc::ParseError
	    raise ArgumentError, 'syntax error'
	  end
      new!(d)
    end

    def self.diff(d1, d2) new(d1.ajd - d2.ajd) end

    class << self

      def once(*ids) # :nodoc: -- restricted
	for id in ids
	  module_eval <<-"end;"
	    alias_method :__#{id.object_id}__, :#{id.to_s}
	    private :__#{id.object_id}__
	    def #{id.to_s}(*args)
	      @__ca__[#{id.object_id}] ||= __#{id.object_id}__(*args)
	    end
	  end;
        end
      end

      private :once

    end

    def dhms() self.class.delta_to_dhms(@delta) end

    once :dhms

    def delta() @delta end

    protected :delta

    def years() dhms[0] end
    def months() dhms[1] end
    def days() dhms[2] end
    def hours() dhms[3] end
    def minutes() dhms[4] end
    def seconds() dhms[5] end
    def second_fractions() dhms[6] end

    alias_method :mins, :minutes
    alias_method :secs, :seconds
    alias_method :sec_fractions, :second_fractions

    RUNITS.each_key do |k|
      module_eval <<-"end;"
	def in_#{k}s(u=1)
	  if @delta.imag != 0
	    raise ArgumentError, "#{k}: #{self} has month"
	  end
	  @delta.real / (u * RUNITS['#{k}'])
	end
      end;
    end

    alias_method :in_mins, :in_minutes
    alias_method :in_secs, :in_seconds

    def zero?() @delta.zero? end
    def nonzero?() unless zero? then self end end

    def integer? () @delta.imag == 0 && @delta.real.integer? end

    def -@ () self.class.new!(-@delta) end
    def +@ () self.class.new!(+@delta) end

    def dx_addsub(m, n)
      case n
      when Numeric; return self.class.new!(@delta.__send__(m, n))
      when Delta; return self.class.new!(@delta.__send__(m, n.delta))
      else
	l, r = n.coerce(self)
	return l.__send__(m, r)
      end
    end

    private :dx_addsub

    def + (n) dx_addsub(:+, n) end
    def - (n) dx_addsub(:-, n) end

    def dx_muldiv(m, n)
      case n
      when Numeric
	return self.class.new!(@delta.__send__(m, n))
      else
	l, r = n.coerce(self)
	return l.__send__(m, r)
      end
    end

    private :dx_muldiv

    def * (n) dx_muldiv(:*, n) end
    def / (n) dx_muldiv(:/, n) end

    def dx_conv1(m, n)
      if @delta.imag != 0
	raise ArgumentError, "#{m}: #{self} has month"
      end
      case n
      when Numeric
	return self.class.new!(Complex(@delta.real.__send__(m, n), 0))
      else
	l, r = n.coerce(self)
	return l.__send__(m, r)
      end
    end

    private :dx_conv1

    def % (n) dx_conv1(:%, n) end

    def div(n) dx_conv1(:div, n) end
    def modulo(n) dx_conv1(:modulo, n) end
    def divmod(n) [div(n), modulo(n)] end

    def quotient(n)
      if @delta.imag != 0
	raise ArgumentError, "quotient: #{self} has month"
      end
      case n
      when Numeric
	return self.class.new!(Complex((@delta.real / n).truncate))
      else
	l, r = n.coerce(self)
	return l.__send__(m, r)
      end
    end

    def remainder(n) dx_conv1(:remainder, n) end
    def quotrem(n) [quotient(n), remainder(n)] end

    def ** (n) dx_conv1(:**, n) end
    def quo(n) dx_muldiv(:quo, n) end

    def <=> (other)
      if @delta.imag != 0
	raise ArgumentError, "<=>: #{self} has month"
      end
      case other
      when Numeric; return @delta.real <=> other
      when Delta;   return @delta.real <=> other.delta.real
      else
	begin
	  l, r = other.coerce(self)
	  return l <=> r
	rescue NoMethodError
	end
      end
      nil
    end

    def == (other)
      case other
      when Numeric; return @delta == other
      when Delta;   return @delta == other
      else
	begin
	  l, r = other.coerce(self)
	  return l == r
	rescue NoMethodError
	end
      end
      nil
    end

    def coerce(other)
      case other
      when Numeric; return other, @delta
      else
	super
      end
    end

    def eql? (other) Delta === other && self == other end
    def hash() @delta.hash end

    def dx_conv0(m)
      if @delta.imag != 0
	raise ArgumentError, "#{m}: #{self} has month"
      end
      @delta.real.__send__(m)
    end

    private :dx_conv0

    def abs() dx_conv0(:abs) end

    def ceil() dx_conv0(:ceil) end
    def floor() dx_conv0(:floor) end
    def round() dx_conv0(:round) end
    def truncate() dx_conv0(:truncate) end

    def to_i() dx_conv0(:to_i) end
    def to_f() dx_conv0(:to_f) end
    def to_r() dx_conv0(:to_r) end
    def to_c() @delta end

    alias_method :to_int, :to_i

    def inspect() format('#<%s: %s (%s)>', self.class, to_s, @delta) end

    def to_s
      format(%(%s(%dd %.02d:%02d'%02d"%03d)%s(%dy %dm)), # '
	     if @delta.real < 0 then '-' else '+' end,
	     days.abs, hours.abs, mins.abs, secs.abs, sec_fractions.abs * 1000,
	     if @delta.imag < 0 then '-' else '+' end,
	     years.abs, months.abs)
    end

    def marshal_dump() @delta end

    def marshal_load(a)
      @delta = a
      @__ca__ = {}
    end

  end

end

vsave = $VERBOSE
$VERBOSE = false

class Date

  def + (n)
    case n
    when Numeric; return self.class.new!(@ajd + n, @of, @sg)
    when Delta
      d = n.__send__(:delta)
      return (self >> d.imag) + d.real
    end
    raise TypeError, 'expected numeric'
  end

  def - (x)
    case x
    when Numeric; return self.class.new!(@ajd - x, @of, @sg)
    when Date;    return @ajd - x.ajd
    when Delta
      d = x.__send__(:delta)
      return (self << d.imag) - d.real
    end
    raise TypeError, 'expected numeric'
  end

end

$VERBOSE = vsave
