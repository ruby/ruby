# parsedate3.rb: Written by Tadayoshi Funaba 2000, 2001
# $Id: parsedate3.rb,v 1.3 2001-01-18 12:09:47+09 tadf Exp $

module ParseDate

  MONTHS = {
    'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4,
    'may' => 5, 'jun' => 6, 'jul' => 7, 'aug' => 8,
    'sep' => 9, 'oct' =>10, 'nov' =>11, 'dec' =>12
  }
  MONTHPAT = MONTHS.keys.join('|')

  DAYS = {
    'sun' => 0, 'mon' => 1, 'tue' => 2, 'wed' => 3,
    'thu' => 4, 'fri' => 5, 'sat' => 6
  }
  DAYPAT = DAYS.keys.join('|')

  def parsedate(date, cyear=false)
    date = date.dup

    # day
    if date.sub!(/(#{DAYPAT})\S*/ino, ' ')
      wday = DAYS[$1.downcase]
    end

    # time
    if date.sub!(
		 /(\d+):(\d+)(?::(\d+))?
		  (?:
		    \s*
		    ([ap])\.?m\.?
		    \b
		  )?
		  (?:
		    \s*
		    (
		      [a-z]+(?:\s+dst)?
		    |
		      [-+]\d+(?::?\d+)
		    )
		    \b
		  )?
		 /inox,
		 ' ')
      hour = $1.to_i
      min = $2.to_i
      sec = $3.to_i if $3
      if $4
	hour %= 12
	if $4.downcase == 'p'
	  hour += 12
	end
      end
      zone = $5
    end

    # eu
    if date.sub!(
		 /(\d+)\S*
		  \s+
		  (#{MONTHPAT})\S*
		  (?:
		    \s+
		    (\d+)
		  )?
		 /inox,
		 ' ')
      mday = $1.to_i
      mon = MONTHS[$2.downcase]
      year = $3.to_i if $3

    # us
    elsif date.sub!(
		    /(#{MONTHPAT})\S*
		     \s+
		     (\d+)\S*
		     (?:
		       \s+
		       (\d+)
		     )?
		    /inox,
		    ' ')
      mon = MONTHS[$1.downcase]
      mday = $2.to_i
      year = $3.to_i if $3

    # iso
    elsif date.sub!(/(\d+)-(\d+)-(\d+)/no, ' ')
      year = $1.to_i
      mon = $2.to_i
      mday = $3.to_i
      mday, mon, year = year, mon, mday if $3.size >= 4

    # jis
    elsif date.sub!(/([MTSH])(\d+)\.(\d+)\.(\d+)/no, ' ')
      e = { 'M'=>1867,
	    'T'=>1911,
	    'S'=>1925,
	    'H'=>1988
	  }[$1]
      year, mon, mday = $2.to_i + e, $3.to_i, $4.to_i

    # vms
    elsif date.sub!(/(\d+)-(#{MONTHPAT})\S*-(\d+)/ino, ' ')
      mday = $1.to_i
      mon = MONTHS[$2.downcase]
      year = $3.to_i
      year, mon, mday = mday, mon, year if $1.size >= 4

    # sla
    elsif date.sub!(%r|(\d+)/(\d+)(?:/(\d+))?|no, ' ')
      mon = $1.to_i
      mday = $2.to_i
      year = $3.to_i if $3
      year, mon, mday = mon, mday, year if $1.size >= 4

    # ddd
    elsif date.sub!(
		    /(\d{4,14})
		     (?:
		       \s*
		       T?
		       \s*
		       (\d{2,6})
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
		    /nox,
		    ' ')
      case $1.size
      when 4
	mon  = $1[ 0, 2].to_i
	mday = $1[ 2, 2].to_i
      when 6
	year = $1[ 0, 2].to_i
	mon  = $1[ 2, 2].to_i
	mday = $1[ 4, 2].to_i
      when 8, 10, 12, 14
	year = $1[ 0, 4].to_i
	mon  = $1[ 4, 2].to_i
	mday = $1[ 6, 2].to_i
	hour = $1[ 8, 2].to_i if $1.size >= 10
	min  = $1[10, 2].to_i if $1.size >= 12
	sec  = $1[12, 2].to_i if $1.size >= 14
      end
      if $2
	case $2.size
	when 2, 4, 6
	  hour = $2[ 0, 2].to_i
	  min  = $2[ 2, 2].to_i if $2.size >= 4
	  sec  = $2[ 4, 2].to_i if $2.size >= 6
	end
      end
      zone = $3
    end

    if cyear and year
      if year < 100
	if year >= 69
	  year += 1900
	else
	  year += 2000
	end
      end
    end

    return year, mon, mday, hour, min, sec, zone, wday

  end

  module_function :parsedate

end
