# date.rb: Written by Tadayoshi Funaba 1998, 1999
# $Id: date.rb,v 1.7 1999/03/06 02:05:59 tadf Exp $

class Date

  include Comparable

  MONTHNAMES = [ nil, 'January', 'February', 'March',
    'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December' ]

  DAYNAMES = [ 'Sunday', 'Monday', 'Tuesday',
    'Wednesday', 'Thursday', 'Friday', 'Saturday' ]

  ITALY   = 2299161 # Oct 15, 1582
  ENGLAND = 2361222 # Sept 14, 1752

  class << self

    def civil_to_jd(y, m, d, gs=true)
      if m <= 2
	y -= 1
	m += 12
      end
      a = (y / 100).to_i
      b = 2 - a + (a / 4).to_i
      jd = (365.25 * (y + 4716)).to_i +
	(30.6001 * (m + 1)).to_i +
	d + b - 1524
      unless
	(if gs.kind_of? Numeric then jd >= gs else gs end)
	jd -= b
      end
      jd
    end

    def jd_to_civil(jd, gs=true)
      unless
	(if gs.kind_of? Numeric then jd >= gs else gs end)
	a = jd
      else
	x = ((jd - 1867216.25) / 36524.25).to_i
	a = jd + 1 + x - (x / 4).to_i
      end
      b = a + 1524
      c = ((b - 122.1) / 365.25).to_i
      d = (365.25 * c).to_i
      e = ((b - d) / 30.6001).to_i
      dom = b - d - (30.6001 * e).to_i
      if e <= 13
	m = e - 1
	y = c - 4716
      else
	m = e - 13
	y = c - 4715
      end
      return y, m, dom
    end

    def ordinal_to_jd(y, d, gs=true)
      civil_to_jd(y, 1, d, gs)
    end

    def jd_to_ordinal(jd, gs=true)
      y, *_ = jd_to_civil(jd, gs)
      ns = if gs.kind_of? Numeric then jd >= gs else gs end
      pl = civil_to_jd(y - 1, 12, 31, ns)
      doy = jd - pl
      return y, doy
    end

    def mjd_to_jd(mjd)
      mjd + 2400000.5
    end

    def jd_to_mjd(jd)
      jd - 2400000.5
    end

    def tjd_to_jd(tjd)
      tjd + 2440000.5
    end

    def jd_to_tjd(jd)
      jd - 2440000.5
    end

    def julian_leap? (y)
      y % 4 == 0
    end

    def gregorian_leap? (y)
      y % 4 == 0 and y % 100 != 0 or y % 400 == 0
    end

    alias_method :leap?, :gregorian_leap?

    def exist3? (y, m, d, gs=true)
      jd = civil_to_jd(y, m, d, gs)
      if [y, m, d] == jd_to_civil(jd, gs)
	jd
      end
    end

    alias_method :exist?, :exist3?

    def new3(y=-4712, m=1, d=1, gs=ITALY)
      unless jd = exist3?(y, m, d, gs)
	fail ArgumentError, 'invalid date'
      end
      new(jd, gs)
    end

    def exist2? (y, d, gs=true)
      jd = ordinal_to_jd(y, d, gs)
      if [y, d] == jd_to_ordinal(jd, gs)
	jd
      end
    end

    def new2(y=-4712, d=1, gs=ITALY)
      unless jd = exist2?(y, d, gs)
	fail ArgumentError, 'invalid date'
      end
      new(jd, gs)
    end

    def today(gs=ITALY)
      new(civil_to_jd(*(Time.now.to_a[3..5].reverse << gs)), gs)
    end

  end

  def initialize(jd=0, gs=ITALY)
    @jd, @gs = jd, gs
  end

  def jd
    @jd
  end

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
    def self.mday() @mday end
    @year, @mon, @mday = Date.jd_to_civil(@jd, @gs)
  end

  private :civil

  def year
    civil
    @year
  end

  def yday
    def self.yday() @yday end
    _, @yday = Date.jd_to_ordinal(@jd, @gs)
    @yday
  end

  def mon
    civil
    @mon
  end

  def mday
    civil
    @mday
  end

  def wday
    def self.wday() @wday end
    @wday = (@jd + 1) % 7
  end

  def leap?
    def self.leap?() @leap_p end
    ns = if @gs.kind_of? Numeric then @jd >= @gs else @gs end
    jd = Date.civil_to_jd(year, 2, 28, ns)
    @leap_p = Date.jd_to_civil(jd + 1, ns)[1] == 2
  end

  def + (other)
    case other
    when Numeric; return Date.new(@jd + other, @gs)
    end
    fail TypeError, 'expected numeric'
  end

  def - (other)
    case other
    when Numeric; return Date.new(@jd - other, @gs)
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
      yield Date.new(jd, @gs)
    end
  end

  def upto(max)
    @jd.upto(max.jd) do |jd|
      yield Date.new(jd, @gs)
    end
  end

  def step(max, step)
    @jd.step(max.jd, step) do |jd|
      yield Date.new(jd, @gs)
    end
  end

  def eql? (other)
    self == other
  end

  def hash
    @jd
  end

  def to_s
    format('%04d-%02d-%02d', year, mon, mday)
  end

  def _dump(limit)
    Marshal.dump([@jd, @gs], -1)
  end

  def Date._load(str)
    Date.new(*Marshal.load(str))
  end

end
