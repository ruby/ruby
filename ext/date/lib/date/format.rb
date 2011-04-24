# format.rb: Written by Tadayoshi Funaba 1999-2011
require 'date_core.so'

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

      'utc' =>  0*3600, 'wet' =>  0*3600,
      'at'  => -2*3600, 'brst'=> -2*3600, 'ndt' => -(2*3600+1800),
      'art' => -3*3600, 'adt' => -3*3600, 'brt' => -3*3600, 'clst'=> -3*3600,
      'nst' => -(3*3600+1800),
      'ast' => -4*3600, 'clt' => -4*3600,
      'akdt'=> -8*3600, 'ydt' => -8*3600,
      'akst'=> -9*3600, 'hadt'=> -9*3600, 'hdt' => -9*3600, 'yst' => -9*3600,
      'ahst'=>-10*3600, 'cat' =>-10*3600, 'hast'=>-10*3600, 'hst' =>-10*3600,
      'nt'  =>-11*3600,
      'idlw'=>-12*3600,
      'bst' =>  1*3600, 'cet' =>  1*3600, 'fwt' =>  1*3600, 'met' =>  1*3600,
      'mewt'=>  1*3600, 'mez' =>  1*3600, 'swt' =>  1*3600, 'wat' =>  1*3600,
      'west'=>  1*3600,
      'cest'=>  2*3600, 'eet' =>  2*3600, 'fst' =>  2*3600, 'mest'=>  2*3600,
      'mesz'=>  2*3600, 'sast'=>  2*3600, 'sst' =>  2*3600,
      'bt'  =>  3*3600, 'eat' =>  3*3600, 'eest'=>  3*3600, 'msk' =>  3*3600,
      'msd' =>  4*3600, 'zp4' =>  4*3600,
      'zp5' =>  5*3600, 'ist' =>  (5*3600+1800),
      'zp6' =>  6*3600,
      'wast'=>  7*3600,
      'cct' =>  8*3600, 'sgt' =>  8*3600, 'wadt'=>  8*3600,
      'jst' =>  9*3600, 'kst' =>  9*3600,
      'east'=> 10*3600, 'gst' => 10*3600,
      'eadt'=> 11*3600,
      'idle'=> 12*3600, 'nzst'=> 12*3600, 'nzt' => 12*3600,
      'nzdt'=> 13*3600,

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

  end

  def asctime() strftime('%c') end

  alias_method :ctime, :asctime

  def iso8601() strftime('%F') end

  def rfc3339() strftime('%FT%T%:z') end

  def xmlschema() iso8601 end # :nodoc:

  def rfc2822() strftime('%a, %-d %b %Y %T %z') end

  alias_method :rfc822, :rfc2822

  def httpdate() new_offset(0).strftime('%a, %d %b %Y %T GMT') end # :nodoc:

  def jisx0301
    if jd < 2405160
      strftime('%F')
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

  def self._iso8601(str) # :nodoc:
    if /\A\s*(?:([-+]?\d{2,}|-)-(\d{2})-(\d{2})|
		([-+]?\d{2,})?-(\d{3})|
		(\d{4}|\d{2})?-w(\d{2})-(\d)|
		-w-(\d))
	(?:t
	(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d+))?)?
	(z|[-+]\d{2}(?::?\d{2})?)?)?\s*\z/ix =~ str
      if $3
	e = {
	  :mon => $2.to_i,
	  :mday => $3.to_i
	}
	if $1 != '-'
	  y = $1.to_i
	  if $1.size < 4
	    y += if y >= 69 then 1900 else 2000 end
	  end
	  e[:year] = y
	end
      elsif $5
	e = {
	  :yday => $5.to_i
	}
	if $4
	  y = $4.to_i
	  if $4.size < 4
	    y += if y >= 69 then 1900 else 2000 end
	  end
	  e[:year] = y
	end
      elsif $8
	e = {
	  :cweek => $7.to_i,
	  :cwday => $8.to_i
	}
	if $6
	  y = $6.to_i
	  if $6.size < 4
	    y += if y >= 69 then 1900 else 2000 end
	  end
	  e[:cwyear] = y
	end
      elsif $9
	e = {
	  :cwday => $9.to_i
	}
      end
      if $10
	e[:hour] = $10.to_i
	e[:min] = $11.to_i
	e[:sec] = $12.to_i if $12
      end
      if $13
	e[:sec_fraction] = Rational($13.to_i, 10**$13.size)
      end
      if $14
	e[:zone] = $14
	e[:offset] = zone_to_diff($14)
      end
      e
    elsif /\A\s*(?:([-+]?(?:\d{4}|\d{2})|--)(\d{2})(\d{2})|
		   ([-+]?(?:\d{4}|\d{2}))?(\d{3})|
		   -(\d{3})|
		   (\d{4}|\d{2})?w(\d{2})(\d))
	(?:t?
	(\d{2})(\d{2})(?:(\d{2})(?:[,.](\d+))?)?
	(z|[-+]\d{2}(?:\d{2})?)?)?\s*\z/ix =~ str
      if $3
	e = {
	  :mon => $2.to_i,
	  :mday => $3.to_i
	}
	if $1 != '--'
	  y = $1.to_i
	  if $1.size < 4
	    y += if y >= 69 then 1900 else 2000 end
	  end
	  e[:year] = y
	end
      elsif $5
	e = {
	  :yday => $5.to_i
	}
	if $4
	  y = $4.to_i
	  if $4.size < 4
	    y += if y >= 69 then 1900 else 2000 end
	  end
	  e[:year] = y
	end
      elsif $6
	e = {
	  :yday => $6.to_i
	}
      elsif $9
	e = {
	  :cweek => $8.to_i,
	  :cwday => $9.to_i
	}
	if $7
	  y = $7.to_i
	  if $7.size < 4
	    y += if y >= 69 then 1900 else 2000 end
	  end
	  e[:cwyear] = y
	end
      end
      if $10
	e[:hour] = $10.to_i
	e[:min] = $11.to_i
	e[:sec] = $12.to_i if $12
      end
      if $13
	e[:sec_fraction] = Rational($13.to_i, 10**$13.size)
      end
      if $14
	e[:zone] = $14
	e[:offset] = zone_to_diff($14)
      end
      e
    elsif /\A\s*(?:(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d+))?)?
	(z|[-+]\d{2}(:?\d{2})?)?)?\s*\z/ix =~ str
      e = {}
      e[:hour] = $1.to_i if $1
      e[:min] = $2.to_i if $2
      e[:sec] = $3.to_i if $3
      if $4
	e[:sec_fraction] = Rational($4.to_i, 10**$4.size)
      end
      if $5
	e[:zone] = $5
	e[:offset] = zone_to_diff($5)
      end
      e
    elsif /\A\s*(?:(\d{2})(\d{2})(?:(\d{2})(?:[,.](\d+))?)?
	(z|[-+]\d{2}(\d{2})?)?)?\s*\z/ix =~ str
      e = {}
      e[:hour] = $1.to_i if $1
      e[:min] = $2.to_i if $2
      e[:sec] = $3.to_i if $3
      if $4
	e[:sec_fraction] = Rational($4.to_i, 10**$4.size)
      end
      if $5
	e[:zone] = $5
	e[:offset] = zone_to_diff($5)
      end
      e
    end
  end

  def self._rfc3339(str) # :nodoc:
    if /\A\s*(-?\d{4})-(\d{2})-(\d{2}) # allow minus, anyway
	(?:t|\s)
	(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?
	(z|[-+]\d{2}:\d{2})\s*\z/ix =~ str
      e = {
	:year => $1.to_i,
	:mon => $2.to_i,
	:mday => $3.to_i,
	:hour => $4.to_i,
	:min => $5.to_i,
	:sec => $6.to_i,
	:zone => $8,
	:offset => zone_to_diff($8)
      }
      e[:sec_fraction] = Rational($7.to_i, 10**$7.size) if $7
      e
    end
  end

  def self._xmlschema(str) # :nodoc:
    if /\A\s*(-?\d{4,})(?:-(\d{2})(?:-(\d{2}))?)?
	(?:t
	  (\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?)?
	(z|[-+]\d{2}:\d{2})?\s*\z/ix =~ str
      e = {}
      e[:year] = $1.to_i
      e[:mon] = $2.to_i if $2
      e[:mday] = $3.to_i if $3
      e[:hour] = $4.to_i if $4
      e[:min] = $5.to_i if $5
      e[:sec] = $6.to_i if $6
      e[:sec_fraction] = Rational($7.to_i, 10**$7.size) if $7
      if $8
	e[:zone] = $8
	e[:offset] = zone_to_diff($8)
      end
      e
    elsif /\A\s*(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?
	(z|[-+]\d{2}:\d{2})?\s*\z/ix =~ str
      e = {}
      e[:hour] = $1.to_i if $1
      e[:min] = $2.to_i if $2
      e[:sec] = $3.to_i if $3
      e[:sec_fraction] = Rational($4.to_i, 10**$4.size) if $4
      if $5
	e[:zone] = $5
	e[:offset] = zone_to_diff($5)
      end
      e
    elsif /\A\s*(?:--(\d{2})(?:-(\d{2}))?|---(\d{2}))
	(z|[-+]\d{2}:\d{2})?\s*\z/ix =~ str
      e = {}
      e[:mon] = $1.to_i if $1
      e[:mday] = $2.to_i if $2
      e[:mday] = $3.to_i if $3
      if $4
	e[:zone] = $4
	e[:offset] = zone_to_diff($4)
      end
      e
    end
  end

  def self._rfc2822(str) # :nodoc:
    if /\A\s*(?:(#{Format::ABBR_DAYS.keys.join('|')})\s*,\s+)?
	(\d{1,2})\s+
	(#{Format::ABBR_MONTHS.keys.join('|')})\s+
	(-?\d{2,})\s+ # allow minus, anyway
	(\d{2}):(\d{2})(?::(\d{2}))?\s*
	([-+]\d{4}|ut|gmt|e[sd]t|c[sd]t|m[sd]t|p[sd]t|[a-ik-z])\s*\z/iox =~ str
      y = $4.to_i
      if $4.size < 4
	y += if y >= 50 then 1900 else 2000 end
      end
      e = {
	:wday => Format::ABBR_DAYS[$1.downcase],
	:mday => $2.to_i,
	:mon =>  Format::ABBR_MONTHS[$3.downcase],
	:year => y,
	:hour => $5.to_i,
	:min => $6.to_i,
	:zone => $8,
	:offset => zone_to_diff($8)
      }
      e[:sec] = $7.to_i if $7
      e
    end
  end

  class << self; alias_method :_rfc822, :_rfc2822 end

  def self._httpdate(str) # :nodoc:
    if /\A\s*(#{Format::ABBR_DAYS.keys.join('|')})\s*,\s+
	(\d{2})\s+
	(#{Format::ABBR_MONTHS.keys.join('|')})\s+
	(-?\d{4})\s+ # allow minus, anyway
	(\d{2}):(\d{2}):(\d{2})\s+
	(gmt)\s*\z/iox =~ str
      {
	:wday => Format::ABBR_DAYS[$1.downcase],
	:mday => $2.to_i,
	:mon =>  Format::ABBR_MONTHS[$3.downcase],
	:year => $4.to_i,
	:hour => $5.to_i,
	:min => $6.to_i,
	:sec => $7.to_i,
	:zone => $8,
	:offset => zone_to_diff($8)
      }
    elsif /\A\s*(#{Format::DAYS.keys.join('|')})\s*,\s+
	(\d{2})\s*-\s*
	(#{Format::ABBR_MONTHS.keys.join('|')})\s*-\s*
	(\d{2})\s+
	(\d{2}):(\d{2}):(\d{2})\s+
	(gmt)\s*\z/iox =~ str
      y = $4.to_i
      if y >= 0 && y <= 99
	y += if y >= 69 then 1900 else 2000 end
      end
      {
	:wday => Format::DAYS[$1.downcase],
	:mday => $2.to_i,
	:mon =>  Format::ABBR_MONTHS[$3.downcase],
	:year => y,
	:hour => $5.to_i,
	:min => $6.to_i,
	:sec => $7.to_i,
	:zone => $8,
	:offset => zone_to_diff($8)
      }
    elsif /\A\s*(#{Format::ABBR_DAYS.keys.join('|')})\s+
	(#{Format::ABBR_MONTHS.keys.join('|')})\s+
	(\d{1,2})\s+
	(\d{2}):(\d{2}):(\d{2})\s+
	(\d{4})\s*\z/iox =~ str
      {
	:wday => Format::ABBR_DAYS[$1.downcase],
	:mon =>  Format::ABBR_MONTHS[$2.downcase],
	:mday => $3.to_i,
	:hour => $4.to_i,
	:min => $5.to_i,
	:sec => $6.to_i,
	:year => $7.to_i
      }
    end
  end

  def self._jisx0301(str) # :nodoc:
    if /\A\s*([mtsh])?(\d{2})\.(\d{2})\.(\d{2})
	(?:t
	(?:(\d{2}):(\d{2})(?::(\d{2})(?:[,.](\d*))?)?
	(z|[-+]\d{2}(?::?\d{2})?)?)?)?\s*\z/ix =~ str
      era = {
	'm'=>1867,
	't'=>1911,
	's'=>1925,
	'h'=>1988
      }[$1 ? $1.downcase : 'h']
      e = {
	:year => $2.to_i + era,
	:mon =>  $3.to_i,
	:mday => $4.to_i
      }
      if $5
	e[:hour] = $5.to_i
	e[:min] = $6.to_i if $6
	e[:sec] = $7.to_i if $7
      end
      if $8
	e[:sec_fraction] = Rational($8.to_i, 10**$8.size)
      end
      if $9
	e[:zone] = $9
	e[:offset] = zone_to_diff($9)
      end
      e
    else
      _iso8601(str)
    end
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
	min = Rational(fr.to_i, 10**fr.size) * 60
      else
	if (zone.size % 2) == 1
	  hour = zone[0,1]
	  min = zone[1,2]
	  sec = zone[3,2]
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

  private_class_method :zone_to_diff

end

class DateTime < Date

  def iso8601_timediv(n) # :nodoc:
    strftime('T%T' +
	     if n < 1
	       ''
	     else
	       '.%0*d' % [n, (sec_fraction / Rational(1, 10**n)).round]
	     end +
	     '%:z')
  end

  private :iso8601_timediv

  def iso8601(n=0)
    super() + iso8601_timediv(n)
  end

  def rfc3339(n=0) iso8601(n) end

  def xmlschema(n=0) iso8601(n) end # :nodoc:

  def jisx0301(n=0)
    super() + iso8601_timediv(n)
  end

end
