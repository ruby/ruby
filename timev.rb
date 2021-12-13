# Time is an abstraction of dates and times. Time is stored internally as
# the number of seconds with subsecond since the _Epoch_,
# 1970-01-01 00:00:00 UTC.
#
# The Time class treats GMT
# (Greenwich Mean Time) and UTC (Coordinated Universal Time) as equivalent.
# GMT is the older way of referring to these baseline times but persists in
# the names of calls on POSIX systems.
#
# Note: A \Time object uses the resolution available on your system clock.
#
# All times may have subsecond. Be aware of this fact when comparing times
# with each other -- times that are apparently equal when displayed may be
# different when compared.
# (Since Ruby 2.7.0, Time#inspect shows subsecond but
# Time#to_s still doesn't show subsecond.)
#
# == Examples
#
# All of these examples were done using the EST timezone which is GMT-5.
#
# === Creating a New \Time Instance
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
# Or a timezone object:
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
# === Working with an Instance of \Time
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
# First, what's elsewhere. \Class \Time:
#
# - Inherits from {class Object}[Object.html#class-Object-label-What-27s+Here].
# - Includes {module Comparable}[Comparable.html#module-Comparable-label-What-27s+Here].
#
# Here, class \Time provides methods that are useful for:
#
# - {Creating \Time objects}[#class-Time-label-Methods+for+Creating].
# - {Fetching \Time values}[#class-Time-label-Methods+for+Fetching].
# - {Querying a \Time object}[#class-Time-label-Methods+for+Querying].
# - {Comparing \Time objects}[#class-Time-label-Methods+for+Comparing].
# - {Converting a \Time object}[#class-Time-label-Methods+for+Converting].
# - {Rounding a \Time}[#class-Time-label-Methods+for+Rounding].
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
# - {-}[#method-i-2D] (minus): Returns a new time
#                              decreased by the given number of seconds.
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
# - {#<=>}[#method-i-3C-3D-3E]: Compares +self+ to another time.
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
#
# === Methods for Rounding
#
# - #round:Returns a new time with subseconds rounded.
# - #ceil: Returns a new time with subseconds raised to a ceiling.
# - #floor: Returns a new time with subseconds lowered to a floor.
#
# == Timezone Argument
#
# A timezone argument must have +local_to_utc+ and +utc_to_local+
# methods, and may have +name+, +abbr+, and +dst?+ methods.
#
# The +local_to_utc+ method should convert a Time-like object from
# the timezone to UTC, and +utc_to_local+ is the opposite.  The
# result also should be a Time or Time-like object (not necessary to
# be the same class).  The #zone of the result is just ignored.
# Time-like argument to these methods is similar to a Time object in
# UTC without subsecond; it has attribute readers for the parts,
# e.g. #year, #month, and so on, and epoch time readers, #to_i.  The
# subsecond attributes are fixed as 0, and #utc_offset, #zone,
# #isdst, and their aliases are same as a Time object in UTC.
# Also #to_time, #+, and #- methods are defined.
#
# The +name+ method is used for marshaling. If this method is not
# defined on a timezone object, Time objects using that timezone
# object can not be dumped by Marshal.
#
# The +abbr+ method is used by '%Z' in #strftime.
#
# The +dst?+ method is called with a +Time+ value and should return whether
# the +Time+ value is in daylight savings time in the zone.
#
# === Auto Conversion to Timezone
#
# At loading marshaled data, a timezone name will be converted to a timezone
# object by +find_timezone+ class method, if the method is defined.
#
# Similarly, that class method will be called when a timezone argument does
# not have the necessary methods mentioned above.
class Time
  # Creates a new \Time object from the current system time.
  # This is the same as Time.new without arguments.
  #
  #    Time.now               # => 2009-06-24 12:39:54 +0900
  #    Time.now(in: '+04:00') # => 2009-06-24 07:39:54 +0400
  #
  # Parameter:
  # :include: doc/time/in.rdoc
  def self.now(in: nil)
    new(in: Primitive.arg!(:in))
  end

  # _Time_
  #
  # This form accepts a \Time object +time+
  # and optional keyword argument +in+:
  #
  #   Time.at(Time.new)               # => 2021-04-26 08:52:31.6023486 -0500
  #   Time.at(Time.new, in: '+09:00') # => 2021-04-26 22:52:31.6023486 +0900
  #
  # _Seconds_
  #
  # This form accepts a numeric number of seconds +sec+
  # and optional keyword argument +in+:
  #
  #   Time.at(946702800)               # => 1999-12-31 23:00:00 -0600
  #   Time.at(946702800, in: '+09:00') # => 2000-01-01 14:00:00 +0900
  #
  # <em>Seconds with Subseconds and Units</em>
  #
  # This form accepts an integer number of seconds +sec_i+,
  # a numeric number of milliseconds +msec+,
  # a symbol argument for the subsecond unit type (defaulting to :usec),
  # and an optional keyword argument +in+:
  #
  #   Time.at(946702800, 500, :millisecond)               # => 1999-12-31 23:00:00.5 -0600
  #   Time.at(946702800, 500, :millisecond, in: '+09:00') # => 2000-01-01 14:00:00.5 +0900
  #   Time.at(946702800, 500000)                             # => 1999-12-31 23:00:00.5 -0600
  #   Time.at(946702800, 500000, :usec)                      # => 1999-12-31 23:00:00.5 -0600
  #   Time.at(946702800, 500000, :microsecond)               # => 1999-12-31 23:00:00.5 -0600
  #   Time.at(946702800, 500000, in: '+09:00')               # => 2000-01-01 14:00:00.5 +0900
  #   Time.at(946702800, 500000, :usec, in: '+09:00')        # => 2000-01-01 14:00:00.5 +0900
  #   Time.at(946702800, 500000, :microsecond, in: '+09:00') # => 2000-01-01 14:00:00.5 +0900
  #   Time.at(946702800, 500000000, :nsec)                     # => 1999-12-31 23:00:00.5 -0600
  #   Time.at(946702800, 500000000, :nanosecond)               # => 1999-12-31 23:00:00.5 -0600
  #   Time.at(946702800, 500000000, :nsec, in: '+09:00')       # => 2000-01-01 14:00:00.5 +0900
  #   Time.at(946702800, 500000000, :nanosecond, in: '+09:00') # => 2000-01-01 14:00:00.5 +0900
  #
  # Parameters:
  # :include: doc/time/sec_i.rdoc
  # :include: doc/time/msec.rdoc
  # :include: doc/time/usec.rdoc
  # :include: doc/time/nsec.rdoc
  # :include: doc/time/in.rdoc
  #
  def self.at(time, subsec = false, unit = :microsecond, in: nil)
    if Primitive.mandatory_only?
      Primitive.time_s_at1(time)
    else
      Primitive.time_s_at(time, subsec, unit, Primitive.arg!(:in))
    end
  end

  # Returns a new \Time object based on the given arguments.
  #
  # With no positional arguments, returns the value of Time.now:
  #
  #   Time.new                                       # => 2021-04-24 17:27:46.0512465 -0500
  #
  # Otherwise, returns a new \Time object based on the given parameters:
  #
  #   Time.new(2000)                                 # => 2000-01-01 00:00:00 -0600
  #   Time.new(2000, 12, 31, 23, 59, 59.5)           # => 2000-12-31 23:59:59.5 -0600
  #   Time.new(2000, 12, 31, 23, 59, 59.5, '+09:00') # => 2000-12-31 23:59:59.5 +0900
  #
  # Parameters:
  #
  # :include: doc/time/year.rdoc
  # :include: doc/time/mon-min.rdoc
  # :include: doc/time/sec.rdoc
  # :include: doc/time/zone_and_in.rdoc
  #
  def initialize(year = (now = true), mon = nil, mday = nil, hour = nil, min = nil, sec = nil, zone = nil, in: nil)
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

    Primitive.time_init_args(year, mon, mday, hour, min, sec, zone)
  end
end
