
#
# == Introduction
#
# This library extends the Time class:
# * conversion between date string and time object.
#   * date-time defined by RFC 2822
#   * HTTP-date defined by RFC 2616
#   * dateTime defined by XML Schema Part 2: Datatypes (ISO 8601)
#   * various formats handled by Date._parse (string to time only)
#
# == Design Issues
#
# === Specialized interface
#
# This library provides methods dedicated to special purposes:
# * RFC 2822, RFC 2616 and XML Schema.
# * They makes usual life easier.
#
# === Doesn't depend on strftime
#
# This library doesn't use +strftime+.  Especially #rfc2822 doesn't depend
# on +strftime+ because:
#
# * %a and %b are locale sensitive
#
#   Since they are locale sensitive, they may be replaced to
#   invalid weekday/month name in some locales.
#   Since ruby-1.6 doesn't invoke setlocale by default,
#   the problem doesn't arise until some external library invokes setlocale.
#   Ruby/GTK is the example of such library.
#
# * %z is not portable
#
#   %z is required to generate zone in date-time of RFC 2822
#   but it is not portable.
#

require 'date/format'

#
# Implements the extensions to the Time class that are described in the
# documentation for the time.rb library.
#
class Time
  class << Time

    ZoneOffset = {
      'UTC' => 0,
      # ISO 8601
      'Z' => 0,
      # RFC 822
      'UT' => 0, 'GMT' => 0,
      'EST' => -5, 'EDT' => -4,
      'CST' => -6, 'CDT' => -5,
      'MST' => -7, 'MDT' => -6,
      'PST' => -8, 'PDT' => -7,
      # Following definition of military zones is original one.
      # See RFC 1123 and RFC 2822 for the error in RFC 822.
      'A' => +1, 'B' => +2, 'C' => +3, 'D' => +4,  'E' => +5,  'F' => +6,
      'G' => +7, 'H' => +8, 'I' => +9, 'K' => +10, 'L' => +11, 'M' => +12,
      'N' => -1, 'O' => -2, 'P' => -3, 'Q' => -4,  'R' => -5,  'S' => -6,
      'T' => -7, 'U' => -8, 'V' => -9, 'W' => -10, 'X' => -11, 'Y' => -12,
    }
    def zone_offset(zone, year=self.now.year)
      off = nil
      zone = zone.upcase
      if /\A([+-])(\d\d):?(\d\d)\z/ =~ zone
        off = ($1 == '-' ? -1 : 1) * ($2.to_i * 60 + $3.to_i) * 60
      elsif /\A[+-]\d\d\z/ =~ zone
        off = zone.to_i * 3600
      elsif ZoneOffset.include?(zone)
        off = ZoneOffset[zone] * 3600
      elsif ((t = self.local(year, 1, 1)).zone.upcase == zone rescue false)
        off = t.utc_offset
      elsif ((t = self.local(year, 7, 1)).zone.upcase == zone rescue false)
        off = t.utc_offset
      end
      off
    end

    def zone_utc?(zone)
      # * +0000
      #   In RFC 2822, +0000 indicate a time zone at Universal Time.
      #   Europe/London is "a time zone at Universal Time" in Winter.
      #   Europe/Lisbon is "a time zone at Universal Time" in Winter.
      #   Atlantic/Reykjavik is "a time zone at Universal Time".
      #   Africa/Dakar is "a time zone at Universal Time".
      #   So +0000 is a local time such as Europe/London, etc.
      # * GMT
      #   GMT is used as a time zone abbreviation in Europe/London,
      #   Africa/Dakar, etc.
      #   So it is a local time.
      #
      # * -0000, -00:00
      #   In RFC 2822, -0000 the date-time contains no information about the
      #   local time zone.
      #   In RFC 3339, -00:00 is used for the time in UTC is known,
      #   but the offset to local time is unknown.
      #   They are not appropriate for specific time zone such as
      #   Europe/London because time zone neutral,
      #   So -00:00 and -0000 are treated as UTC.
      if /\A(?:-00:00|-0000|-00|UTC|Z|UT)\z/i =~ zone
        true
      else
        false
      end
    end
    private :zone_utc?

    LeapYearMonthDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    CommonYearMonthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    def month_days(y, m)
      if ((y % 4 == 0) && (y % 100 != 0)) || (y % 400 == 0)
        LeapYearMonthDays[m-1]
      else
        CommonYearMonthDays[m-1]
      end
    end
    private :month_days

    def apply_offset(year, mon, day, hour, min, sec, off)
      if off < 0
        off = -off
        off, o = off.divmod(60)
        if o != 0 then sec += o; o, sec = sec.divmod(60); off += o end
        off, o = off.divmod(60)
        if o != 0 then min += o; o, min = min.divmod(60); off += o end
        off, o = off.divmod(24)
        if o != 0 then hour += o; o, hour = hour.divmod(24); off += o end
        if off != 0
          day += off
          if month_days(year, mon) < day
            mon += 1
            if 12 < mon
              mon = 1
              year += 1
            end
            day = 1
          end
        end
      elsif 0 < off
        off, o = off.divmod(60)
        if o != 0 then sec -= o; o, sec = sec.divmod(60); off -= o end
        off, o = off.divmod(60)
        if o != 0 then min -= o; o, min = min.divmod(60); off -= o end
        off, o = off.divmod(24)
        if o != 0 then hour -= o; o, hour = hour.divmod(24); off -= o end
        if off != 0 then
          day -= off
          if day < 1
            mon -= 1
            if mon < 1
              year -= 1
              mon = 12
            end
            day = month_days(year, mon)
          end
        end
      end
      return year, mon, day, hour, min, sec
    end
    private :apply_offset

    def make_time(year, mon, day, hour, min, sec, sec_fraction, zone, now)
      usec = nil
      usec = sec_fraction * 1000000 if sec_fraction
      if now
        begin
          break if year; year = now.year
          break if mon; mon = now.mon
          break if day; day = now.day
          break if hour; hour = now.hour
          break if min; min = now.min
          break if sec; sec = now.sec
          break if sec_fraction; usec = now.tv_usec
        end until true
      end

      year ||= 1970
      mon ||= 1
      day ||= 1
      hour ||= 0
      min ||= 0
      sec ||= 0
      usec ||= 0

      off = nil
      off = zone_offset(zone, year) if zone

      if off
        year, mon, day, hour, min, sec =
          apply_offset(year, mon, day, hour, min, sec, off)
        t = self.utc(year, mon, day, hour, min, sec, usec)
        t.localtime if !zone_utc?(zone)
        t
      else
        self.local(year, mon, day, hour, min, sec, usec)
      end
    end
    private :make_time

    #
    # Parses +date+ using Date._parse and converts it to a Time object.
    #
    # If a block is given, the year described in +date+ is converted by the
    # block.  For example:
    #
    #     Time.parse(...) {|y| 0 <= y && y < 100 ? (y >= 69 ? y + 1900 : y + 2000) : y}
    #
    # If the upper components of the given time are broken or missing, they are
    # supplied with those of +now+.  For the lower components, the minimum
    # values (1 or 0) are assumed if broken or missing.  For example:
    #
    #     # Suppose it is "Thu Nov 29 14:33:20 GMT 2001" now and
    #     # your timezone is GMT:
    #     now = Time.parse("Thu Nov 29 14:33:20 GMT 2001")
    #     Time.parse("16:30", now)     #=> 2001-11-29 16:30:00 +0900
    #     Time.parse("7/23", now)      #=> 2001-07-23 00:00:00 +0900
    #     Time.parse("Aug 31", now)    #=> 2001-08-31 00:00:00 +0900
    #     Time.parse("Aug 2000", now)  #=> 2000-08-01 00:00:00 +0900
    #
    # Since there are numerous conflicts among locally defined timezone
    # abbreviations all over the world, this method is not made to
    # understand all of them.  For example, the abbreviation "CST" is
    # used variously as:
    #
    #     -06:00 in America/Chicago,
    #     -05:00 in America/Havana,
    #     +08:00 in Asia/Harbin,
    #     +09:30 in Australia/Darwin,
    #     +10:30 in Australia/Adelaide,
    #     etc.
    #
    # Based on the fact, this method only understands the timezone
    # abbreviations described in RFC 822 and the system timezone, in the
    # order named. (i.e. a definition in RFC 822 overrides the system
    # timezone definition.)  The system timezone is taken from
    # <tt>Time.local(year, 1, 1).zone</tt> and
    # <tt>Time.local(year, 7, 1).zone</tt>.
    # If the extracted timezone abbreviation does not match any of them,
    # it is ignored and the given time is regarded as a local time.
    #
    # ArgumentError is raised if Date._parse cannot extract information from
    # +date+ or Time class cannot represent specified date.
    #
    # This method can be used as fail-safe for other parsing methods as:
    #
    #   Time.rfc2822(date) rescue Time.parse(date)
    #   Time.httpdate(date) rescue Time.parse(date)
    #   Time.xmlschema(date) rescue Time.parse(date)
    #
    # A failure for Time.parse should be checked, though.
    #
    # time library should be required to use this method as follows.
    #
    #     require 'time'
    #
    def parse(date, now=self.now)
      comp = !block_given?
      d = Date._parse(date, comp)
      if !d[:year] && !d[:mon] && !d[:mday] && !d[:hour] && !d[:min] && !d[:sec] && !d[:sec_fraction]
        raise ArgumentError, "no time information in #{date.inspect}"
      end
      year = d[:year]
      year = yield(year) if year && !comp
      make_time(year, d[:mon], d[:mday], d[:hour], d[:min], d[:sec], d[:sec_fraction], d[:zone], now)
    end

    #
    # Parses +date+ using Date._strptime and converts it to a Time object.
    #
    # If a block is given, the year described in +date+ is converted by the
    # block.  For example:
    #
    #     Time.strptime(...) {|y| y < 100 ? (y >= 69 ? y + 1900 : y + 2000) : y}
    def strptime(date, format, now=self.now)
      d = Date._strptime(date, format)
      raise ArgumentError, "invalid strptime format - `#{format}'" unless d
      year = d[:year]
      year = yield(year) if year && block_given?
      make_time(year, d[:mon], d[:mday], d[:hour], d[:min], d[:sec], d[:sec_fraction], d[:zone], now)
    end

    MonthValue = {
      'JAN' => 1, 'FEB' => 2, 'MAR' => 3, 'APR' => 4, 'MAY' => 5, 'JUN' => 6,
      'JUL' => 7, 'AUG' => 8, 'SEP' => 9, 'OCT' =>10, 'NOV' =>11, 'DEC' =>12
    }

    #
    # Parses +date+ as date-time defined by RFC 2822 and converts it to a Time
    # object.  The format is identical to the date format defined by RFC 822 and
    # updated by RFC 1123.
    #
    # ArgumentError is raised if +date+ is not compliant with RFC 2822
    # or Time class cannot represent specified date.
    #
    # See #rfc2822 for more information on this format.
    #
    # time library should be required to use this method as follows.
    #
    #     require 'time'
    #
    def rfc2822(date)
      if /\A\s*
          (?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s*,\s*)?
          (\d{1,2})\s+
          (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+
          (\d{2,})\s+
          (\d{2})\s*
          :\s*(\d{2})\s*
          (?::\s*(\d{2}))?\s+
          ([+-]\d{4}|
           UT|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT|[A-IK-Z])/ix =~ date
        # Since RFC 2822 permit comments, the regexp has no right anchor.
        day = $1.to_i
        mon = MonthValue[$2.upcase]
        year = $3.to_i
        hour = $4.to_i
        min = $5.to_i
        sec = $6 ? $6.to_i : 0
        zone = $7

        # following year completion is compliant with RFC 2822.
        year = if year < 50
                 2000 + year
               elsif year < 1000
                 1900 + year
               else
                 year
               end

        year, mon, day, hour, min, sec =
          apply_offset(year, mon, day, hour, min, sec, zone_offset(zone))
        t = self.utc(year, mon, day, hour, min, sec)
        t.localtime if !zone_utc?(zone)
        t
      else
        raise ArgumentError.new("not RFC 2822 compliant date: #{date.inspect}")
      end
    end
    alias rfc822 rfc2822

    #
    # Parses +date+ as HTTP-date defined by RFC 2616 and converts it to a Time
    # object.
    #
    # ArgumentError is raised if +date+ is not compliant with RFC 2616 or Time
    # class cannot represent specified date.
    #
    # See #httpdate for more information on this format.
    #
    # time library should be required to use this method as follows.
    #
    #     require 'time'
    #
    def httpdate(date)
      if /\A\s*
          (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),\x20
          (\d{2})\x20
          (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\x20
          (\d{4})\x20
          (\d{2}):(\d{2}):(\d{2})\x20
          GMT
          \s*\z/ix =~ date
        self.rfc2822(date)
      elsif /\A\s*
             (?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\x20
             (\d\d)-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d\d)\x20
             (\d\d):(\d\d):(\d\d)\x20
             GMT
             \s*\z/ix =~ date
        year = $3.to_i
        if year < 50
          year += 2000
        else
          year += 1900
        end
        self.utc(year, $2, $1.to_i, $4.to_i, $5.to_i, $6.to_i)
      elsif /\A\s*
             (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\x20
             (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\x20
             (\d\d|\x20\d)\x20
             (\d\d):(\d\d):(\d\d)\x20
             (\d{4})
             \s*\z/ix =~ date
        self.utc($6.to_i, MonthValue[$1.upcase], $2.to_i,
                 $3.to_i, $4.to_i, $5.to_i)
      else
        raise ArgumentError.new("not RFC 2616 compliant date: #{date.inspect}")
      end
    end

    #
    # Parses +date+ as dateTime defined by XML Schema and converts it to a Time
    # object.  The format is restricted version of the format defined by ISO
    # 8601.
    #
    # ArgumentError is raised if +date+ is not compliant with the format or Time
    # class cannot represent specified date.
    #
    # See #xmlschema for more information on this format.
    #
    # time library should be required to use this method as follows.
    #
    #     require 'time'
    #
    def xmlschema(date)
      if /\A\s*
          (-?\d+)-(\d\d)-(\d\d)
          T
          (\d\d):(\d\d):(\d\d)
          (\.\d+)?
          (Z|[+-]\d\d:\d\d)?
          \s*\z/ix =~ date
        year = $1.to_i
        mon = $2.to_i
        day = $3.to_i
        hour = $4.to_i
        min = $5.to_i
        sec = $6.to_i
        usec = 0
        if $7
          usec = Rational($7) * 1000000
        end
        if $8
          zone = $8
          year, mon, day, hour, min, sec =
            apply_offset(year, mon, day, hour, min, sec, zone_offset(zone))
          self.utc(year, mon, day, hour, min, sec, usec)
        else
          self.local(year, mon, day, hour, min, sec, usec)
        end
      else
        raise ArgumentError.new("invalid date: #{date.inspect}")
      end
    end
    alias iso8601 xmlschema
  end # class << self

  #
  # Returns a string which represents the time as date-time defined by RFC 2822:
  #
  #   day-of-week, DD month-name CCYY hh:mm:ss zone
  #
  # where zone is [+-]hhmm.
  #
  # If +self+ is a UTC time, -0000 is used as zone.
  #
  # time library should be required to use this method as follows.
  #
  #     require 'time'
  #
  def rfc2822
    sprintf('%s, %02d %s %0*d %02d:%02d:%02d ',
      RFC2822_DAY_NAME[wday],
      day, RFC2822_MONTH_NAME[mon-1], year < 0 ? 5 : 4, year,
      hour, min, sec) +
    if utc?
      '-0000'
    else
      off = utc_offset
      sign = off < 0 ? '-' : '+'
      sprintf('%s%02d%02d', sign, *(off.abs / 60).divmod(60))
    end
  end
  alias rfc822 rfc2822

  RFC2822_DAY_NAME = [
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
  ]
  RFC2822_MONTH_NAME = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ]

  #
  # Returns a string which represents the time as rfc1123-date of HTTP-date
  # defined by RFC 2616:
  #
  #   day-of-week, DD month-name CCYY hh:mm:ss GMT
  #
  # Note that the result is always UTC (GMT).
  #
  # time library should be required to use this method as follows.
  #
  #     require 'time'
  #
  def httpdate
    t = dup.utc
    sprintf('%s, %02d %s %0*d %02d:%02d:%02d GMT',
      RFC2822_DAY_NAME[t.wday],
      t.day, RFC2822_MONTH_NAME[t.mon-1], t.year < 0 ? 5 : 4, t.year,
      t.hour, t.min, t.sec)
  end

  #
  # Returns a string which represents the time as dateTime defined by XML
  # Schema:
  #
  #   CCYY-MM-DDThh:mm:ssTZD
  #   CCYY-MM-DDThh:mm:ss.sssTZD
  #
  # where TZD is Z or [+-]hh:mm.
  #
  # If self is a UTC time, Z is used as TZD.  [+-]hh:mm is used otherwise.
  #
  # +fractional_seconds+ specifies a number of digits of fractional seconds.
  # Its default value is 0.
  #
  # time library should be required to use this method as follows.
  #
  #     require 'time'
  #
  def xmlschema(fraction_digits=0)
    sprintf('%0*d-%02d-%02dT%02d:%02d:%02d',
      year < 0 ? 5 : 4, year, mon, day, hour, min, sec) +
    if fraction_digits == 0
      ''
    else
      '.' + sprintf('%0*d', fraction_digits, (subsec * 10**fraction_digits).floor)
    end +
    if utc?
      'Z'
    else
      off = utc_offset
      sign = off < 0 ? '-' : '+'
      sprintf('%s%02d:%02d', sign, *(off.abs / 60).divmod(60))
    end
  end
  alias iso8601 xmlschema
end

