# date.rb: Written by Tadayoshi Funaba 1998-2002
# $Id: date.rb,v 2.8 2002-06-08 00:39:51+09 tadf Exp $

require 'rational'
require 'date/format'

class Date

  include Comparable

  MONTHNAMES = [nil] + %w(January February March April May June July
			  August September October November December)

  DAYNAMES = %w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)

  ABBR_MONTHNAMES = [nil] + %w(Jan Feb Mar Apr May Jun
			       Jul Aug Sep Oct Nov Dec)

  ABBR_DAYNAMES = %w(Sun Mon Tue Wed Thu Fri Sat)

  ITALY     = 2299161 # 1582-10-15
  ENGLAND   = 2361222 # 1752-09-14
  JULIAN    = false
  GREGORIAN = true

  def self.os? (jd, sg)
    case sg
    when Numeric; jd < sg
    else;         not sg
    end
  end

  def self.ns? (jd, sg) not os?(jd, sg) end

  def self.civil_to_jd(y, m, d, sg=GREGORIAN)
    if m <= 2
      y -= 1
      m += 12
    end
    a = (y / 100.0).floor
    b = 2 - a + (a / 4.0).floor
    jd = (365.25 * (y + 4716)).floor +
      (30.6001 * (m + 1)).floor +
      d + b - 1524
    if os?(jd, sg)
      jd -= b
    end
    jd
  end

  def self.jd_to_civil(jd, sg=GREGORIAN)
    if os?(jd, sg)
      a = jd
    else
      x = ((jd - 1867216.25) / 36524.25).floor
      a = jd + 1 + x - (x / 4.0).floor
    end
    b = a + 1524
    c = ((b - 122.1) / 365.25).floor
    d = (365.25 * c).floor
    e = ((b - d) / 30.6001).floor
    dom = b - d - (30.6001 * e).floor
    if e <= 13
      m = e - 1
      y = c - 4716
    else
      m = e - 13
      y = c - 4715
    end
    return y, m, dom
  end

  def self.ordinal_to_jd(y, d, sg=GREGORIAN)
    civil_to_jd(y, 1, d, sg)
  end

  def self.jd_to_ordinal(jd, sg=GREGORIAN)
    y = jd_to_civil(jd, sg)[0]
    doy = jd - civil_to_jd(y - 1, 12, 31, ns?(jd, sg))
    return y, doy
  end

  def self.jd_to_commercial(jd, sg=GREGORIAN)
    ns = ns?(jd, sg)
    a = jd_to_civil(jd - 3, ns)[0]
    y = if jd >= commercial_to_jd(a + 1, 1, 1, ns) then a + 1 else a end
    w = 1 + (jd - commercial_to_jd(y, 1, 1, ns)) / 7
    d = (jd + 1) % 7
    if d.zero? then d = 7 end
    return y, w, d
  end

  def self.commercial_to_jd(y, w, d, ns=GREGORIAN)
    jd = civil_to_jd(y, 1, 4, ns)
    (jd - (((jd - 1) + 1) % 7)) +
      7 * (w - 1) +
      (d - 1)
  end

  %w(self.clfloor clfloor).each do |name|
    module_eval <<-"end;"
      def #{name}(x, y=1)
	q, r = x.divmod(y)
	q = q.to_i
	return q, r
      end
    end;
  end

  private_class_method :clfloor
  private              :clfloor

  def self.ajd_to_jd(ajd, of=0) clfloor(ajd + of + 1.to_r/2) end
  def self.jd_to_ajd(jd, fr, of=0) jd + fr - of - 1.to_r/2 end

  def self.day_fraction_to_time(fr)
    h,   fr = clfloor(fr, 1.to_r/24)
    min, fr = clfloor(fr, 1.to_r/1440)
    s,   fr = clfloor(fr, 1.to_r/86400)
    return h, min, s, fr
  end

  def self.time_to_day_fraction(h, min, s)
    h.to_r/24 + min.to_r/1440 + s.to_r/86400
  end

  def self.amjd_to_ajd(amjd) amjd + 4800001.to_r/2 end
  def self.ajd_to_amjd(ajd) ajd - 4800001.to_r/2 end
  def self.mjd_to_jd(mjd) mjd + 2400001 end
  def self.jd_to_mjd(jd) jd - 2400001 end
  def self.ld_to_jd(ld) ld + 2299160 end
  def self.jd_to_ld(jd) jd - 2299160 end

  def self.jd_to_wday(jd) (jd + 1) % 7 end

  def self.julian_leap? (y) y % 4 == 0 end
  def self.gregorian_leap? (y) y % 4 == 0 and y % 100 != 0 or y % 400 == 0 end

  class << self; alias_method :leap?, :gregorian_leap? end
  class << self; alias_method :new0, :new end

  def self.valid_jd? (jd, sg=ITALY) jd end

  def self.jd(jd=0, sg=ITALY)
    jd = valid_jd?(jd, sg)
    new0(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  def self.valid_ordinal? (y, d, sg=ITALY)
    if d < 0
      ny, = clfloor(y + 1, 1)
      jd = ordinal_to_jd(ny, d + 1, sg)
      ns = ns?(jd, sg)
      return unless [y] == jd_to_ordinal(jd, sg)[0..0]
      return unless [ny, 1] == jd_to_ordinal(jd - d, ns)
    else
      jd = ordinal_to_jd(y, d, sg)
      return unless [y, d] == jd_to_ordinal(jd, sg)
    end
    jd
  end

  def self.ordinal(y=-4712, d=1, sg=ITALY)
    unless jd = valid_ordinal?(y, d, sg)
      raise ArgumentError, 'invalid date'
    end
    new0(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  def self.valid_civil? (y, m, d, sg=ITALY)
    if m < 0
      m += 13
    end
    if d < 0
      ny, nm = clfloor(y * 12 + m, 12)
      nm,    = clfloor(nm + 1, 1)
      jd = civil_to_jd(ny, nm, d + 1, sg)
      ns = ns?(jd, sg)
      return unless [y, m] == jd_to_civil(jd, sg)[0..1]
      return unless [ny, nm, 1] == jd_to_civil(jd - d, ns)
    else
      jd = civil_to_jd(y, m, d, sg)
      return unless [y, m, d] == jd_to_civil(jd, sg)
    end
    jd
  end

  class << self; alias_method :valid_date?, :valid_civil? end

  def self.civil(y=-4712, m=1, d=1, sg=ITALY)
    unless jd = valid_civil?(y, m, d, sg)
      raise ArgumentError, 'invalid date'
    end
    new0(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  class << self; alias_method :new, :civil end

  def self.valid_commercial? (y, w, d, sg=ITALY)
    if d < 0
      d += 8
    end
    if w < 0
      w = jd_to_commercial(commercial_to_jd(y + 1, 1, 1) + w * 7)[1]
    end
    jd = commercial_to_jd(y, w, d)
    return unless ns?(jd, sg)
    return unless [y, w, d] == jd_to_commercial(jd)
    jd
  end

  def self.commercial(y=1582, w=41, d=5, sg=ITALY)
    unless jd = valid_commercial?(y, w, d, sg)
      raise ArgumentError, 'invalid date'
    end
    new0(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  def self.new_with_hash(elem, sg)
    elem ||= {}
    y, m, d = elem.select(:year, :mon, :mday)
    if [y, m, d].include? nil
      raise ArgumentError, 'invalid date'
    else
      civil(y, m, d, sg)
    end
  end

  private_class_method :new_with_hash

  def self.strptime(str='-4712-01-01', fmt='%F', sg=ITALY)
    elem = _strptime(str, fmt)
    new_with_hash(elem, sg)
  end

  def self.parse(str='-4712-01-01', comp=false, sg=ITALY)
    elem = _parse(str, comp)
    new_with_hash(elem, sg)
  end

  def self.today(sg=ITALY)
    jd = civil_to_jd(*(Time.now.to_a[3..5].reverse << sg))
    new0(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  class << self

    def once(*ids)
      for id in ids
	module_eval <<-"end;"
	  alias_method :__#{id.to_i}__, :#{id.to_s}
	  private :__#{id.to_i}__
	  def #{id.to_s}(*args, &block)
	    (@__#{id.to_i}__ ||= [__#{id.to_i}__(*args, &block)])[0]
	  end
	end;
      end
    end

    private :once

  end

  def initialize(ajd=0, of=0, sg=ITALY) @ajd, @of, @sg = ajd, of, sg end

  def ajd() @ajd end
  def amjd() type.ajd_to_amjd(@ajd) end

  once :amjd

  def jd() type.ajd_to_jd(@ajd, @of)[0] end
  def day_fraction() type.ajd_to_jd(@ajd, @of)[1] end
  def mjd() type.jd_to_mjd(jd) end
  def ld() type.jd_to_ld(jd) end

  once :jd, :day_fraction, :mjd, :ld

  def civil() type.jd_to_civil(jd, @sg) end
  def ordinal() type.jd_to_ordinal(jd, @sg) end
  def commercial() type.jd_to_commercial(jd, @sg) end

  once :civil, :ordinal, :commercial
  private :civil, :ordinal, :commercial

  def year() civil[0] end
  def yday() ordinal[1] end
  def mon() civil[1] end
  def mday() civil[2] end

  alias_method :month, :mon
  alias_method :day, :mday

  def time() type.day_fraction_to_time(day_fraction) end

  once :time
  private :time

  def hour() time[0] end
  def min() time[1] end
  def sec() time[2] end
  def sec_fraction() time[3] end

  private :hour, :min, :sec, :sec_fraction

  def zone
    ['Z',
      format('%+.2d%02d',
	     (@of     / (1.to_r/24)).to_i,
	     (@of.abs % (1.to_r/24) / (1.to_r/1440)).to_i)
    ][@of<=>0]
  end

  private :zone

  def cwyear() commercial[0] end
  def cweek() commercial[1] end
  def cwday() commercial[2] end

  def wday() type.jd_to_wday(jd) end

  once :wday

  def os? () type.os?(jd, @sg) end
  def ns? () type.ns?(jd, @sg) end

  once :os?, :ns?

  def leap?
    type.jd_to_civil(type.civil_to_jd(year, 3, 1, ns?) - 1,
		     ns?)[-1] == 29
  end

  once :leap?

  def start() @sg end
  def new_start(sg=type::ITALY) type.new0(@ajd, @of, sg) end

  def italy() new_start(type::ITALY) end
  def england() new_start(type::ENGLAND) end
  def julian() new_start(type::JULIAN) end
  def gregorian() new_start(type::GREGORIAN) end

  def offset() @of end
  def new_offset(of=0) type.new0(@ajd, of, @sg) end

  private :offset, :new_offset

  def + (n)
    case n
    when Numeric; return type.new0(@ajd + n, @of, @sg)
    end
    raise TypeError, 'expected numeric'
  end

  def - (x)
    case x
    when Numeric; return type.new0(@ajd - x, @of, @sg)
    when Date;    return @ajd - x.ajd
    end
    raise TypeError, 'expected numeric or date'
  end

  def <=> (other)
    case other
    when Numeric; return @ajd <=> other
    when Date;    return @ajd <=> other.ajd
    end
    raise TypeError, 'expected numeric or date'
  end

  def === (other)
    case other
    when Numeric; return jd == other
    when Date;    return jd == other.jd
    end
    raise TypeError, 'expected numeric or date'
  end

  def >> (n)
    y, m = clfloor(year * 12 + (mon - 1) + n, 12)
    m,   = clfloor(m + 1, 1)
    d = mday
    d -= 1 until jd2 = type.valid_civil?(y, m, d, ns?)
    self + (jd2 - jd)
  end

  def << (n) self >> -n end

  def step(limit, step)
    da = self
    op = [:-,:<=,:>=][step<=>0]
    while da.__send__(op, limit)
      yield da
      da += step
    end
    self
  end

  def upto(max, &block) step(max, +1, &block) end
  def downto(min, &block) step(min, -1, &block) end

  def succ() self + 1 end

  alias_method :next, :succ

  def eql? (other) Date === other and self == other end
  def hash() @ajd.hash end

  def inspect() format('#<%s: %s,%s,%s>', type, @ajd, @of, @sg) end
  def to_s() strftime end

  def _dump(limit) Marshal.dump([@ajd, @of, @sg], -1) end

# def self._load(str) new0(*Marshal.load(str)) end

  def self._load(str)
    a = Marshal.load(str)
    if a.size == 2
      ajd,     sg = a
           of = 0
      ajd -= 1.to_r/2
    else
      ajd, of, sg = a
    end
    new0(ajd, of, sg)
  end

end

class DateTime < Date

  def self.valid_time? (h, min, s)
    h   += 24 if h   < 0
    min += 60 if min < 0
    s   += 60 if s   < 0
    return unless (0..24) === h and
		  (0..59) === min and
		  (0..59) === s
    time_to_day_fraction(h, min, s)
  end

  def self.jd(jd=0, h=0, min=0, s=0, of=0, sg=ITALY)
    unless (jd = valid_jd?(jd, sg)) and
	   (fr = valid_time?(h, min, s))
      raise ArgumentError, 'invalid date'
    end
    new0(jd_to_ajd(jd, fr, of), of, sg)
  end

  def self.ordinal(y=-4712, d=1, h=0, min=0, s=0, of=0, sg=ITALY)
    unless (jd = valid_ordinal?(y, d, sg)) and
	   (fr = valid_time?(h, min, s))
      raise ArgumentError, 'invalid date'
    end
    new0(jd_to_ajd(jd, fr, of), of, sg)
  end

  def self.civil(y=-4712, m=1, d=1, h=0, min=0, s=0, of=0, sg=ITALY)
    unless (jd = valid_civil?(y, m, d, sg)) and
	   (fr = valid_time?(h, min, s))
      raise ArgumentError, 'invalid date'
    end
    new0(jd_to_ajd(jd, fr, of), of, sg)
  end

  class << self; alias_method :new, :civil end

  def self.commercial(y=1582, w=41, d=5, h=0, min=0, s=0, of=0, sg=ITALY)
    unless (jd = valid_commercial?(y, w, d, sg)) and
	   (fr = valid_time?(h, min, s))
      raise ArgumentError, 'invalid date'
    end
    new0(jd_to_ajd(jd, fr, of), of, sg)
  end

  def self.new_with_hash(elem, sg)
    elem ||= {}
    y, m, d, h, min, s, of =
      elem.select(:year, :mon, :mday, :hour, :min, :sec, :offset)
    h   ||= 0
    min ||= 0
    s   ||= 0
    of  ||= 0
    if [y, m, d].include? nil
      raise ArgumentError, 'invalid date'
    else
      civil(y, m, d, h, min, s, of.to_r/86400, sg)
    end
  end

  private_class_method :new_with_hash

  def self.strptime(str='-4712-01-01T00:00:00Z', fmt='%FT%T%Z', sg=ITALY)
    elem = _strptime(str, fmt)
    new_with_hash(elem, sg)
  end

  def self.parse(str='-4712-01-01T00:00:00Z', comp=false, sg=ITALY)
    elem = _parse(str, comp)
    new_with_hash(elem, sg)
  end

  class << self; undef_method :today end

  def self.now(sg=ITALY)
    i = Time.now
    a = i.to_a[0..5].reverse
    jd = civil_to_jd(*(a[0,3] << sg))
    fr = time_to_day_fraction(*(a[3,3])) + i.usec.to_r/86400000000
    d = Time.gm(*i.to_a).to_i - i.to_i
    d += d / d.abs if d.nonzero?
    of = (d / 60).to_r/1440
    new0(jd_to_ajd(jd, fr, of), of, sg)
  end

  public :hour, :min, :sec, :sec_fraction, :zone, :offset, :new_offset

end

class Date

  [ %w(exist1?	valid_jd?),
    %w(exist2?	valid_ordinal?),
    %w(exist3?	valid_date?),
    %w(exist?	valid_date?),
    %w(existw?	valid_commercial?),
    %w(new1	jd),
    %w(new2	ordinal),
    %w(new3	new),
    %w(neww	commercial)
  ].each do |old, new|
    module_eval <<-"end;"
      def self.#{old}(*args, &block)
	if $VERBOSE
	  $stderr.puts("\#{caller.shift.sub(/:in .*/, '')}: " \
		       "warning: \#{self}::#{old} is deprecated; " \
		       "use \#{self}::#{new}")
	end
	#{new}(*args, &block)
      end
    end;
  end

  [ %w(sg	start),
    %w(newsg	new_start),
    %w(of	offset),
    %w(newof	new_offset)
  ].each do |old, new|
    module_eval <<-"end;"
      def #{old}(*args, &block)
	if $VERBOSE
	  $stderr.puts("\#{caller.shift.sub(/:in .*/, '')}: " \
		       "warning: \#{type}\##{old} is deprecated; " \
		       "use \#{type}\##{new}")
	end
	#{new}(*args, &block)
      end
    end;
  end

  private :of, :newof

end

class DateTime < Date

  public :of, :newof

end
