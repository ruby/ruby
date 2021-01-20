#
# call-seq:
#    Time.now -> time
#
# Creates a new Time object for the current time.
# This is the same as Time.new without arguments.
#
#    Time.now            #=> 2009-06-24 12:39:54 +0900
def Time.now(in: nil)
  new(in: __builtin.arg!(:in))
end

#
# call-seq:
#    Time.at(time) -> time
#    Time.at(seconds_with_frac) -> time
#    Time.at(seconds, microseconds_with_frac) -> time
#    Time.at(seconds, milliseconds, :millisecond) -> time
#    Time.at(seconds, microseconds, :usec) -> time
#    Time.at(seconds, microseconds, :microsecond) -> time
#    Time.at(seconds, nanoseconds, :nsec) -> time
#    Time.at(seconds, nanoseconds, :nanosecond) -> time
#    Time.at(time, in: tz) -> time
#    Time.at(seconds_with_frac, in: tz) -> time
#    Time.at(seconds, microseconds_with_frac, in: tz) -> time
#    Time.at(seconds, milliseconds, :millisecond, in: tz) -> time
#    Time.at(seconds, microseconds, :usec, in: tz) -> time
#    Time.at(seconds, microseconds, :microsecond, in: tz) -> time
#    Time.at(seconds, nanoseconds, :nsec, in: tz) -> time
#    Time.at(seconds, nanoseconds, :nanosecond, in: tz) -> time
#
# Creates a new Time object with the value given by +time+,
# the given number of +seconds_with_frac+, or
# +seconds+ and +microseconds_with_frac+ since the Epoch.
# +seconds_with_frac+ and +microseconds_with_frac+
# can be an Integer, Float, Rational, or other Numeric.
#
# If +in+ argument is given, the result is in that timezone or UTC offset, or
# if a numeric argument is given, the result is in local time.
# The +in+ argument accepts the same types of arguments as +tz+ argument of
# Time.new: string, number of seconds, or a timezone object.
#
#
#    Time.at(0)                                #=> 1969-12-31 18:00:00 -0600
#    Time.at(Time.at(0))                       #=> 1969-12-31 18:00:00 -0600
#    Time.at(946702800)                        #=> 1999-12-31 23:00:00 -0600
#    Time.at(-284061600)                       #=> 1960-12-31 00:00:00 -0600
#    Time.at(946684800.2).usec                 #=> 200000
#    Time.at(946684800, 123456.789).nsec       #=> 123456789
#    Time.at(946684800, 123456789, :nsec).nsec #=> 123456789
#
#    Time.at(1582721899, in: "+09:00")         #=> 2020-02-26 21:58:19 +0900
#    Time.at(1582721899, in: "UTC")            #=> 2020-02-26 12:58:19 UTC
#    Time.at(1582721899, in: "C")              #=> 2020-02-26 13:58:19 +0300
#    Time.at(1582721899, in: 32400)            #=> 2020-02-26 21:58:19 +0900
#
#    require 'tzinfo'
#    Time.at(1582721899, in: TZInfo::Timezone.get('Europe/Kiev'))
#                                              #=> 2020-02-26 14:58:19 +0200
def Time.at(time, subsec = (nosubsec = true), unit = (nounit = true), in: nil)
  __builtin.time_s_at(time, subsec, unit, __builtin.arg!(:in), nosubsec, nounit)
end

class Time
  # call-seq:
  #    Time.new -> time
  #    Time.new(year, month=nil, day=nil, hour=nil, min=nil, sec=nil, tz=nil) -> time
  #    Time.new(year, month=nil, day=nil, hour=nil, min=nil, sec=nil, in: tz) -> time
  #
  # Returns a Time object.
  #
  # It is initialized to the current system time if no argument is given.
  #
  # *Note:* The new object will use the resolution available on your
  # system clock, and may include subsecond.
  #
  # If one or more arguments are specified, the time is initialized to the
  # specified time.
  #
  # +sec+ may have subsecond if it is a rational.
  #
  # +tz+ specifies the timezone.
  # It can be an offset from UTC, given either as a string such as "+09:00"
  # or a single letter "A".."Z" excluding "J" (so-called military time zone),
  # or as a number of seconds such as 32400.
  # Or it can be a timezone object,
  # see {Timezone argument}[#class-Time-label-Timezone+argument] for details.
  #
  #    a = Time.new      #=> 2020-07-21 01:27:44.917547285 +0900
  #    b = Time.new      #=> 2020-07-21 01:27:44.917617713 +0900
  #    a == b            #=> false
  #    "%.6f" % a.to_f   #=> "1595262464.917547"
  #    "%.6f" % b.to_f   #=> "1595262464.917618"
  #
  #    Time.new(2008,6,21, 13,30,0, "+09:00") #=> 2008-06-21 13:30:00 +0900
  #
  #    # A trip for RubyConf 2007
  #    t1 = Time.new(2007,11,1,15,25,0, "+09:00") # JST (Narita)
  #    t2 = Time.new(2007,11,1,12, 5,0, "-05:00") # CDT (Minneapolis)
  #    t3 = Time.new(2007,11,1,13,25,0, "-05:00") # CDT (Minneapolis)
  #    t4 = Time.new(2007,11,1,16,53,0, "-04:00") # EDT (Charlotte)
  #    t5 = Time.new(2007,11,5, 9,24,0, "-05:00") # EST (Charlotte)
  #    t6 = Time.new(2007,11,5,11,21,0, "-05:00") # EST (Detroit)
  #    t7 = Time.new(2007,11,5,13,45,0, "-05:00") # EST (Detroit)
  #    t8 = Time.new(2007,11,6,17,10,0, "+09:00") # JST (Narita)
  #    (t2-t1)/3600.0                             #=> 10.666666666666666
  #    (t4-t3)/3600.0                             #=> 2.466666666666667
  #    (t6-t5)/3600.0                             #=> 1.95
  #    (t8-t7)/3600.0                             #=> 13.416666666666666
  def initialize(year = (now = true), mon = nil, mday = nil, hour = nil, min = nil, sec = nil, zone = nil, in: nil)
    if zone
      if __builtin.arg!(:in)
        raise ArgumentError, "timezone argument given as positional and keyword arguments"
      end
    else
      zone = __builtin.arg!(:in)
    end

    if now
      return __builtin.time_init_now(zone)
    end

    __builtin.time_init_args(year, mon, mday, hour, min, sec, zone)
  end
end
