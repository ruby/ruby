
#
# == Introduction
# 
# This library extends the Time class:
# * conversion between date string and time object.
#   * date-time defined by RFC 2822
#   * HTTP-date defined by RFC 2616
#   * dateTime defined by XML Schema Part 2: Datatypes (ISO 8601)
#   * various formats handled by ParseDate (string to time only)
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
# == Revision Information
#
# $Id$
#

require 'parsedate'

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
      # See RFC 1123 and RFC 2822 for the error of RFC 822.
      'A' => +1, 'B' => +2, 'C' => +3, 'D' => +4,  'E' => +5,  'F' => +6, 
      'G' => +7, 'H' => +8, 'I' => +9, 'K' => +10, 'L' => +11, 'M' => +12,
      'N' => -1, 'O' => -2, 'P' => -3, 'Q' => -4,  'R' => -5,  'S' => -6, 
      'T' => -7, 'U' => -8, 'V' => -9, 'W' => -10, 'X' => -11, 'Y' => -12,
    }
    def zone_offset(zone, year=Time.now.year)
      off = nil
      zone = zone.upcase
      if /\A([+-])(\d\d):?(\d\d)\z/ =~ zone
        off = ($1 == '-' ? -1 : 1) * ($2.to_i * 60 + $3.to_i) * 60
      elsif /\A[+-]\d\d\z/ =~ zone
        off = zone.to_i * 3600
      elsif ZoneOffset.include?(zone)
        off = ZoneOffset[zone] * 3600
      elsif ((t = Time.local(year, 1, 1)).zone.upcase == zone rescue false)
        off = t.utc_offset
      elsif ((t = Time.local(year, 7, 1)).zone.upcase == zone rescue false)
        off = t.utc_offset
      end
      off
    end

    #
    # Parses +date+ using ParseDate.parsedate and converts it to a Time object.
    #
    # If a block is given, the year described in +date+ is converted by the
    # block.  For example:
    #
    #     Time.parse(...) {|y| y < 100 ? (y >= 69 ? y + 1900 : y + 2000) : y}
    #
    # If the upper components of the given time are broken or missing, they are
    # supplied with those of +now+.  For the lower components, the minimum
    # values (1 or 0) are assumed if broken or missing.  For example:
    #
    #     # Suppose it is "Thu Nov 29 14:33:20 GMT 2001" now and
    #     # your timezone is GMT:
    #     Time.parse("16:30")     #=> Thu Nov 29 16:30:00 GMT 2001
    #     Time.parse("7/23")      #=> Mon Jul 23 00:00:00 GMT 2001
    #     Time.parse("Aug 31")    #=> Fri Aug 31 00:00:00 GMT 2001
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
    # ArgumentError is raised if ParseDate cannot extract information from
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
    def parse(date, now=Time.now)
      year, mon, day, hour, min, sec, zone, _ = ParseDate.parsedate(date)
      year = yield(year) if year && block_given?

      if now
        begin
          break if year; year = now.year
          break if mon; mon = now.mon
          break if day; day = now.day
          break if hour; hour = now.hour
          break if min; min = now.min
          break if sec; sec = now.sec
        end until true
      end

      year ||= 1970
      mon ||= 1
      day ||= 1
      hour ||= 0
      min ||= 0
      sec ||= 0

      off = nil
      off = zone_offset(zone, year) if zone

      if off
        t = Time.utc(year, mon, day, hour, min, sec) - off
        t.localtime if off != 0
        t
      else
        Time.local(year, mon, day, hour, min, sec)
      end
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

        t = Time.utc(year, mon, day, hour, min, sec)
        offset = zone_offset(zone)
	t = (t - offset).localtime if offset != 0 || zone == '+0000'
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
    def httpdate(date)
      if /\A\s*
          (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),\x20
          (\d{2})\x20
          (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\x20
          (\d{4})\x20
          (\d{2}):(\d{2}):(\d{2})\x20
          GMT
          \s*\z/ix =~ date
        Time.rfc2822(date)
      elsif /\A\s*
             (?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\x20
             (\d\d)-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d\d)\x20
             (\d\d):(\d\d):(\d\d)\x20
             GMT
             \s*\z/ix =~ date
        Time.parse(date)
      elsif /\A\s*
             (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\x20
             (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\x20
             (\d\d|\x20\d)\x20
             (\d\d):(\d\d):(\d\d)\x20
             (\d{4})
             \s*\z/ix =~ date
        Time.utc($6.to_i, MonthValue[$1.upcase], $2.to_i,
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
    def xmlschema(date)
      if /\A\s*
          (-?\d+)-(\d\d)-(\d\d)
          T
          (\d\d):(\d\d):(\d\d)
          (\.\d*)?
          (Z|[+-]\d\d:\d\d)?
          \s*\z/ix =~ date
	datetime = [$1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i] 
	datetime << $7.to_f * 1000000 if $7
	if $8
	  Time.utc(*datetime) - zone_offset($8)
	else
	  Time.local(*datetime)
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
  def rfc2822
    sprintf('%s, %02d %s %d %02d:%02d:%02d ',
      RFC2822_DAY_NAME[wday],
      day, RFC2822_MONTH_NAME[mon-1], year,
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
  def httpdate
    t = dup.utc
    sprintf('%s, %02d %s %d %02d:%02d:%02d GMT',
      RFC2822_DAY_NAME[t.wday],
      t.day, RFC2822_MONTH_NAME[t.mon-1], t.year,
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
  def xmlschema(fraction_digits=0)
    sprintf('%d-%02d-%02dT%02d:%02d:%02d',
      year, mon, day, hour, min, sec) +
    if fraction_digits == 0
      ''
    elsif fraction_digits <= 6
      '.' + sprintf('%06d', usec)[0, fraction_digits]
    else
      '.' + sprintf('%06d', usec) + '0' * (fraction_digits - 6)
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

if __FILE__ == $0
  require 'test/unit'

  class TimeExtentionTest < Test::Unit::TestCase # :nodoc:
    def test_rfc822
      assert_equal(Time.utc(1976, 8, 26, 14, 30) + 4 * 3600,
                   Time.rfc2822("26 Aug 76 14:30 EDT"))
      assert_equal(Time.utc(1976, 8, 27, 9, 32) + 7 * 3600,
                   Time.rfc2822("27 Aug 76 09:32 PDT"))
    end

    def test_rfc2822
      assert_equal(Time.utc(1997, 11, 21, 9, 55, 6) + 6 * 3600,
                   Time.rfc2822("Fri, 21 Nov 1997 09:55:06 -0600"))
      assert_equal(Time.utc(2003, 7, 1, 10, 52, 37) - 2 * 3600,
                   Time.rfc2822("Tue, 1 Jul 2003 10:52:37 +0200"))
      assert_equal(Time.utc(1997, 11, 21, 10, 1, 10) + 6 * 3600,
                   Time.rfc2822("Fri, 21 Nov 1997 10:01:10 -0600"))
      assert_equal(Time.utc(1997, 11, 21, 11, 0, 0) + 6 * 3600,
                   Time.rfc2822("Fri, 21 Nov 1997 11:00:00 -0600"))
      assert_equal(Time.utc(1997, 11, 24, 14, 22, 1) + 8 * 3600,
                   Time.rfc2822("Mon, 24 Nov 1997 14:22:01 -0800"))
      begin
        Time.at(-1)
      rescue ArgumentError
        # ignore
      else
        assert_equal(Time.utc(1969, 2, 13, 23, 32, 54) + 3 * 3600 + 30 * 60,
                     Time.rfc2822("Thu, 13 Feb 1969 23:32:54 -0330"))
        assert_equal(Time.utc(1969, 2, 13, 23, 32, 0) + 3 * 3600 + 30 * 60,
                     Time.rfc2822(" Thu,
        13
          Feb
            1969
        23:32
                 -0330 (Newfoundland Time)"))
      end
      assert_equal(Time.utc(1997, 11, 21, 9, 55, 6),
                   Time.rfc2822("21 Nov 97 09:55:06 GMT"))
      assert_equal(Time.utc(1997, 11, 21, 9, 55, 6) + 6 * 3600,
                   Time.rfc2822("Fri, 21 Nov 1997 09 :   55  :  06 -0600"))
      assert_raise(ArgumentError) {
        # inner comment is not supported.
        Time.rfc2822("Fri, 21 Nov 1997 09(comment):   55  :  06 -0600")
      }
    end

    def test_rfc2616
      t = Time.utc(1994, 11, 6, 8, 49, 37)
      assert_equal(t, Time.httpdate("Sun, 06 Nov 1994 08:49:37 GMT"))
      assert_equal(t, Time.httpdate("Sunday, 06-Nov-94 08:49:37 GMT"))
      assert_equal(t, Time.httpdate("Sun Nov  6 08:49:37 1994"))
      assert_equal(Time.utc(1995, 11, 15, 6, 25, 24),
                   Time.httpdate("Wed, 15 Nov 1995 06:25:24 GMT"))
      assert_equal(Time.utc(1995, 11, 15, 4, 58, 8),
                   Time.httpdate("Wed, 15 Nov 1995 04:58:08 GMT"))
      assert_equal(Time.utc(1994, 11, 15, 8, 12, 31),
                   Time.httpdate("Tue, 15 Nov 1994 08:12:31 GMT"))
      assert_equal(Time.utc(1994, 12, 1, 16, 0, 0),
                   Time.httpdate("Thu, 01 Dec 1994 16:00:00 GMT"))
      assert_equal(Time.utc(1994, 10, 29, 19, 43, 31),
                   Time.httpdate("Sat, 29 Oct 1994 19:43:31 GMT"))
      assert_equal(Time.utc(1994, 11, 15, 12, 45, 26),
                   Time.httpdate("Tue, 15 Nov 1994 12:45:26 GMT"))
      assert_equal(Time.utc(1999, 12, 31, 23, 59, 59),
                   Time.httpdate("Fri, 31 Dec 1999 23:59:59 GMT"))
    end

    def test_rfc3339
      t = Time.utc(1985, 4, 12, 23, 20, 50, 520000)
      s = "1985-04-12T23:20:50.52Z"
      assert_equal(t, Time.iso8601(s))
      assert_equal(s, t.iso8601(2))

      t = Time.utc(1996, 12, 20, 0, 39, 57)
      s = "1996-12-19T16:39:57-08:00"
      assert_equal(t, Time.iso8601(s))
      # There is no way to generate time string with arbitrary timezone.
      s = "1996-12-20T00:39:57Z"
      assert_equal(t, Time.iso8601(s))
      assert_equal(s, t.iso8601)

      t = Time.utc(1990, 12, 31, 23, 59, 60)
      s = "1990-12-31T23:59:60Z"
      assert_equal(t, Time.iso8601(s))
      # leap second is representable only if timezone file has it.
      s = "1990-12-31T15:59:60-08:00"
      assert_equal(t, Time.iso8601(s))

      begin
        Time.at(-1)
      rescue ArgumentError
        # ignore
      else
        t = Time.utc(1937, 1, 1, 11, 40, 27, 870000)
        s = "1937-01-01T12:00:27.87+00:20"
        assert_equal(t, Time.iso8601(s))
      end
    end

    # http://www.w3.org/TR/xmlschema-2/
    def test_xmlschema
      assert_equal(Time.utc(1999, 5, 31, 13, 20, 0) + 5 * 3600,
                   Time.xmlschema("1999-05-31T13:20:00-05:00"))
      assert_equal(Time.local(2000, 1, 20, 12, 0, 0),
                   Time.xmlschema("2000-01-20T12:00:00"))
      assert_equal(Time.utc(2000, 1, 20, 12, 0, 0),
                   Time.xmlschema("2000-01-20T12:00:00Z"))
      assert_equal(Time.utc(2000, 1, 20, 12, 0, 0) - 12 * 3600,
                   Time.xmlschema("2000-01-20T12:00:00+12:00"))
      assert_equal(Time.utc(2000, 1, 20, 12, 0, 0) + 13 * 3600,
                   Time.xmlschema("2000-01-20T12:00:00-13:00"))
      assert_equal(Time.utc(2000, 3, 4, 23, 0, 0) - 3 * 3600,
                   Time.xmlschema("2000-03-04T23:00:00+03:00"))
      assert_equal(Time.utc(2000, 3, 4, 20, 0, 0),
                   Time.xmlschema("2000-03-04T20:00:00Z"))
      assert_equal(Time.local(2000, 1, 15, 0, 0, 0),
                   Time.xmlschema("2000-01-15T00:00:00"))
      assert_equal(Time.local(2000, 2, 15, 0, 0, 0),
                   Time.xmlschema("2000-02-15T00:00:00"))
      assert_equal(Time.local(2000, 1, 15, 12, 0, 0),
                   Time.xmlschema("2000-01-15T12:00:00"))
      assert_equal(Time.utc(2000, 1, 16, 12, 0, 0),
                   Time.xmlschema("2000-01-16T12:00:00Z"))
      assert_equal(Time.local(2000, 1, 1, 12, 0, 0),
                   Time.xmlschema("2000-01-01T12:00:00"))
      assert_equal(Time.utc(1999, 12, 31, 23, 0, 0),
                   Time.xmlschema("1999-12-31T23:00:00Z"))
      assert_equal(Time.local(2000, 1, 16, 12, 0, 0),
                   Time.xmlschema("2000-01-16T12:00:00"))
      assert_equal(Time.local(2000, 1, 16, 0, 0, 0),
                   Time.xmlschema("2000-01-16T00:00:00"))
      assert_equal(Time.utc(2000, 1, 12, 12, 13, 14),
                   Time.xmlschema("2000-01-12T12:13:14Z"))
      assert_equal(Time.utc(2001, 4, 17, 19, 23, 17, 300000),
		   Time.xmlschema("2001-04-17T19:23:17.3Z"))
    end

    def test_encode_xmlschema
      t = Time.utc(2001, 4, 17, 19, 23, 17, 300000)
      assert_equal("2001-04-17T19:23:17Z", t.xmlschema)
      assert_equal("2001-04-17T19:23:17.3Z", t.xmlschema(1))
      assert_equal("2001-04-17T19:23:17.300000Z", t.xmlschema(6))
      assert_equal("2001-04-17T19:23:17.3000000Z", t.xmlschema(7))

      t = Time.utc(2001, 4, 17, 19, 23, 17, 123456)
      assert_equal("2001-04-17T19:23:17.1234560Z", t.xmlschema(7))
      assert_equal("2001-04-17T19:23:17.123456Z", t.xmlschema(6))
      assert_equal("2001-04-17T19:23:17.12345Z", t.xmlschema(5))
      assert_equal("2001-04-17T19:23:17.1Z", t.xmlschema(1))

      begin
        Time.at(-1)
      rescue ArgumentError
        # ignore
      else
        t = Time.utc(1960, 12, 31, 23, 0, 0, 123456)
        assert_equal("1960-12-31T23:00:00.123456Z", t.xmlschema(6))
      end
    end

    def test_completion
      now = Time.local(2001,11,29,21,26,35)
      assert_equal(Time.local( 2001,11,29,21,12),
                   Time.parse("2001/11/29 21:12", now))
      assert_equal(Time.local( 2001,11,29),
                   Time.parse("2001/11/29", now))
      assert_equal(Time.local( 2001,11,29),
                   Time.parse(     "11/29", now))
      #assert_equal(Time.local(2001,11,1), Time.parse("Nov", now))
      assert_equal(Time.local( 2001,11,29,10,22),
                   Time.parse(           "10:22", now))
    end

    def test_invalid
      # They were actually used in some web sites.
      assert_raise(ArgumentError) { Time.httpdate("1 Dec 2001 10:23:57 GMT") }
      assert_raise(ArgumentError) { Time.httpdate("Sat, 1 Dec 2001 10:25:42 GMT") }
      assert_raise(ArgumentError) { Time.httpdate("Sat,  1-Dec-2001 10:53:55 GMT") }
      assert_raise(ArgumentError) { Time.httpdate("Saturday, 01-Dec-2001 10:15:34 GMT") }
      assert_raise(ArgumentError) { Time.httpdate("Saturday, 01-Dec-101 11:10:07 GMT") }
      assert_raise(ArgumentError) { Time.httpdate("Fri, 30 Nov 2001 21:30:00 JST") }

      # They were actually used in some mails.
      assert_raise(ArgumentError) { Time.rfc2822("01-5-20") }
      assert_raise(ArgumentError) { Time.rfc2822("7/21/00") }
      assert_raise(ArgumentError) { Time.rfc2822("2001-8-28") }
      assert_raise(ArgumentError) { Time.rfc2822("00-5-6 1:13:06") }
      assert_raise(ArgumentError) { Time.rfc2822("2001-9-27 9:36:49") }
      assert_raise(ArgumentError) { Time.rfc2822("2000-12-13 11:01:11") }
      assert_raise(ArgumentError) { Time.rfc2822("2001/10/17 04:29:55") }
      assert_raise(ArgumentError) { Time.rfc2822("9/4/2001 9:23:19 PM") }
      assert_raise(ArgumentError) { Time.rfc2822("01 Nov 2001 09:04:31") }
      assert_raise(ArgumentError) { Time.rfc2822("13 Feb 2001 16:4 GMT") }
      assert_raise(ArgumentError) { Time.rfc2822("01 Oct 00 5:41:19 PM") }
      assert_raise(ArgumentError) { Time.rfc2822("2 Jul 00 00:51:37 JST") }
      assert_raise(ArgumentError) { Time.rfc2822("01 11 2001 06:55:57 -0500") }
      assert_raise(ArgumentError) { Time.rfc2822("18 \343\366\356\341\370 2000") }
      assert_raise(ArgumentError) { Time.rfc2822("Fri, Oct 2001  18:53:32") }
      assert_raise(ArgumentError) { Time.rfc2822("Fri, 2 Nov 2001 03:47:54") }
      assert_raise(ArgumentError) { Time.rfc2822("Fri, 27 Jul 2001 11.14.14 +0200") }
      assert_raise(ArgumentError) { Time.rfc2822("Thu, 2 Nov 2000 04:13:53 -600") }
      assert_raise(ArgumentError) { Time.rfc2822("Wed, 5 Apr 2000 22:57:09 JST") }
      assert_raise(ArgumentError) { Time.rfc2822("Mon, 11 Sep 2000 19:47:33 00000") }
      assert_raise(ArgumentError) { Time.rfc2822("Fri, 28 Apr 2000 20:40:47 +-900") }
      assert_raise(ArgumentError) { Time.rfc2822("Fri, 19 Jan 2001 8:15:36 AM -0500") }
      assert_raise(ArgumentError) { Time.rfc2822("Thursday, Sep 27 2001 7:42:35 AM EST") }
      assert_raise(ArgumentError) { Time.rfc2822("3/11/2001 1:31:57 PM Pacific Daylight Time") }
      assert_raise(ArgumentError) { Time.rfc2822("Mi, 28 Mrz 2001 11:51:36") }
      assert_raise(ArgumentError) { Time.rfc2822("P, 30 sept 2001 23:03:14") }
      assert_raise(ArgumentError) { Time.rfc2822("fr, 11 aug 2000 18:39:22") }
      assert_raise(ArgumentError) { Time.rfc2822("Fr, 21 Sep 2001 17:44:03 -1000") }
      assert_raise(ArgumentError) { Time.rfc2822("Mo, 18 Jun 2001 19:21:40 -1000") }
      assert_raise(ArgumentError) { Time.rfc2822("l\366, 12 aug 2000 18:53:20") }
      assert_raise(ArgumentError) { Time.rfc2822("l\366, 26 maj 2001 00:15:58") }
      assert_raise(ArgumentError) { Time.rfc2822("Dom, 30 Sep 2001 17:36:30") }
      assert_raise(ArgumentError) { Time.rfc2822("%&, 31 %2/ 2000 15:44:47 -0500") }
      assert_raise(ArgumentError) { Time.rfc2822("dom, 26 ago 2001 03:57:07 -0300") }
      assert_raise(ArgumentError) { Time.rfc2822("ter, 04 set 2001 16:27:58 -0300") }
      assert_raise(ArgumentError) { Time.rfc2822("Wen, 3 oct 2001 23:17:49 -0400") }
      assert_raise(ArgumentError) { Time.rfc2822("Wen, 3 oct 2001 23:17:49 -0400") }
      assert_raise(ArgumentError) { Time.rfc2822("ele, 11 h: 2000 12:42:15 -0500") }
      assert_raise(ArgumentError) { Time.rfc2822("Tue, 14 Aug 2001 3:55:3 +0200") }
      assert_raise(ArgumentError) { Time.rfc2822("Fri, 25 Aug 2000 9:3:48 +0800") }
      assert_raise(ArgumentError) { Time.rfc2822("Fri, 1 Dec 2000 0:57:50 EST") }
      assert_raise(ArgumentError) { Time.rfc2822("Mon, 7 May 2001 9:39:51 +0200") }
      assert_raise(ArgumentError) { Time.rfc2822("Wed, 1 Aug 2001 16:9:15 +0200") }
      assert_raise(ArgumentError) { Time.rfc2822("Wed, 23 Aug 2000 9:17:36 +0800") }
      assert_raise(ArgumentError) { Time.rfc2822("Fri, 11 Aug 2000 10:4:42 +0800") }
      assert_raise(ArgumentError) { Time.rfc2822("Sat, 15 Sep 2001 13:22:2 +0300") }
      assert_raise(ArgumentError) { Time.rfc2822("Wed,16 \276\305\324\302 2001 20:06:25 +0800") }
      assert_raise(ArgumentError) { Time.rfc2822("Wed,7 \312\256\322\273\324\302 2001 23:47:22 +0800") }
      assert_raise(ArgumentError) { Time.rfc2822("=?iso-8859-1?Q?(=C5=DA),?= 10   2 2001 23:32:26 +0900 (JST)") }
      assert_raise(ArgumentError) { Time.rfc2822("\307\341\314\343\332\311, 30 \344\346\335\343\310\321 2001 10:01:06") }
      assert_raise(ArgumentError) { Time.rfc2822("=?iso-8859-1?Q?(=BF=E5),?= 12  =?iso-8859-1?Q?9=B7=EE?= 2001 14:52:41\n+0900 (JST)") }
    end
  end

end
