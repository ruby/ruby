# format.rb: Written by Tadayoshi Funaba 1999-2004
# $Id: format.rb,v 2.14 2004-11-06 10:58:40+09 tadf Exp $

require 'rational'

class Date

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
    'nzt' => 12*3600, 'nzst'=> 12*3600, 'nzdt'=> 13*3600, 'idle'=> 12*3600
  }

  def self.__strptime(str, fmt, elem)
    fmt.scan(/%[EO]?.|./o) do |c|
      cc = c.sub(/\A%[EO]?(.)\Z/o, '%\\1')
      case cc
      when /\A\s/o
	str.sub!(/\A[\s\v]+/o, '')
      when '%A', '%a'
	return unless str.sub!(/\A([a-z]+)\b/io, '')
	val = DAYS[$1.downcase] || ABBR_DAYS[$1.downcase]
	return unless val
	elem[:wday] = val
      when '%B', '%b', '%h'
	return unless str.sub!(/\A([a-z]+)\b/io, '')
	val = MONTHS[$1.downcase] || ABBR_MONTHS[$1.downcase]
	return unless val
	elem[:mon] = val
      when '%C'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	elem[:cent] = val
      when '%c'
	return unless __strptime(str, '%a %b %e %H:%M:%S %Y', elem)
      when '%D'
	return unless __strptime(str, '%m/%d/%y', elem)
      when '%d', '%e'
	return unless str.sub!(/\A ?(\d+)/o, '')
	val = $1.to_i
	return unless (1..31) === val
	elem[:mday] = val
      when '%F'
	return unless __strptime(str, '%Y-%m-%d', elem)
      when '%G'
	return unless str.sub!(/\A([-+]?\d+)/o, '')
	val = $1.to_i
	elem[:cwyear] = val
      when '%g'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	return unless (0..99) === val
	elem[:cwyear] = val
	elem[:cent] ||= if val >= 69 then 19 else 20 end
      when '%H', '%k'
	return unless str.sub!(/\A ?(\d+)/o, '')
	val = $1.to_i
	return unless (0..24) === val
	elem[:hour] = val
      when '%I', '%l'
	return unless str.sub!(/\A ?(\d+)/o, '')
	val = $1.to_i
	return unless (1..12) === val
	elem[:hour] = val
      when '%j'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	return unless (1..366) === val
	elem[:yday] = val
      when '%M'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	return unless (0..59) === val
	elem[:min] = val
      when '%m'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	return unless (1..12) === val
	elem[:mon] = val
      when '%n'
	return unless __strptime(str, ' ', elem)
      when '%p', '%P'
	return unless str.sub!(/\A([ap])(?:m\b|\.m\.)/io, '')
	elem[:merid] = if $1.downcase == 'a' then 0 else 12 end
      when '%R'
	return unless __strptime(str, '%H:%M', elem)
      when '%r'
	return unless __strptime(str, '%I:%M:%S %p', elem)
      when '%S'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	return unless (0..60) === val
	elem[:sec] = val
      when '%s'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	elem[:seconds] = val
      when '%T'
	return unless __strptime(str, '%H:%M:%S', elem)
      when '%t'
	return unless __strptime(str, ' ', elem)
      when '%U', '%W'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	return unless (0..53) === val
	elem[if c == '%U' then :wnum0 else :wnum1 end] = val
      when '%u'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	return unless (1..7) === val
	elem[:cwday] = val
      when '%V'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	return unless (1..53) === val
	elem[:cweek] = val
      when '%v'
	return unless __strptime(str, '%e-%b-%Y', elem)
      when '%w'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	return unless (0..6) === val
	elem[:wday] = val
      when '%X'
	return unless __strptime(str, '%H:%M:%S', elem)
      when '%x'
	return unless __strptime(str, '%m/%d/%y', elem)
      when '%Y'
	return unless str.sub!(/\A([-+]?\d+)/o, '')
	val = $1.to_i
	elem[:year] = val
      when '%y'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	return unless (0..99) === val
	elem[:year] = val
	elem[:cent] ||= if val >= 69 then 19 else 20 end
      when '%Z', '%z'
	return unless str.sub!(/\A([-+:a-z0-9]+(?:\s+dst\b)?)/io, '')
	val = $1
	elem[:zone] = val
	offset = zone_to_diff(val)
	elem[:offset] = offset
      when '%%'
	return unless str.sub!(/\A%/o, '')
      when '%+'
	return unless __strptime(str, '%a %b %e %H:%M:%S %Z %Y', elem)
=begin
      when '%.'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i.to_r / (10**$1.size)
	elem[:sec_fraction] = val
=end
      when '%1'
	return unless str.sub!(/\A(\d+)/o, '')
	val = $1.to_i
	elem[:jd] = val
      when '%2'
	return unless __strptime(str, '%Y-%j', elem)
      when '%3'
	return unless __strptime(str, '%F', elem)
      else
	return unless str.sub!(Regexp.new('\\A' + Regexp.quote(c)), '')
      end
    end

    if cent = elem.delete(:cent)
      if elem[:cwyear]
	elem[:cwyear] += cent * 100
      end
      if elem[:year]
	elem[:year] += cent * 100
      end
    end

    if merid = elem.delete(:merid)
      if elem[:hour]
	elem[:hour] %= 12
	elem[:hour] += merid
      end
    end

    str
  end

  private_class_method :__strptime

  def self._strptime(str, fmt='%F')
    elem = {}
    elem if __strptime(str.dup, fmt, elem)
  end

  PARSE_MONTHPAT = ABBR_MONTHS.keys.join('|')
  PARSE_DAYPAT   = ABBR_DAYS.  keys.join('|')

  def self._parse(str, comp=false)
    str = str.dup

    str.gsub!(/[^-+,.\/:0-9a-z]+/ino, ' ')

    # day
    if str.sub!(/(#{PARSE_DAYPAT})\S*/ino, ' ')
      wday = ABBR_DAYS[$1.downcase]
    end

    # time
    if str.sub!(
		/(\d+):(\d+)
		 (?:
		   :(\d+)(?:[,.](\d*))?
		 )?
		 (?:
		   \s*
		   ([ap])(?:m\b|\.m\.)
		 )?
		 (?:
		   \s*
		   (
		     [a-z]+(?:\s+dst)?\b
		   |
		     [-+]\d+(?::?\d+)
		   )
		 )?
		/inox,
		' ')
      hour = $1.to_i
      min = $2.to_i
      sec = $3.to_i if $3
      if $4
	sec_fraction = $4.to_i.to_r / (10**$4.size)
      end

      if $5
	hour %= 12
	if $5.downcase == 'p'
	  hour += 12
	end
      end

      if $6
	zone = $6
      end
    end

    # eu
    if str.sub!(
		/(\d+)\S*
		 \s+
		 (#{PARSE_MONTHPAT})\S*
		 (?:
		   \s+
		   (-?\d+)
		 )?
		/inox,
		' ')
      mday = $1.to_i
      mon = ABBR_MONTHS[$2.downcase]

      if $3
	year = $3.to_i
	if $3.size > 2
	  comp = false
	end
      end

    # us
    elsif str.sub!(
		   /(#{PARSE_MONTHPAT})\S*
		    \s+
		    (\d+)\S*
		    (?:
		      \s+
		      (-?\d+)
		    )?
		   /inox,
		   ' ')
      mon = ABBR_MONTHS[$1.downcase]
      mday = $2.to_i

      if $3
	year = $3.to_i
	if $3.size > 2
	  comp = false
	end
      end

    # iso
    elsif str.sub!(/([-+]?\d+)-(\d+)-(-?\d+)/no, ' ')
      year = $1.to_i
      mon = $2.to_i
      mday = $3.to_i

      if $1.size > 2
	comp = false
      elsif $3.size > 2
	comp = false
	mday, mon, year = year, mon, mday
      end

    # jis
    elsif str.sub!(/([MTSH])(\d+)\.(\d+)\.(\d+)/ino, ' ')
      e = { 'm'=>1867,
	    't'=>1911,
	    's'=>1925,
	    'h'=>1988
	  }[$1.downcase]
      year = $2.to_i + e
      mon = $3.to_i
      mday = $4.to_i

    # vms
    elsif str.sub!(/(-?\d+)-(#{PARSE_MONTHPAT})[^-]*-(-?\d+)/ino, ' ')
      mday = $1.to_i
      mon = ABBR_MONTHS[$2.downcase]
      year = $3.to_i

      if $1.size > 2
	comp = false
	year, mon, mday = mday, mon, year
      elsif $3.size > 2
	comp = false
      end

    # sla
    elsif str.sub!(%r|(-?\d+)/(\d+)(?:/(-?\d+))?|no, ' ')
      mon = $1.to_i
      mday = $2.to_i

      if $3
	year = $3.to_i
	if $3.size > 2
	  comp = false
	end
      end

      if $3 && $1.size > 2
	comp = false
	year, mon, mday = mon, mday, year
      end

    # ddd
    elsif str.sub!(
		   /([-+]?)(\d{4,14})
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
			[-+]\d{2,4}
		      )
		      \b
		    )?
		   /inox,
		   ' ')
      case $2.size
      when 4
	mon  = $2[ 0, 2].to_i
	mday = $2[ 2, 2].to_i
      when 6
	year = ($1 + $2[ 0, 2]).to_i
	mon  = $2[ 2, 2].to_i
	mday = $2[ 4, 2].to_i
      when 8, 10, 12, 14
	year = ($1 + $2[ 0, 4]).to_i
	mon  = $2[ 4, 2].to_i
	mday = $2[ 6, 2].to_i
	hour = $2[ 8, 2].to_i if $2.size >= 10
	min  = $2[10, 2].to_i if $2.size >= 12
	sec  = $2[12, 2].to_i if $2.size >= 14
	comp = false
      end
      if $3
	case $3.size
	when 2, 4, 6
	  hour = $3[ 0, 2].to_i
	  min  = $3[ 2, 2].to_i if $3.size >= 4
	  sec  = $3[ 4, 2].to_i if $3.size >= 6
	end
      end
      if $4
	sec_fraction = $4.to_i.to_r / (10**$4.size)
      end
      if $5
	zone = $5
      end
    end

    if str.sub!(/\b(bc\b|bce\b|b\.c\.|b\.c\.e\.)/ino, ' ')
      if year
	year = -year + 1
      end
    end

    if comp and year
      if year >= 0 and year <= 99
	if year >= 69
	  year += 1900
	else
	  year += 2000
	end
      end
    end

    elem = {}
    elem[:year] = year if year
    elem[:mon] = mon if mon
    elem[:mday] = mday if mday
    elem[:hour] = hour if hour
    elem[:min] = min if min
    elem[:sec] = sec if sec
    elem[:sec_fraction] = sec_fraction if sec_fraction
    elem[:zone] = zone if zone
    offset = zone_to_diff(zone) if zone
    elem[:offset] = offset if offset
    elem[:wday] = wday if wday
    elem
  end

  def self.zone_to_diff(str)
    abb, dst = str.downcase.split(/\s+/o, 2)
    if ZONES.include?(abb)
      offset  = ZONES[abb]
      offset += 3600 if dst
    elsif /\A([-+])(\d{2}):?(\d{2})?\Z/no =~ str
      offset = $2.to_i * 3600 + $3.to_i * 60
      offset *= -1 if $1 == '-'
    end
    offset
  end

  def strftime(fmt='%F')
    o = ''
    fmt.scan(/%[EO]?.|./o) do |c|
      cc = c.sub(/^%[EO]?(.)$/o, '%\\1')
      case cc
      when '%A'; o << DAYNAMES[wday]
      when '%a'; o << ABBR_DAYNAMES[wday]
      when '%B'; o << MONTHNAMES[mon]
      when '%b'; o << ABBR_MONTHNAMES[mon]
      when '%C'; o << '%02d' % (year / 100.0).floor		# P2,ID
      when '%c'; o << strftime('%a %b %e %H:%M:%S %Y')
      when '%D'; o << strftime('%m/%d/%y')			# P2,ID
      when '%d'; o << '%02d' % mday
      when '%e'; o <<  '%2d' % mday
      when '%F'; o << strftime('%Y-%m-%d')			# ID
      when '%G'; o << '%.4d' %  cwyear				# ID
      when '%g'; o << '%02d' % (cwyear % 100)			# ID
      when '%H'; o << '%02d' %   hour
      when '%h'; o << strftime('%b')				# P2,ID
      when '%I'; o << '%02d' % ((hour % 12).nonzero? or 12)
      when '%j'; o << '%03d' % yday
      when '%k'; o <<  '%2d' %   hour				# AR,TZ,GL
      when '%l'; o <<  '%2d' % ((hour % 12).nonzero? or 12)	# AR,TZ,GL
      when '%M'; o << '%02d' % min
      when '%m'; o << '%02d' % mon
      when '%n'; o << "\n"					# P2,ID
      when '%P'; o << if hour < 12 then 'am' else 'pm' end	# GL
      when '%p'; o << if hour < 12 then 'AM' else 'PM' end
      when '%R'; o << strftime('%H:%M')				# ID
      when '%r'; o << strftime('%I:%M:%S %p')			# P2,ID
      when '%S'; o << '%02d' % sec
      when '%s'							# TZ,GL
	d = ajd - self.class.jd_to_ajd(self.class.civil_to_jd(1970,1,1), 0)
	s = (d * 86400).to_i
	o << '%d' % s
      when '%T'; o << strftime('%H:%M:%S')			# P2,ID
      when '%t'; o << "\t"					# P2,ID
      when '%U', '%W'
	a = self.class.civil_to_jd(year, 1, 1, ns?) + 6
	k = if c == '%U' then 0 else 1 end
	w = (jd - (a - ((a - k) + 1) % 7) + 7) / 7
	o << '%02d' % w
      when '%u'; o <<   '%d' % cwday				# P2,ID
      when '%V'; o << '%02d' % cweek				# P2,ID
      when '%v'; o << strftime('%e-%b-%Y')			# AR,TZ
      when '%w'; o <<   '%d' % wday
      when '%X'; o << strftime('%H:%M:%S')
      when '%x'; o << strftime('%m/%d/%y')
      when '%Y'; o << '%.4d' %  year
      when '%y'; o << '%02d' % (year % 100)
      when '%Z'; o << (if offset.zero? then 'Z' else strftime('%z') end)
      when '%z'							# ID
	o << if offset < 0 then '-' else '+' end
	of = offset.abs
	hh, fr = of.divmod(1.to_r/24)
	mm = fr / (1.to_r/1440)
	o << '%02d' % hh
	o << '%02d' % mm
      when '%%'; o << '%'
      when '%+'; o << strftime('%a %b %e %H:%M:%S %Z %Y')	# TZ
=begin
      when '%.'
	o << '%06d' % (sec_fraction / (1.to_r/86400/(10**6)))
=end
      when '%1'; o <<   '%d' % jd
      when '%2'; o << strftime('%Y-%j')
      when '%3'; o << strftime('%Y-%m-%d')
      else;      o << c
      end
    end
    o
  end

# alias_method :format, :strftime

  def asctime() strftime('%c') end

  alias_method :ctime, :asctime

end

class DateTime < Date

  def self._strptime(str, fmt='%FT%T%Z')
    super(str, fmt)
  end

  def strftime(fmt='%FT%T%Z')
    super(fmt)
  end

end
