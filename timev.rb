# Creates a new \Time object from the current system time.
# This is the same as Time.new without arguments.
#
#    Time.now               # => 2009-06-24 12:39:54 +0900
#    Time.now(in: '+04:00') # => 2021-04-30 01:56:44 +0400
#
# Parameter:
# :include: doc/time/in.rdoc
def Time.now(in: nil)
  new(in: __builtin.arg!(:in))
end

# _Time_
#
# This form accepts a \Time object +time+
# and optional keyword argument +in+:
#
#   Time.at(Time.new)               # => 2021-04-26 08:52:31.6023486 -0500
#   Time.at(Time.new, in: '+09:00') # => 2021-04-26 22:52:32.1480341 +0900
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
def Time.at(time, subsec = (nosubsec = true), unit = (nounit = true), in: nil)
  __builtin.time_s_at(time, subsec, unit, __builtin.arg!(:in), nosubsec, nounit)
end

class Time
  # Returns a new \Time object based the on given arguments.
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
  # :include: doc/time/in.rdoc
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
