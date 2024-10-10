# A +Time+ object represents a date and time:
#
#   Time.new(2000, 1, 1, 0, 0, 0) # => 2000-01-01 00:00:00 -0600
#
# Although its value can be expressed as a single numeric
# (see {Epoch Seconds}[rdoc-ref:Time@Epoch+Seconds] below),
# it can be convenient to deal with the value by parts:
#
#   t = Time.new(-2000, 1, 1, 0, 0, 0.0)
#   # => -2000-01-01 00:00:00 -0600
#   t.year # => -2000
#   t.month # => 1
#   t.mday # => 1
#   t.hour # => 0
#   t.min # => 0
#   t.sec # => 0
#   t.subsec # => 0
#
#   t = Time.new(2000, 12, 31, 23, 59, 59.5)
#   # => 2000-12-31 23:59:59.5 -0600
#   t.year # => 2000
#   t.month # => 12
#   t.mday # => 31
#   t.hour # => 23
#   t.min # => 59
#   t.sec # => 59
#   t.subsec # => (1/2)
#
# == Epoch Seconds
#
# <i>Epoch seconds</i> is the exact number of seconds
# (including fractional subseconds) since the Unix Epoch, January 1, 1970.
#
# You can retrieve that value exactly using method Time.to_r:
#
#   Time.at(0).to_r        # => (0/1)
#   Time.at(0.999999).to_r # => (9007190247541737/9007199254740992)
#
# Other retrieval methods such as Time#to_i and Time#to_f
# may return a value that rounds or truncates subseconds.
#
# == \Time Resolution
#
# A +Time+ object derived from the system clock
# (for example, by method Time.now)
# has the resolution supported by the system.
#
# == \Time Internal Representation
#
# Time implementation uses a signed 63 bit integer, Integer, or
# Rational.
# It is a number of nanoseconds since the _Epoch_.
# The signed 63 bit integer can represent 1823-11-12 to 2116-02-20.
# When Integer or Rational is used (before 1823, after 2116, under
# nanosecond), Time works slower than when the signed 63 bit integer is used.
#
# Ruby uses the C function +localtime+ and +gmtime+ to map between the number
# and 6-tuple (year,month,day,hour,minute,second).
# +localtime+ is used for local time and "gmtime" is used for UTC.
#
# Integer and Rational has no range limit, but the localtime and
# gmtime has range limits due to the C types +time_t+ and <tt>struct tm</tt>.
# If that limit is exceeded, Ruby extrapolates the localtime function.
#
# The Time class always uses the Gregorian calendar.
# I.e. the proleptic Gregorian calendar is used.
# Other calendars, such as Julian calendar, are not supported.
#
# +time_t+ can represent 1901-12-14 to 2038-01-19 if it is 32 bit signed integer,
# -292277022657-01-27 to 292277026596-12-05 if it is 64 bit signed integer.
# However +localtime+ on some platforms doesn't supports negative +time_t+ (before 1970).
#
# <tt>struct tm</tt> has _tm_year_ member to represent years.
# (<tt>tm_year = 0</tt> means the year 1900.)
# It is defined as +int+ in the C standard.
# _tm_year_ can represent between -2147481748 to 2147485547 if +int+ is 32 bit.
#
# Ruby supports leap seconds as far as if the C function +localtime+ and
# +gmtime+ supports it.
# They use the tz database in most Unix systems.
# The tz database has timezones which supports leap seconds.
# For example, "Asia/Tokyo" doesn't support leap seconds but
# "right/Asia/Tokyo" supports leap seconds.
# So, Ruby supports leap seconds if the TZ environment variable is
# set to "right/Asia/Tokyo" in most Unix systems.
#
# == Examples
#
# All of these examples were done using the EST timezone which is GMT-5.
#
# === Creating a New +Time+ Instance
#
# You can create a new instance of Time with Time.new. This will use the
# current system time. Time.now is an alias for this. You can also
# pass parts of the time to Time.new such as year, month, minute, etc. When
# you want to construct a time this way you must pass at least a year. If you
# pass the year with nothing else time will default to January 1 of that year
# at 00:00:00 with the current system timezone. Here are some examples:
#
#   Time.new(2002)         #=> 2002-01-01 00:00:00 -0500
#   Time.new(2002, 10)     #=> 2002-10-01 00:00:00 -0500
#   Time.new(2002, 10, 31) #=> 2002-10-31 00:00:00 -0500
#
# You can pass a UTC offset:
#
#   Time.new(2002, 10, 31, 2, 2, 2, "+02:00") #=> 2002-10-31 02:02:02 +0200
#
# Or {a timezone object}[rdoc-ref:Time@Timezone+Objects]:
#
#   zone = timezone("Europe/Athens")      # Eastern European Time, UTC+2
#   Time.new(2002, 10, 31, 2, 2, 2, zone) #=> 2002-10-31 02:02:02 +0200
#
# You can also use Time.local and Time.utc to infer
# local and UTC timezones instead of using the current system
# setting.
#
# You can also create a new time using Time.at which takes the number of
# seconds (with subsecond) since the {Unix
# Epoch}[https://en.wikipedia.org/wiki/Unix_time].
#
#   Time.at(628232400) #=> 1989-11-28 00:00:00 -0500
#
# === Working with an Instance of +Time+
#
# Once you have an instance of Time there is a multitude of things you can
# do with it. Below are some examples. For all of the following examples, we
# will work on the assumption that you have done the following:
#
#   t = Time.new(1993, 02, 24, 12, 0, 0, "+09:00")
#
# Was that a monday?
#
#   t.monday? #=> false
#
# What year was that again?
#
#   t.year #=> 1993
#
# Was it daylight savings at the time?
#
#   t.dst? #=> false
#
# What's the day a year later?
#
#   t + (60*60*24*365) #=> 1994-02-24 12:00:00 +0900
#
# How many seconds was that since the Unix Epoch?
#
#   t.to_i #=> 730522800
#
# You can also do standard functions like compare two times.
#
#   t1 = Time.new(2010)
#   t2 = Time.new(2011)
#
#   t1 == t2 #=> false
#   t1 == t1 #=> true
#   t1 <  t2 #=> true
#   t1 >  t2 #=> false
#
#   Time.new(2010,10,31).between?(t1, t2) #=> true
#
# == What's Here
#
# First, what's elsewhere. \Class +Time+:
#
# - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
# - Includes {module Comparable}[rdoc-ref:Comparable@What-27s+Here].
#
# Here, class +Time+ provides methods that are useful for:
#
# - {Creating Time objects}[rdoc-ref:Time@Methods+for+Creating].
# - {Fetching Time values}[rdoc-ref:Time@Methods+for+Fetching].
# - {Querying a Time object}[rdoc-ref:Time@Methods+for+Querying].
# - {Comparing Time objects}[rdoc-ref:Time@Methods+for+Comparing].
# - {Converting a Time object}[rdoc-ref:Time@Methods+for+Converting].
# - {Rounding a Time}[rdoc-ref:Time@Methods+for+Rounding].
#
# === Methods for Creating
#
# - ::new: Returns a new time from specified arguments (year, month, etc.),
#   including an optional timezone value.
# - ::local (aliased as ::mktime): Same as ::new, except the
#   timezone is the local timezone.
# - ::utc (aliased as ::gm): Same as ::new, except the timezone is UTC.
# - ::at: Returns a new time based on seconds since epoch.
# - ::now: Returns a new time based on the current system time.
# - #+ (plus): Returns a new time increased by the given number of seconds.
# - #- (minus): Returns a new time decreased by the given number of seconds.
#
# === Methods for Fetching
#
# - #year: Returns the year of the time.
# - #month (aliased as #mon): Returns the month of the time.
# - #mday (aliased as #day): Returns the day of the month.
# - #hour: Returns the hours value for the time.
# - #min: Returns the minutes value for the time.
# - #sec: Returns the seconds value for the time.
# - #usec (aliased as #tv_usec): Returns the number of microseconds
#   in the subseconds value of the time.
# - #nsec (aliased as #tv_nsec: Returns the number of nanoseconds
#   in the subsecond part of the time.
# - #subsec: Returns the subseconds value for the time.
# - #wday: Returns the integer weekday value of the time (0 == Sunday).
# - #yday: Returns the integer yearday value of the time (1 == January 1).
# - #hash: Returns the integer hash value for the time.
# - #utc_offset (aliased as #gmt_offset and #gmtoff): Returns the offset
#   in seconds between time and UTC.
# - #to_f: Returns the float number of seconds since epoch for the time.
# - #to_i (aliased as #tv_sec): Returns the integer number of seconds since epoch
#   for the time.
# - #to_r: Returns the Rational number of seconds since epoch for the time.
# - #zone: Returns a string representation of the timezone of the time.
#
# === Methods for Querying
#
# - #utc? (aliased as #gmt?): Returns whether the time is UTC.
# - #dst? (aliased as #isdst): Returns whether the time is DST (daylight saving time).
# - #sunday?: Returns whether the time is a Sunday.
# - #monday?: Returns whether the time is a Monday.
# - #tuesday?: Returns whether the time is a Tuesday.
# - #wednesday?: Returns whether the time is a Wednesday.
# - #thursday?: Returns whether the time is a Thursday.
# - #friday?: Returns whether time is a Friday.
# - #saturday?: Returns whether the time is a Saturday.
#
# === Methods for Comparing
#
# - #<=>: Compares +self+ to another time.
# - #eql?: Returns whether the time is equal to another time.
#
# === Methods for Converting
#
# - #asctime (aliased as #ctime): Returns the time as a string.
# - #inspect: Returns the time in detail as a string.
# - #strftime: Returns the time as a string, according to a given format.
# - #to_a: Returns a 10-element array of values from the time.
# - #to_s: Returns a string representation of the time.
# - #getutc (aliased as #getgm): Returns a new time converted to UTC.
# - #getlocal: Returns a new time converted to local time.
# - #utc (aliased as #gmtime): Converts time to UTC in place.
# - #localtime: Converts time to local time in place.
# - #deconstruct_keys: Returns a hash of time components used in pattern-matching.
#
# === Methods for Rounding
#
# - #round:Returns a new time with subseconds rounded.
# - #ceil: Returns a new time with subseconds raised to a ceiling.
# - #floor: Returns a new time with subseconds lowered to a floor.
#
# For the forms of argument +zone+, see
# {Timezone Specifiers}[rdoc-ref:Time@Timezone+Specifiers].
#
# :include: doc/_timezones.rdoc
class Time
  # Creates a new +Time+ object from the current system time.
  # This is the same as Time.new without arguments.
  #
  #    Time.now               # => 2009-06-24 12:39:54 +0900
  #    Time.now(in: '+04:00') # => 2009-06-24 07:39:54 +0400
  #
  # For forms of argument +zone+, see
  # {Timezone Specifiers}[rdoc-ref:Time@Timezone+Specifiers].
  def self.now(in: nil)
    Primitive.time_s_now(Primitive.arg!(:in))
  end

  # Returns a new +Time+ object based on the given arguments.
  #
  # Required argument +time+ may be either of:
  #
  # - A +Time+ object, whose value is the basis for the returned time;
  #   also influenced by optional keyword argument +in:+ (see below).
  # - A numeric number of
  #   {Epoch seconds}[rdoc-ref:Time@Epoch+Seconds]
  #   for the returned time.
  #
  # Examples:
  #
  #   t = Time.new(2000, 12, 31, 23, 59, 59) # => 2000-12-31 23:59:59 -0600
  #   secs = t.to_i                          # => 978328799
  #   Time.at(secs)                          # => 2000-12-31 23:59:59 -0600
  #   Time.at(secs + 0.5)                    # => 2000-12-31 23:59:59.5 -0600
  #   Time.at(1000000000)                    # => 2001-09-08 20:46:40 -0500
  #   Time.at(0)                             # => 1969-12-31 18:00:00 -0600
  #   Time.at(-1000000000)                   # => 1938-04-24 17:13:20 -0500
  #
  # Optional numeric argument +subsec+ and optional symbol argument +units+
  # work together to specify subseconds for the returned time;
  # argument +units+ specifies the units for +subsec+:
  #
  # - +:millisecond+: +subsec+ in milliseconds:
  #
  #     Time.at(secs, 0, :millisecond)     # => 2000-12-31 23:59:59 -0600
  #     Time.at(secs, 500, :millisecond)   # => 2000-12-31 23:59:59.5 -0600
  #     Time.at(secs, 1000, :millisecond)  # => 2001-01-01 00:00:00 -0600
  #     Time.at(secs, -1000, :millisecond) # => 2000-12-31 23:59:58 -0600
  #
  # - +:microsecond+ or +:usec+: +subsec+ in microseconds:
  #
  #     Time.at(secs, 0, :microsecond)        # => 2000-12-31 23:59:59 -0600
  #     Time.at(secs, 500000, :microsecond)   # => 2000-12-31 23:59:59.5 -0600
  #     Time.at(secs, 1000000, :microsecond)  # => 2001-01-01 00:00:00 -0600
  #     Time.at(secs, -1000000, :microsecond) # => 2000-12-31 23:59:58 -0600
  #
  # - +:nanosecond+ or +:nsec+: +subsec+ in nanoseconds:
  #
  #     Time.at(secs, 0, :nanosecond)           # => 2000-12-31 23:59:59 -0600
  #     Time.at(secs, 500000000, :nanosecond)   # => 2000-12-31 23:59:59.5 -0600
  #     Time.at(secs, 1000000000, :nanosecond)  # => 2001-01-01 00:00:00 -0600
  #     Time.at(secs, -1000000000, :nanosecond) # => 2000-12-31 23:59:58 -0600
  #
  #
  # Optional keyword argument <tt>in: zone</tt> specifies the timezone
  # for the returned time:
  #
  #   Time.at(secs, in: '+12:00') # => 2001-01-01 17:59:59 +1200
  #   Time.at(secs, in: '-12:00') # => 2000-12-31 17:59:59 -1200
  #
  # For the forms of argument +zone+, see
  # {Timezone Specifiers}[rdoc-ref:Time@Timezone+Specifiers].
  #
  def self.at(time, subsec = false, unit = :microsecond, in: nil)
    if Primitive.mandatory_only?
      Primitive.time_s_at1(time)
    else
      Primitive.time_s_at(time, subsec, unit, Primitive.arg!(:in))
    end
  end

  # call-seq:
  #   Time.new(year = nil, mon = nil, mday = nil, hour = nil, min = nil, sec = nil, zone = nil, in: nil, precision: 9)
  #
  # Returns a new +Time+ object based on the given arguments,
  # by default in the local timezone.
  #
  # With no positional arguments, returns the value of Time.now:
  #
  #   Time.new # => 2021-04-24 17:27:46.0512465 -0500
  #
  # With one string argument that represents a time, returns a new
  # +Time+ object based on the given argument, in the local timezone.
  #
  #   Time.new('2000-12-31 23:59:59.5')              # => 2000-12-31 23:59:59.5 -0600
  #   Time.new('2000-12-31 23:59:59.5 +0900')        # => 2000-12-31 23:59:59.5 +0900
  #   Time.new('2000-12-31 23:59:59.5', in: '+0900') # => 2000-12-31 23:59:59.5 +0900
  #   Time.new('2000-12-31 23:59:59.5')              # => 2000-12-31 23:59:59.5 -0600
  #   Time.new('2000-12-31 23:59:59.56789', precision: 3) # => 2000-12-31 23:59:59.567 -0600
  #
  # With one to six arguments, returns a new +Time+ object
  # based on the given arguments, in the local timezone.
  #
  #   Time.new(2000, 1, 2, 3, 4, 5) # => 2000-01-02 03:04:05 -0600
  #
  # For the positional arguments (other than +zone+):
  #
  # - +year+: Year, with no range limits:
  #
  #     Time.new(999999999)  # => 999999999-01-01 00:00:00 -0600
  #     Time.new(-999999999) # => -999999999-01-01 00:00:00 -0600
  #
  # - +month+: Month in range (1..12), or case-insensitive
  #   3-letter month name:
  #
  #     Time.new(2000, 1)     # => 2000-01-01 00:00:00 -0600
  #     Time.new(2000, 12)    # => 2000-12-01 00:00:00 -0600
  #     Time.new(2000, 'jan') # => 2000-01-01 00:00:00 -0600
  #     Time.new(2000, 'JAN') # => 2000-01-01 00:00:00 -0600
  #
  # - +mday+: Month day in range(1..31):
  #
  #     Time.new(2000, 1, 1)  # => 2000-01-01 00:00:00 -0600
  #     Time.new(2000, 1, 31) # => 2000-01-31 00:00:00 -0600
  #
  # - +hour+: Hour in range (0..23), or 24 if +min+, +sec+, and +usec+
  #   are zero:
  #
  #     Time.new(2000, 1, 1, 0)  # => 2000-01-01 00:00:00 -0600
  #     Time.new(2000, 1, 1, 23) # => 2000-01-01 23:00:00 -0600
  #     Time.new(2000, 1, 1, 24) # => 2000-01-02 00:00:00 -0600
  #
  # - +min+: Minute in range (0..59):
  #
  #     Time.new(2000, 1, 1, 0, 0)  # => 2000-01-01 00:00:00 -0600
  #     Time.new(2000, 1, 1, 0, 59) # => 2000-01-01 00:59:00 -0600
  #
  # - +sec+: Second in range (0...61):
  #
  #     Time.new(2000, 1, 1, 0, 0, 0)  # => 2000-01-01 00:00:00 -0600
  #     Time.new(2000, 1, 1, 0, 0, 59) # => 2000-01-01 00:00:59 -0600
  #     Time.new(2000, 1, 1, 0, 0, 60) # => 2000-01-01 00:01:00 -0600
  #
  #   +sec+ may be Float or Rational.
  #
  #     Time.new(2000, 1, 1, 0, 0, 59.5)  # => 2000-12-31 23:59:59.5 +0900
  #     Time.new(2000, 1, 1, 0, 0, 59.7r) # => 2000-12-31 23:59:59.7 +0900
  #
  # These values may be:
  #
  # - Integers, as above.
  # - Numerics convertible to integers:
  #
  #     Time.new(Float(0.0), Rational(1, 1), 1.0, 0.0, 0.0, 0.0)
  #     # => 0000-01-01 00:00:00 -0600
  #
  # - String integers:
  #
  #     a = %w[0 1 1 0 0 0]
  #     # => ["0", "1", "1", "0", "0", "0"]
  #     Time.new(*a) # => 0000-01-01 00:00:00 -0600
  #
  # When positional argument +zone+ or keyword argument +in:+ is given,
  # the new +Time+ object is in the specified timezone.
  # For the forms of argument +zone+, see
  # {Timezone Specifiers}[rdoc-ref:Time@Timezone+Specifiers]:
  #
  #   Time.new(2000, 1, 1, 0, 0, 0, '+12:00')
  #   # => 2000-01-01 00:00:00 +1200
  #   Time.new(2000, 1, 1, 0, 0, 0, in: '-12:00')
  #   # => 2000-01-01 00:00:00 -1200
  #   Time.new(in: '-12:00')
  #   # => 2022-08-23 08:49:26.1941467 -1200
  #
  # Since +in:+ keyword argument just provides the default, so if the
  # first argument in single string form contains time zone information,
  # this keyword argument will be silently ignored.
  #
  #   Time.new('2000-01-01 00:00:00 +0100', in: '-0500').utc_offset  # => 3600
  #
  # - +precision+: maximum effective digits in sub-second part, default is 9.
  #   More digits will be truncated, as other operations of +Time+.
  #   Ignored unless the first argument is a string.
  #
  def initialize(year = (now = true), mon = (str = year; nil), mday = nil, hour = nil, min = nil, sec = nil, zone = nil,
                 in: nil, precision: 9)
    if zone
      if Primitive.arg!(:in)
        raise ArgumentError, "timezone argument given as positional and keyword arguments"
      end
    else
      zone = Primitive.arg!(:in)
    end

    if now
      return Primitive.time_init_now(zone)
    end

    if str and Primitive.time_init_parse(str, zone, precision)
      return self
    end

    Primitive.time_init_args(year, mon, mday, hour, min, sec, zone)
  end
end
