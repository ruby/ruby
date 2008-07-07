# format.rb: Written by Tadayoshi Funaba 1999-2007
# $Id: format.rb,v 2.30 2007-01-07 09:16:24+09 tadf Exp $

require 'rational'

class Date

  module Format # :nodoc:

    MONTHS = {
      'january'  => 1, 'february' => 2, 'march'    => 3, 'april'    => 4,
      'may'      => 5, 'june'     => 6, 'july'     => 7, 'august'   => 8,
      'september'=> 9, 'october'  =>10, 'november' =>11, 'december' =>12
    }

    DAYS = {
      'sunday'   => 0, 'monday'   => 1, 'tuesday'  => 2, 'wednesday'=> 3,
      'thursday' => 4, 'friday'   => 5, 'saturday' => 6
    }

    ABBR_MONTHS = {
      'jan'      => 1, 'feb'      => 2, 'mar'      => 3, 'apr'      => 4,
      'may'      => 5, 'jun'      => 6, 'jul'      => 7, 'aug'      => 8,
      'sep'      => 9, 'oct'      =>10, 'nov'      =>11, 'dec'      =>12
    }

    ABBR_DAYS = {
      'sun'      => 0, 'mon'      => 1, 'tue'      => 2, 'wed'      => 3,
      'thu'      => 4, 'fri'      => 5, 'sat'      => 6
    }

    ZONES = {
      'ut'  =>  0*3600, 'gmt' =>  0*3600, 'est' => -5*3600, 'edt' => -4*3600,
      'cst' => -6*3600, 'cdt' => -5*3600, 'mst' => -7*3600, 'mdt' => -6*3600,
      'pst' => -8*3600, 'pdt' => -7*3600,
      'a'   =>  1*3600, 'b'   =>  2*3600, 'c'   =>  3*3600, 'd'   =>  4*3600,
      'e'   =>  5*3600, 'f'   =>  6*3600, 'g'   =>  7*3600, 'h'   =>  8*3600,
      'i'   =>  9*3600, 'k'   => 10*3600, 'l'   => 11*3600, 'm'   => 12*3600,
      'n'   => -1*3600, 'o'   => -2*3600, 'p'   => -3*3600, 'q'   => -4*3600,
      'r'   => -5*3600, 's'   => -6*3600, 't'   => -7*3600, 'u'   => -8*3600,
      'v'   => -9*3600, 'w'   =>-10*3600, 'x'   =>-11*3600, 'y'   =>-12*3600,
      'z'   =>  0*3600,
      'utc' =>  0*3600, 'wet' =>  0*3600, 'bst' =>  1*3600, 'wat' => -1*3600,
      'at'  => -2*3600, 'ast' => -4*3600, 'adt' => -3*3600, 'yst' => -9*3600,
      'ydt' => -8*3600, 'hst' =>-10*3600, 'hdt' => -9*3600, 'cat' =>-10*3600,
      'ahst'=>-10*3600, 'nt'  =>-11*3600, 'idlw'=>-12*3600, 'cet' =>  1*3600,
      'met' =>  1*3600, 'mewt'=>  1*3600, 'mest'=>  2*3600, 'mesz'=>  2*3600,
      'swt' =>  1*3600, 'sst' =>  2*3600, 'fwt' =>  1*3600, 'fst' =>  2*3600,
      'eet' =>  2*3600, 'bt'  =>  3*3600, 'zp4' =>  4*3600, 'zp5' =>  5*3600,
      'zp6' =>  6*3600, 'wast'=>  7*3600, 'wadt'=>  8*3600, 'cct' =>  8*3600,
      'jst' =>  9*3600, 'east'=> 10*3600, 'eadt'=> 11*3600, 'gst' => 10*3600,
      'nzt' => 12*3600, 'nzst'=> 12*3600, 'nzdt'=> 13*3600, 'idle'=> 12*3600,

      'afghanistan'           =>   16200, 'alaskan'               =>  -32400,
      'arab'                  =>   10800, 'arabian'               =>   14400,
      'arabic'                =>   10800, 'atlantic'              =>  -14400,
      'aus central'           =>   34200, 'aus eastern'           =>   36000,
      'azores'                =>   -3600, 'canada central'        =>  -21600,
      'cape verde'            =>   -3600, 'caucasus'              =>   14400,
      'cen. australia'        =>   34200, 'central america'       =>  -21600,
      'central asia'          =>   21600, 'central europe'        =>    3600,
      'central european'      =>    3600, 'central pacific'       =>   39600,
      'central'               =>  -21600, 'china'                 =>   28800,
      'dateline'              =>  -43200, 'e. africa'             =>   10800,
      'e. australia'          =>   36000, 'e. europe'             =>    7200,
      'e. south america'      =>  -10800, 'eastern'               =>  -18000,
      'egypt'                 =>    7200, 'ekaterinburg'          =>   18000,
      'fiji'                  =>   43200, 'fle'                   =>    7200,
      'greenland'             =>  -10800, 'greenwich'             =>       0,
      'gtb'                   =>    7200, 'hawaiian'              =>  -36000,
      'india'                 =>   19800, 'iran'                  =>   12600,
      'jerusalem'             =>    7200, 'korea'                 =>   32400,
      'mexico'                =>  -21600, 'mid-atlantic'          =>   -7200,
      'mountain'              =>  -25200, 'myanmar'               =>   23400,
      'n. central asia'       =>   21600, 'nepal'                 =>   20700,
      'new zealand'           =>   43200, 'newfoundland'          =>  -12600,
      'north asia east'       =>   28800, 'north asia'            =>   25200,
      'pacific sa'            =>  -14400, 'pacific'               =>  -28800,
      'romance'               =>    3600, 'russian'               =>   10800,
      'sa eastern'            =>  -10800, 'sa pacific'            =>  -18000,
      'sa western'            =>  -14400, 'samoa'                 =>  -39600,
      'se asia'               =>   25200, 'malay peninsula'       =>   28800,
      'south africa'          =>    7200, 'sri lanka'             =>   21600,
      'taipei'                =>   28800, 'tasmania'              =>   36000,
      'tokyo'                 =>   32400, 'tonga'                 =>   46800,
      'us eastern'            =>  -18000, 'us mountain'           =>  -25200,
      'vladivostok'           =>   36000, 'w. australia'          =>   28800,
      'w. central africa'     =>    3600, 'w. europe'             =>    3600,
      'west asia'             =>   18000, 'west pacific'          =>   36000,
      'yakutsk'               =>   32400
    }

    [MONTHS, DAYS, ABBR_MONTHS, ABBR_DAYS, ZONES].each do |x|
      x.freeze
    end

    class Bag # :nodoc:

      def initialize
	@elem = {}
      end

      def method_missing(t, *args, &block)
	t = t.to_s
	set = t.chomp!('=')
	t = t.intern
	if set
	  @elem[t] = args[0]
	else
	  @elem[t]
	end
      end

      def to_hash
	@elem.reject{|k, v| /\A_/ =~ k.to_s || v.nil?}
      end

    end

  end

  def emit(e, f) # :nodoc:
    case e
    when Numeric
      sign = %w(+ + -)[e <=> 0]
      e = e.abs
    end

    s = e.to_s

    if f[:s] && f[:p] == '0'
      f[:w] -= 1
    end

    if f[:s] && f[:p] == "\s"
      s[0,0] = sign
    end

    if f[:p] != '-'
      s = s.rjust(f[:w], f[:p])
    end

    if f[:s] && f[:p] != "\s"
      s[0,0] = sign
    end

    s = s.upcase if f[:u]
    s = s.downcase if f[:d]
    s
  end

  def emit_w(e, w, f) # :nodoc:
    f[:w] = [f[:w], w].compact.max
    emit(e, f)
  end

  def emit_n(e, w, f) # :nodoc:
    f[:p] ||= '0'
    emit_w(e, w, f)
  end

  def emit_sn(e, w, f) # :nodoc:
    if e < 0
      w += 1
      f[:s] = true
    end
    emit_n(e, w, f)
  end

  def emit_z(e, w, f) # :nodoc:
    w += 1
    f[:s] = true
    emit_n(e, w, f)
  end

  def emit_a(e, w, f) # :nodoc:
    f[:p] ||= "\s"
    emit_w(e, w, f)
  end

  def emit_ad(e, w, f) # :nodoc:
    if f[:x]
      f[:u] = true
      f[:d] = false
    end
    emit_a(e, w, f)
  end

  def emit_au(e, w, f) # :nodoc:
    if f[:x]
      f[:u] = false
      f[:d] = true
    end
    emit_a(e, w, f)
  end

  private :emit, :emit_w, :emit_n, :emit_sn, :emit_z,
	  :emit_a, :emit_ad, :emit_au

  def strftime(fmt='%F')
    fmt.gsub(/%([-_0^#]+)?(\d+)?[EO]?(:{1,3}z|.)/m) do |m|
      f = {}
      s, w, c = $1, $2, $3
      if s
	s.scan(/./) do |k|
	  case k
	  when '-'; f[:p] = '-'
	  when '_'; f[:p] = "\s"
	  when '0'; f[:p] = '0'
	  when '^'; f[:u] = true
	  when '#'; f[:x] = true
	  end
	end
      end
      if w
	f[:w] = w.to_i
      end
      case c
      when 'A'; emit_ad(DAYNAMES[wday], 0, f)
      when 'a'; emit_ad(ABBR_DAYNAMES[wday], 0, f)
      when 'B'; emit_ad(MONTHNAMES[mon], 0, f)
      when 'b'; emit_ad(ABBR_MONTHNAMES[mon], 0, f)
      when 'C'; emit_sn((year / 100).floor, 2, f)
      when 'c'; emit_a(strftime('%a %b %e %H:%M:%S %Y'), 0, f)
      when 'D'; emit_a(strftime('%m/%d/%y'), 0, f)
      when 'd'; emit_n(mday, 2, f)
      when 'e'; emit_a(mday, 2, f)
      when 'F'
	if m == '%F'
	  format('%.4d-%02d-%02d', year, mon, mday) # 4p
	else
	  emit_a(strftime('%Y-%m-%d'), 0, f)
	end
      when 'G'; emit_sn(cwyear, 4, f)
      when 'g'; emit_n(cwyear % 100, 2, f)
      when 'H'; emit_n(hour, 2, f)
      when 'h'; emit_ad(strftime('%b'), 0, f)
      when 'I'; emit_n((hour % 12).nonzero? || 12, 2, f)
      when 'j'; emit_n(yday, 3, f)
      when 'k'; emit_a(hour, 2, f)
      when 'L'
	emit_n((sec_fraction / (1.to_r/86400/(10**3))).round, 3, f)
      when 'l'; emit_a((hour % 12).nonzero? || 12, 2, f)
      when 'M'; emit_n(min, 2, f)
      when 'm'; emit_n(mon, 2, f)
      when 'N'
	emit_n((sec_fraction / (1.to_r/86400/(10**9))).round, 9, f)
      when 'n'; "\n"
      when 'P'; emit_ad(strftime('%p').downcase, 0, f)
      when 'p'; emit_au(if hour < 12 then 'AM' else 'PM' end, 0, f)
      when 'Q'
	d = ajd - self.class.jd_to_ajd(self.class::UNIXEPOCH, 0)
	s = (d * 86400*10**3).to_i
	emit_sn(s, 1, f)
      when 'R'; emit_a(strftime('%H:%M'), 0, f)
      when 'r'; emit_a(strftime('%I:%M:%S %p'), 0, f)
      when 'S'; emit_n(sec, 2, f)
      when 's'
	d = ajd - self.class.jd_to_ajd(self.class::UNIXEPOCH, 0)
	s = (d * 86400).to_i
	emit_sn(s, 1, f)
      when 'T'
	if m == '%T'
	  format('%02d:%02d:%02d', hour, min, sec) # 4p
	else
	  emit_a(strftime('%H:%M:%S'), 0, f)
	end
      when 't'; "\t"
      when 'U', 'W'
	emit_n(if c == 'U' then wnum0 else wnum1 end, 2, f)
      when 'u'; emit_n(cwday, 1, f)
      when 'V'; emit_n(cweek, 2, f)
      when 'v'; emit_a(strftime('%e-%b-%Y'), 0, f)
      when 'w'; emit_n(wday, 1, f)
      when 'X'; emit_a(strftime('%H:%M:%S'), 0, f)
      when 'x'; emit_a(strftime('%m/%d/%y'), 0, f)
      when 'Y'; emit_sn(year, 4, f)
      when 'y'; emit_n(year % 100, 2, f)
      when 'Z'; emit_au(strftime('%:z'), 0, f)
      when /\A(:{0,3})z/
	t = $1.size
	sign = if offset < 0 then -1 else +1 end
	fr = offset.abs
	hh, fr = fr.divmod(1.to_r/24)
	mm, fr = fr.divmod(1.to_r/1440)
	ss, fr = fr.divmod(1.to_r/86400)
	if t == 3
	  if    ss.nonzero? then t =  2
	  elsif mm.nonzero? then t =  1
	  else                   t = -1
	  end
	end
	case t
	when -1
	  tail = []
	  sep = ''
	when 0
	  f[:w] -= 2 if f[:w]
	  tail = ['%02d' % mm]
	  sep = ''
	when 1
	  f[:w] -= 3 if f[:w]
	  tail = ['%02d' % mm]
	  sep = ':'
	when 2
	  f[:w] -= 6 if f[:w]
	  tail = ['%02d' % mm, '%02d' % ss]
	  sep = ':'
	end
	([emit_z(sign * hh, 2, f)] + tail).join(sep)
      when '%'; emit_a('%', 0, f)
      when '+'; emit_a(strftime('%a %b %e %H:%M:%S %Z %Y'), 0, f)
      when '1'
	if $VERBOSE
	  warn("warning: strftime: %1 is deprecated; forget this")
	end
	emit_n(jd, 1, f)
      when '2'
	if $VERBOSE
	  warn("warning: strftime: %2 is deprecated; use '%Y-%j'")
	end
	emit_a(strftime('%Y-%j'), 0, f)
      when '3'
	if $VERBOSE
	  warn("warning: strftime: %3 is deprecated; use '%F'")
	end
	emit_a(strftime('%F'), 0, f)
      else
	c
      end
    end
  end

# alias_method :format, :strftime

  def asctime() strftime('%c') end

  alias_method :ctime, :asctime

=begin
  def iso8601() strftime('%F') end

  def rfc3339() iso8601 end

  def rfc2822() strftime('%a, %-d %b %Y %T %z') end

  alias_method :rfc822, :rfc2822

  def jisx0301
    if jd < 2405160
      iso8601
    else
      case jd
      when 2405160...2419614
	g = 'M%02d' % (year - 1867)
      when 2419614...2424875
	g = 'T%02d' % (year - 1911)
      when 2424875...2447535
	g = 'S%02d' % (year - 1925)
      else
	g = 'H%02d' % (year - 1988)
      end
      g + strftime('.%m.%d')
    end
  end

  def beat(n=0)
    i, f = (new_offset(1.to_r/24).day_fraction * 1000).divmod(1)
    ('@%03d' % i) +
      if n < 1
	''
      else
	'.%0*d' % [n, (f / (1.to_r/(10**n))).round]
      end
  end
=end

  def self.num_pattern? (s) # :nodoc:
    /\A%[EO]?[CDdeFGgHIjkLlMmNQRrSsTUuVvWwXxYy\d]/ =~ s || /\A\d/ =~ s
  end

  private_class_method :num_pattern?

  def self._strptime_i(str, fmt, e) # :nodoc:
    fmt.scan(/%[EO]?(:{1,3}z|.)|(.)/m) do |s, c|
      if s
	case s
	when 'A', 'a'
	  return unless str.sub!(/\A(#{Format::DAYS.keys.join('|')})/io, '') ||
			str.sub!(/\A(#{Format::ABBR_DAYS.keys.join('|')})/io, '')
	  val = Format::DAYS[$1.downcase] || Format::ABBR_DAYS[$1.downcase]
	  return unless val
	  e.wday = val
	when 'B', 'b', 'h'
	  return unless str.sub!(/\A(#{Format::MONTHS.keys.join('|')})/io, '') ||
			str.sub!(/\A(#{Format::ABBR_MONTHS.keys.join('|')})/io, '')
	  val = Format::MONTHS[$1.downcase] || Format::ABBR_MONTHS[$1.downcase]
	  return unless val
	  e.mon = val
	when 'C'
	  return unless str.sub!(if num_pattern?($')
				 then /\A([-+]?\d{1,2})/
				 else /\A([-+]?\d{1,})/
				 end, '')
	  val = $1.to_i
	  e._cent = val
	when 'c'
	  return unless _strptime_i(str, '%a %b %e %H:%M:%S %Y', e)
	when 'D'
	  return unless _strptime_i(str, '%m/%d/%y', e)
	when 'd', 'e'
	  return unless str.sub!(/\A( \d|\d{1,2})/, '')
	  val = $1.to_i
	  return unless (1..31) === val
	  e.mday = val
	when 'F'
	  return unless _strptime_i(str, '%Y-%m-%d', e)
	when 'G'
	  return unless str.sub!(if num_pattern?($')
				 then /\A([-+]?\d{1,4})/
				 else /\A([-+]?\d{1,})/
				 end, '')
	  val = $1.to_i
	  e.cwyear = val
	when 'g'
	  return unless str.sub!(/\A(\d{1,2})/, '')
	  val = $1.to_i
	  return unless (0..99) === val
	  e.cwyear = val
	  e._cent ||= if val >= 69 then 19 else 20 end
	when 'H', 'k'
	  return unless str.sub!(/\A( \d|\d{1,2})/, '')
	  val = $1.to_i
	  return unless (0..24) === val
	  e.hour = val
	when 'I', 'l'
	  return unless str.sub!(/\A( \d|\d{1,2})/, '')
	  val = $1.to_i
	  return unless (1..12) === val
	  e.hour = val
	when 'j'
	  return unless str.sub!(/\A(\d{1,3})/, '')
	  val = $1.to_i
	  return unless (1..366) === val
	  e.yday = val
	when 'L'
	  return unless str.sub!(if num_pattern?($')
				 then /\A([-+]?\d{1,3})/
				 else /\A([-+]?\d{1,})/
				 end, '')
#	  val = $1.to_i.to_r / (10**3)
	  val = $1.to_i.to_r / (10**$1.size)
	  e.sec_fraction = val
	when 'M'
	  return unless str.sub!(/\A(\d{1,2})/, '')
	  val = $1.to_i
	  return unless (0..59) === val
	  e.min = val
	when 'm'
	  return unless str.sub!(/\A(\d{1,2})/, '')
	  val = $1.to_i
	  return unless (1..12) === val
	  e.mon = val
	when 'N'
	  return unless str.sub!(if num_pattern?($')
				 then /\A([-+]?\d{1,9})/
				 else /\A([-+]?\d{1,})/
				 end, '')
#	  val = $1.to_i.to_r / (10**9)
	  val = $1.to_i.to_r / (10**$1.size)
	  e.sec_fraction = val
	when 'n', 't'
	  return unless _strptime_i(str, "\s", e)
	when 'P', 'p'
	  return unless str.sub!(/\A([ap])(?:m\b|\.m\.)/i, '')
	  e._merid = if $1.downcase == 'a' then 0 else 12 end
	when 'Q'
	  return unless str.sub!(/\A(-?\d{1,})/, '')
	  val = $1.to_i.to_r / 10**3
	  e.seconds = val
	when 'R'
	  return unless _strptime_i(str, '%H:%M', e)
	when 'r'
	  return unless _strptime_i(str, '%I:%M:%S %p', e)
	when 'S'
	  return unless str.sub!(/\A(\d{1,2})/, '')
	  val = $1.to_i
	  return unless (0..60) === val
	  e.sec = val
	when 's'
	  return unless str.sub!(/\A(-?\d{1,})/, '')
	  val = $1.to_i
	  e.seconds = val
	when 'T'
	  return unless _strptime_i(str, '%H:%M:%S', e)
	when 'U', 'W'
	  return unless str.sub!(/\A(\d{1,2})/, '')
	  val = $1.to_i
	  return unless (0..53) === val
	  e.__send__(if s == 'U' then :wnum0= else :wnum1= end, val)
	when 'u'
	  return unless str.sub!(/\A(\d{1})/, '')
	  val = $1.to_i
	  return unless (1..7) === val
	  e.cwday = val
	when 'V'
	  return unless str.sub!(/\A(\d{1,2})/, '')
	  val = $1.to_i
	  return unless (1..53) === val
	  e.cweek = val
	when 'v'
	  return unless _strptime_i(str, '%e-%b-%Y', e)
	when 'w'
	  return unless str.sub!(/\A(\d{1})/, '')
	  val = $1.to_i
	  return unless (0..6) === val
	  e.wday = val
	when 'X'
	  return unless _strptime_i(str, '%H:%M:%S', e)
	when 'x'
	  return unless _strptime_i(str, '%m/%d/%y', e)
	when 'Y'
	  return unless str.sub!(if num_pattern?($')
				 then /\A([-+]?\d{1,4})/
				 else /\A([-+]?\d{1,})/
				 end, '')
	  val = $1.to_i
	  e.year = val
	when 'y'
	  return unless str.sub!(/\A(\d{1,2})/, '')
	  val = $1.to_i
	  return unless (0..99) === val
	  e.year = val
	  e._cent ||= if val >= 69 then 19 else 20 end
	when 'Z', /\A:{0,3}z/
	  return unless str.sub!(/\A((?:gmt|utc?)?[-+]\d+(?:[,.:]\d+(?::\d+)?)?
				    |[a-z.\s]+(?:standard|daylight)\s+time\b
				    |[a-z]+(?:\s+dst)?\b
				    )/ix, '')
	  val = $1
	  e.zone = val
	  offset = zone_to_diff(val)
	  e.offset = offset
	when '%'
	  return unless str.sub!(/\A%/, '')
	when '+'
	  return unless _strptime_i(str, '%a %b %e %H:%M:%S %Z %Y', e)
	when '1'
	  if $VERBOSE
	    warn("warning: strptime: %1 is deprecated; forget this")
	  end
	  return unless str.sub!(/\A(\d+)/, '')
	  val = $1.to_i
	  e.jd = val
	when '2'
	  if $VERBOSE
	    warn("warning: strptime: %2 is deprecated; use '%Y-%j'")
	  end
	  return unless _strptime_i(str, '%Y-%j', e)
	when '3'
	  if $VERBOSE
	    warn("warning: strptime: %3 is deprecated; use '%F'")
	  end
	  return unless _strptime_i(str, '%F', e)
	else
	  return unless str.sub!(Regexp.new('\\A' + Regexp.quote(s)), '')
	end
      else
	case c
	when /\A[\s\v]/
	  str.sub!(/\A[\s\v]+/, '')
	else
	  return unless str.sub!(Regexp.new('\\A' + Regexp.quote(c)), '')
	end
      end
    end
  end

  private_class_method :_strptime_i

  def self._strptime(str, fmt='%F')
    e = Format::Bag.new
    return unless _strptime_i(str.dup, fmt, e)

    if e._cent
      if e.cwyear
	e.cwyear += e._cent * 100
      end
      if e.year
	e.  year += e._cent * 100
      end
    end

    if e._merid
      if e.hour
	e.hour %= 12
	e.hour += e._merid
      end
    end

    e.to_hash
  end

  def self.s3e(e, y, m, d, bc=false)
    unless String === m
      m = m.to_s
    end

    if y == nil
      if d && d.size > 2
	y = d
	d = nil
      end
      if d && d[0,1] == "'"
	y = d
	d = nil
      end
    end

    if y
      y.scan(/(\d+)(.+)?/)
      if $2
	y, d = d, $1
      end
    end

    if m
      if m[0,1] == "'" || m.size > 2
	y, m, d = m, d, y # us -> be
      end
    end

    if d
      if d[0,1] == "'" || d.size > 2
	y, d = d, y
      end
    end

    if y
      y =~ /([-+])?(\d+)/
      if $1 || $2.size > 2
	c = false
      end
      iy = $&.to_i
      if bc
	iy = -iy + 1
      end
      e.year = iy
    end

    if m
      m =~ /\d+/
      e.mon = $&.to_i
    end

    if d
      d =~ /\d+/
      e.mday = $&.to_i
    end

    if c != nil
      e._comp = c
    end

  end

  private_class_method :s3e

  def self._parse_day(str, e) # :nodoc:
    if str.sub!(/\b(#{Format::ABBR_DAYS.keys.join('|')})[^-\d\s]*/ino, ' ')
      e.wday = Format::ABBR_DAYS[$1.downcase]
      true
=begin
    elsif str.sub!(/\b(?!\dth)(su|mo|tu|we|th|fr|sa)\b/in, ' ')
      e.wday = %w(su mo tu we th fr sa).index($1.downcase)
      true
=end
    end
  end

  def self._parse_time(str, e) # :nodoc:
    if str.sub!(
		/(
		   (?:
		     \d+\s*:\s*\d+
		     (?:
		       \s*:\s*\d+(?:[,.]\d*)?
		     )?
		   |
		     \d+\s*h(?:\s*\d+m?(?:\s*\d+s?)?)?
		   )
		   (?:
		     \s*
		     [ap](?:m\b|\.m\.)
		   )?
		 |
		   \d+\s*[ap](?:m\b|\.m\.)
		 )
		 (?:
		   \s*
		   (
		     (?:gmt|utc?)?[-+]\d+(?:[,.:]\d+(?::\d+)?)?
		   |
		     [a-z.\s]+(?:standard|daylight)\stime\b
		   |
		     [a-z]+(?:\sdst)?\b
		   )
		 )?
		/inx,
		' ')

      t = $1
      e.zone = $2 if $2

      t =~ /\A(\d+)h?
	      (?:\s*:?\s*(\d+)m?
		(?:
		  \s*:?\s*(\d+)(?:[,.](\d+))?s?
		)?
	      )?
	    (?:\s*([ap])(?:m\b|\.m\.))?/inx

      e.hour = $1.to_i
      e.min = $2.to_i if $2
      e.sec = $3.to_i if $3
      e.sec_fraction = $4.to_i.to_r / (10**$4.size) if $4

      if $5
	e.hour %= 12
	if $5.downcase == 'p'
	  e.hour += 12
	end
      end
      true
    end
  end

  def self._parse_beat(str, e) # :nodoc:
    if str.sub!(/@\s*(\d+)(?:[,.](\d*))?/, ' ')
      beat = $1.to_i.to_r
      beat += $2.to_i.to_r / (10**$2.size) if $2
      secs = beat.to_r / 1000
      h, min, s, fr = self.day_fraction_to_time(secs)
      e.hour = h
      e.min = min
      e.sec = s
      e.sec_fraction = fr * 86400
      e.zone = '+01:00'
      true
    end
  end

  def self._parse_eu(str, e) # :nodoc:
    if str.sub!(
		/'?(\d+)[^-\d\s]*
		 \s*
		 (#{Format::ABBR_MONTHS.keys.join('|')})[^-\d\s']*
		 (?:
		   \s*
		   (c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|a(?:d|\.d\.)|b(?:c|\.c\.))?
		   \s*
		   ('?-?\d+(?:(?:st|nd|rd|th)\b)?)
		 )?
		/inox,
		' ') # '
      s3e(e, $4, Format::ABBR_MONTHS[$2.downcase], $1,
	  $3 && $3[0,1].downcase == 'b')
      true
    end
  end

  def self._parse_us(str, e) # :nodoc:
    if str.sub!(
		/\b(#{Format::ABBR_MONTHS.keys.join('|')})[^-\d\s']*
		 \s*
		 ('?\d+)[^-\d\s']*
		 (?:
		   \s*
		   (c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|a(?:d|\.d\.)|b(?:c|\.c\.))?
		   \s*
		   ('?-?\d+)
		 )?
		/inox,
		' ') # '
      s3e(e, $4, Format::ABBR_MONTHS[$1.downcase], $2,
	  $3 && $3[0,1].downcase == 'b')
      true
    end
  end

  def self._parse_iso(str, e) # :nodoc:
    if str.sub!(/('?[-+]?\d+)-(\d+)-('?-?\d+)/n, ' ')
      s3e(e, $1, $2, $3)
      true
    end
  end

  def self._parse_iso2(str, e) # :nodoc:
    if str.sub!(/\b(\d{2}|\d{4})?-?w(\d{2})(?:-?(\d+))?/in, ' ')
      e.cwyear = $1.to_i if $1
      e.cweek = $2.to_i
      e.cwday = $3.to_i if $3
      true
    elsif str.sub!(/--(\d{2})-(\d{2})\b/n, ' ')
      e.mon = $1.to_i
      e.mday = $2.to_i
      true
    elsif str.sub!(/\b(\d{2}|\d{4})-(\d{2,3})\b/n, ' ')
      e.year = $1.to_i
      if $2.size < 3
	e.mon = $2.to_i
      else
	e.yday = $2.to_i
      end
      true
    end
  end

  def self._parse_jis(str, e) # :nodoc:
    if str.sub!(/\b([MTSH])(\d+)\.(\d+)\.(\d+)/in, ' ')
      era = { 'm'=>1867,
	      't'=>1911,
	      's'=>1925,
	      'h'=>1988
	  }[$1.downcase]
      e.year = $2.to_i + era
      e.mon = $3.to_i
      e.mday = $4.to_i
      true
    end
  end

  def self._parse_vms(str, e) # :nodoc:
    if str.sub!(/('?-?\d+)-(#{Format::ABBR_MONTHS.keys.join('|')})[^-]*
		-('?-?\d+)/inox, ' ')
      s3e(e, $3, Format::ABBR_MONTHS[$2.downcase], $1)
      true
    elsif str.sub!(/\b(#{Format::ABBR_MONTHS.keys.join('|')})[^-]*
		-('?-?\d+)(?:-('?-?\d+))?/inox, ' ')
      s3e(e, $3, Format::ABBR_MONTHS[$1.downcase], $2)
      true
    end
  end

  def self._parse_sla_ja(str, e) # :nodoc:
    if str.sub!(%r|('?-?\d+)[/.]\s*('?\d+)(?:[^\d]\s*('?-?\d+))?|n, ' ') # '
      s3e(e, $1, $2, $3)
      true
    end
  end

  def self._parse_sla_eu(str, e) # :nodoc:
    if str.sub!(%r|('?-?\d+)[/.]\s*('?\d+)(?:[^\d]\s*('?-?\d+))?|n, ' ') # '
      s3e(e, $3, $2, $1)
      true
    end
  end

  def self._parse_sla_us(str, e) # :nodoc:
    if str.sub!(%r|('?-?\d+)[/.]\s*('?\d+)(?:[^\d]\s*('?-?\d+))?|n, ' ') # '
      s3e(e, $3, $1, $2)
      true
    end
  end

  def self._parse_year(str, e) # :nodoc:
    if str.sub!(/'(\d+)\b/in, ' ')
      e.year = $1.to_i
      true
    end
  end

  def self._parse_mon(str, e) # :nodoc:
    if str.sub!(/\b(#{Format::ABBR_MONTHS.keys.join('|')})\S*/ino, ' ')
      e.mon = Format::ABBR_MONTHS[$1.downcase]
      true
    end
  end

  def self._parse_mday(str, e) # :nodoc:
    if str.sub!(/(\d+)(st|nd|rd|th)\b/in, ' ')
      e.mday = $1.to_i
      true
    end
  end

  def self._parse_ddd(str, e) # :nodoc:
    if str.sub!(
		/([-+]?)(\d{2,14})
		  (?:
		    \s*
		    T?
		    \s*
		    (\d{2,6})(?:[,.](\d*))?
		  )?
		  (?:
		    \s*
		    (
		      Z
		    |
		      [-+]\d{1,4}
		    )
		    \b
		  )?
		/inx,
		' ')
      case $2.size
      when 2
	e.mday = $2[ 0, 2].to_i
      when 4
	e.mon  = $2[ 0, 2].to_i
	e.mday = $2[ 2, 2].to_i
      when 6
	e.year = ($1 + $2[ 0, 2]).to_i
	e.mon  = $2[ 2, 2].to_i
	e.mday = $2[ 4, 2].to_i
      when 8, 10, 12, 14
	e.year = ($1 + $2[ 0, 4]).to_i
	e.mon  = $2[ 4, 2].to_i
	e.mday = $2[ 6, 2].to_i
	e.hour = $2[ 8, 2].to_i if $2.size >= 10
	e.min  = $2[10, 2].to_i if $2.size >= 12
	e.sec  = $2[12, 2].to_i if $2.size >= 14
	e._comp = false
      when 3
	e.yday = $2[ 0, 3].to_i
      when 5
	e.year = ($1 + $2[ 0, 2]).to_i
	e.yday = $2[ 2, 3].to_i
      when 7
	e.year = ($1 + $2[ 0, 4]).to_i
	e.yday = $2[ 4, 3].to_i
      end
      if $3
	case $3.size
	when 2, 4, 6
	  e.hour = $3[ 0, 2].to_i
	  e.min  = $3[ 2, 2].to_i if $3.size >= 4
	  e.sec  = $3[ 4, 2].to_i if $3.size >= 6
	end
      end
      if $4
	e.sec_fraction = $4.to_i.to_r / (10**$4.size)
      end
      if $5
	e.zone = $5
      end
      true
    end
  end

  private_class_method :_parse_day, :_parse_time, :_parse_beat,
	:_parse_eu, :_parse_us, :_parse_iso, :_parse_iso2,
	:_parse_jis, :_parse_vms,
	:_parse_sla_ja, :_parse_sla_eu, :_parse_sla_us,
	:_parse_year, :_parse_mon, :_parse_mday, :_parse_ddd

  def self._parse(str, comp=false)
    str = str.dup

    e = Format::Bag.new

    e._comp = comp

    str.gsub!(/[^-+',.\/:0-9@a-z\x80-\xff]+/in, ' ')

    _parse_time(str, e) # || _parse_beat(str, e)
    _parse_day(str, e)

    _parse_eu(str, e)     ||
    _parse_us(str, e)     ||
    _parse_iso(str, e)    ||
    _parse_jis(str, e)    ||
    _parse_vms(str, e)    ||
    _parse_sla_us(str, e) ||
    _parse_iso2(str, e)   ||
    _parse_year(str, e)   ||
    _parse_mon(str, e)    ||
    _parse_mday(str, e)   ||
    _parse_ddd(str, e)

    if str.sub!(/\b(bc\b|bce\b|b\.c\.|b\.c\.e\.)/in, ' ')
      if e.year
	e.year = -e.year + 1
      end
    end

    if str.sub!(/\A\s*(\d{1,2})\s*\z/n, ' ')
      if e.hour && !e.mday
	v = $1.to_i
	if (1..31) === v
	  e.mday = v
	end
      end
      if e.mday && !e.hour
	v = $1.to_i
	if (0..24) === v
	  e.hour = v
	end
      end
    end

    if e._comp and e.year
      if e.year >= 0 and e.year <= 99
	if e.year >= 69
	  e.year += 1900
	else
	  e.year += 2000
	end
      end
    end

    e.offset ||= zone_to_diff(e.zone) if e.zone

    e.to_hash
  end

  def self.zone_to_diff(zone) # :nodoc:
    zone = zone.downcase
    if zone.sub!(/\s+(standard|daylight)\s+time\z/, '')
      dst = $1 == 'daylight'
    else
      dst = zone.sub!(/\s+dst\z/, '')
    end
    if Format::ZONES.include?(zone)
      offset = Format::ZONES[zone]
      offset += 3600 if dst
    elsif zone.sub!(/\A(?:gmt|utc?)?([-+])/, '')
      sign = $1
      if zone.include?(':')
	hour, min, sec, = zone.split(':')
      elsif zone.include?(',') || zone.include?('.')
	hour, fr, = zone.split(/[,.]/)
	min = fr.to_i.to_r / (10**fr.size) * 60
      else
	case zone.size
	when 3
	  hour = zone[0,1]
	  min = zone[1,2]
	else
	  hour = zone[0,2]
	  min = zone[2,2]
	  sec = zone[4,2]
	end
      end
      offset = hour.to_i * 3600 + min.to_i * 60 + sec.to_i
      offset *= -1 if sign == '-'
    end
    offset
  end

end

class DateTime < Date

  def strftime(fmt='%FT%T%:z')
    super(fmt)
  end

  def self._strptime(str, fmt='%FT%T%z')
    super(str, fmt)
  end

=begin
  def iso8601_timediv(n) # :nodoc:
    strftime('T%T' +
	     if n < 1
	       ''
	     else
	       '.%0*d' % [n, (sec_fraction / (1.to_r/86400/(10**n))).round]
	     end +
	     '%:z')
  end

  private :iso8601_timediv

  def iso8601(n=0)
    super() + iso8601_timediv(n)
  end

  def rfc3339(n=0) iso8601(n) end

  def jisx0301(n=0)
    super() + iso8601_timediv(n)
  end
=end

end
