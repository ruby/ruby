# date2.rb: Written by Tadayoshi Funaba 1998, 1999
# $Id: date2.rb,v 1.15 1999/08/29 15:23:52 tadf Exp $

class Date

  include Comparable

  MONTHNAMES = [ nil, 'January', 'February', 'March',
    'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December' ]

  DAYNAMES = [ 'Sunday', 'Monday', 'Tuesday',
    'Wednesday', 'Thursday', 'Friday', 'Saturday' ]

  ITALY   = 2299161 # Oct  15, 1582
  ENGLAND = 2361222 # Sept 14, 1752

  class << self

    def os? (jd, sg)
      case sg
      when Numeric; jd < sg
      else;         not sg
      end
    end

    def ns? (jd, sg) not os?(jd, sg) end

    def civil_to_jd(y, m, d, sg=true)
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

    def jd_to_civil(jd, sg=true)
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

    def ordinal_to_jd(y, d, sg=true)
      civil_to_jd(y, 1, d, sg)
    end

    def jd_to_ordinal(jd, sg=true)
      y = jd_to_civil(jd, sg)[0]
      doy = jd - civil_to_jd(y - 1, 12, 31, ns?(jd, sg))
      return y, doy
    end

    def mjd_to_jd(mjd) mjd + 2400000.5 end
    def jd_to_mjd(jd) jd - 2400000.5 end
    def tjd_to_jd(tjd) tjd + 2440000.5 end
    def jd_to_tjd(jd) jd - 2440000.5 end

    def julian_leap? (y) y % 4 == 0 end
    def gregorian_leap? (y) y % 4 == 0 and y % 100 != 0 or y % 400 == 0 end

    alias_method :leap?, :gregorian_leap?

    def exist3? (y, m, d, sg=ITALY)
      if m < 0
	m += 13
      end
      if d < 0
	ljd = nil
	31.downto 1 do |ld|
	  break if ljd = exist3?(y, m, ld, sg)
	end
	x  = y * 12 + m
	ny = x / 12
	nm = x % 12 + 1
	d = jd_to_civil(civil_to_jd(ny, nm, 1, ns?(ljd, sg)) + d,
			ns?(ljd, sg))[-1]
      end
      jd = civil_to_jd(y, m, d, sg)
      if [y, m, d] == jd_to_civil(jd, sg)
	jd
      end
    end

    alias_method :exist?, :exist3?

    def new3(y=-4712, m=1, d=1, sg=ITALY)
      unless jd = exist3?(y, m, d, sg)
	fail ArgumentError, 'invalid date'
      end
      new(jd, sg)
    end

    def exist2? (y, d, sg=ITALY)
      if d < 0
	ljd = nil
	366.downto 1 do |ld|
	  break if ljd = exist2?(y, ld, sg)
	end
	ny = y + 1
	d = jd_to_ordinal(ordinal_to_jd(ny, 1, ns?(ljd, sg)) + d,
			  ns?(ljd, sg))[-1]
      end
      jd = ordinal_to_jd(y, d, sg)
      if [y, d] == jd_to_ordinal(jd, sg)
	jd
      end
    end

    def new2(y=-4712, d=1, sg=ITALY)
      unless jd = exist2?(y, d, sg)
	fail ArgumentError, 'invalid date'
      end
      new(jd, sg)
    end

    def today(sg=ITALY)
      new(civil_to_jd(*(Time.now.to_a[3..5].reverse << sg)), sg)
    end

  end

  def initialize(jd=0, sg=ITALY) @jd, @sg = jd, sg end

  def jd() @jd end

  def mjd
    def self.mjd() @mjd end
    @mjd = Date.jd_to_mjd(@jd)
  end

  def tjd
    def self.tjd() @tjd end
    @tjd = Date.jd_to_tjd(@jd)
  end

  def civil
    def self.year() @year end
    def self.mon() @mon end
    def self.month() @mon end
    def self.mday() @mday end
    def self.day() @mday end
    @year, @mon, @mday = Date.jd_to_civil(@jd, @sg)
  end

  private :civil

  def year
    civil
    @year
  end

  def yday
    def self.yday() @yday end
    @yday = Date.jd_to_ordinal(@jd, @sg)[-1]
    @yday
  end

  def mon
    civil
    @mon
  end

  alias_method :month, :mon

  def mday
    civil
    @mday
  end

  alias_method :day, :mday

  def wday
    def self.wday() @wday end
    @wday = (@jd + 1) % 7
  end

  def os? () Date.os?(@jd, @sg) end
  def ns? () Date.ns?(@jd, @sg) end

  def leap?
    def self.leap?() @leap_p end
    @leap_p = Date.jd_to_civil(Date.civil_to_jd(year, 3, 1, ns?) - 1,
			       ns?)[-1] == 29
  end

  def + (other)
    case other
    when Numeric; return Date.new(@jd + other, @sg)
    end
    fail TypeError, 'expected numeric'
  end

  def - (other)
    case other
    when Numeric; return Date.new(@jd - other, @sg)
    when Date;    return @jd - other.jd
    end
    fail TypeError, 'expected numeric or date'
  end

  def <=> (other)
    case other
    when Numeric; return @jd <=> other
    when Date;    return @jd <=> other.jd
    end
    fail TypeError, 'expected numeric or date'
  end

  def downto(min)
    @jd.downto(min.jd) do |jd|
      yield Date.new(jd, @sg)
    end
    self
  end

  def upto(max)
    @jd.upto(max.jd) do |jd|
      yield Date.new(jd, @sg)
    end
    self
  end

  def step(limit, step)
    @jd.step(limit.jd, step) do |jd|
      yield Date.new(jd, @sg)
    end
    self
  end

  def succ() self + 1 end

  alias_method :next, :succ

  def eql? (other) self == other end
  def hash() @jd end
  def inspect() format('#<Date: %s,%s>', @jd, @sg) end
  def to_s() format('%.4d-%02d-%02d', year, mon, mday) end

  def _dump(limit) Marshal.dump([@jd, @sg], -1) end
  def Date._load(str) Date.new(*Marshal.load(str)) end

end
