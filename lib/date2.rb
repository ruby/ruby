# date.rb: Written by Tadayoshi Funaba 1998
# $Id: date.rb,v 1.3 1998/03/08 09:43:54 tadf Exp $

class Date

  include Comparable

  MONTHNAMES = [ '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December' ]

  DAYNAMES = [ 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday' ]

  GREGORY = 2299161	# Oct 15, 1582
  ENGLAND = 2361222	# Sept 14, 1752

  def Date.civil_to_jd(y, m, d, gs = true)
    if m <= 2 then
      y -= 1
      m += 12
    end
    a = (y / 100).to_i
    b = (a / 4).to_i
    c = 2 - a + b
    e = (365.25 * (y + 4716)).to_i
    f = (30.6001 * (m + 1)).to_i
    jd = c + d + e + f - 1524
    unless
      (if gs.kind_of? Numeric then jd >= gs else gs end) then
      jd -= c
    end
    return jd
  end

  def Date.jd_to_civil(jd, gs = true)
    unless
      (if gs.kind_of? Numeric then jd >= gs else gs end) then
      a = jd
    else
      w = ((jd - 1867216.25) / 36524.25).to_i
      x = (w / 4).to_i
      a = jd + 1 + w - x
    end
    b = a + 1524
    c = ((b - 122.1) / 365.25).to_i
    d = (365.25 * c).to_i
    e = ((b - d) / 30.6001).to_i
    f = (30.6001 * e).to_i
    day = b - d - f
    if e <= 13 then
      m = e - 1
    else
      m = e - 13
    end
    if m <= 2 then
      y = c - 4715
    else
      y = c - 4716
    end
    return y, m, day
  end

  def Date.mjd_to_jd(mjd)
    mjd + 2400000.5
  end

  def Date.jd_to_mjd(jd)
    jd - 2400000.5
  end

  def Date.tjd_to_jd(tjd)
    tjd + 2440000.5
  end

  def Date.jd_to_tjd(jd)
    jd - 2440000.5
  end

  def initialize(jd = 0, gs = GREGORY)
    @jd = jd
    @gs = gs
  end

  def Date.new3(y = -4712, m = 1, d = 1, gs = GREGORY)
    jd = Date.civil_to_jd(y, m, d, gs)
    y2, m2, d2 = Date.jd_to_civil(jd, gs)
    unless y == y2 and m == m2 and d == d2 then
      raise ArgumentError, 'invalid date'
    end
    Date.new(jd, gs)
  end

  def Date.today(gs = GREGORY)
    Date.new3(*(Time.now.to_a[3..5].reverse << gs))
  end

  def jd
    @jd
  end

  def mjd
    Date.jd_to_mjd(@jd)
  end

  def tjd
    Date.jd_to_tjd(@jd)
  end

  def year
    Date.jd_to_civil(@jd, @gs)[0]
  end

  def yday
    gs = if @gs.kind_of? Numeric then @jd >= @gs else @gs end
    jd = Date.civil_to_jd(year - 1, 12, 31, gs)
    @jd - jd
  end

  def mon
    Date.jd_to_civil(@jd, @gs)[1]
  end

  def mday
    Date.jd_to_civil(@jd, @gs)[2]
  end

  def wday
    k = (@jd + 1) % 7
    k += 7 if k < 0
    k
  end

  def leap?
    gs = if @gs.kind_of? Numeric then @jd >= @gs else @gs end
    jd = Date.civil_to_jd(year, 2, 28, gs)
    Date.jd_to_civil(jd + 1, gs)[1] == 2
  end

  def + (other)
    if other.kind_of? Numeric then
      return Date.new(@jd + other, @gs)
    end
    raise TypeError, 'expected numeric'
  end

  def - (other)
    if other.kind_of? Numeric then
      return Date.new(@jd - other, @gs)
    elsif other.kind_of? Date then
      return @jd - other.jd
    end
    raise TypeError, 'expected numeric or date'
  end

  def <=> (other)
    if other.kind_of? Numeric then
      return @jd <=> other
    elsif other.kind_of? Date then
      return @jd <=> other.jd
    end
    raise TypeError, 'expected numeric or date'
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
    format('%04d-%02d-%02d', *Date.jd_to_civil(@jd, @gs))
  end

end
