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
  #    Time.new -> new_time
  #    Time.new(year, month=nil, day=nil, hour=nil, min=nil, sec_with_frac=nil, tz=nil) -> new_time
  #    Time.new(year, month=nil, day=nil, hour=nil, min=nil, sec_with_frac=nil, in: tz) -> new_time
  #
  # Returns a new \Time object based the on given arguments.
  #
  # In the first form (no arguments), returns the value of Time.local:
  #
  #   Time.new                                       # => 2021-04-24 17:27:46.0512465 -0500
  #
  # In the second form, argument +year+ is required and argument +tz+ is optional:
  #
  #   Time.new(2000)                                 # => 2000-01-01 00:00:00 -0600
  #   Time.new(2000, 12, 31, 23, 59, 59.5)           # => 2000-12-31 23:59:59.5 -0600
  #   Time.new(2000, 12, 31, 23, 59, 59.5, '+09:00') # => 2000-12-31 23:59:59.5 +0900
  #
  # In the third form, argument +year+ is required, argument +tz+ is forbidden,
  # and keyword argument <tt>in: tz</tt> is required:
  #   Time.new(2000, in: '+09:00')                   # => 2000-01-01 00:00:00 +0900
  #   Time.new(2000, 12, 31, 23, 59, 59.5, in: 'A')  # => 2000-12-31 23:59:59.5 +0100
  #
  # Parameters:
  #
  # :include: doc/time/year.rdoc
  # :include: doc/time/mon-sec_with_frac.rdoc
  # :include: doc/time/tz.rdoc
  #
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
