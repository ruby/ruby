#
# date.rb - date and time library
#
# Author: Tadayoshi Funaba 1998-2010
#
# Documentation: William Webber <william@williamwebber.com>
#
#--
# $Id: date.rb,v 2.37 2008-01-17 20:16:31+09 tadf Exp $
#++
#
# == Overview
#
# This file provides two classes for working with
# dates and times.
#
# The first class, Date, represents dates.
# It works with years, months, weeks, and days.
# See the Date class documentation for more details.
#
# The second, DateTime, extends Date to include hours,
# minutes, seconds, and fractions of a second.  It
# provides basic support for time zones.  See the
# DateTime class documentation for more details.
#
# === Ways of calculating the date.
#
# In common usage, the date is reckoned in years since or
# before the Common Era (CE/BCE, also known as AD/BC), then
# as a month and day-of-the-month within the current year.
# This is known as the *Civil* *Date*, and abbreviated
# as +civil+ in the Date class.
#
# Instead of year, month-of-the-year,  and day-of-the-month,
# the date can also be reckoned in terms of year and
# day-of-the-year.  This is known as the *Ordinal* *Date*,
# and is abbreviated as +ordinal+ in the Date class.  (Note
# that referring to this as the Julian date is incorrect.)
#
# The date can also be reckoned in terms of year, week-of-the-year,
# and day-of-the-week.  This is known as the *Commercial*
# *Date*, and is abbreviated as +commercial+ in the
# Date class.  The commercial week runs Monday (day-of-the-week
# 1) to Sunday (day-of-the-week 7), in contrast to the civil
# week which runs Sunday (day-of-the-week 0) to Saturday
# (day-of-the-week 6).  The first week of the commercial year
# starts on the Monday on or before January 1, and the commercial
# year itself starts on this Monday, not January 1.
#
# For scientific purposes, it is convenient to refer to a date
# simply as a day count, counting from an arbitrary initial
# day.  The date first chosen for this was January 1, 4713 BCE.
# A count of days from this date is the *Julian* *Day* *Number*
# or *Julian* *Date*, which is abbreviated as +jd+ in the
# Date class.  This is in local time, and counts from midnight
# on the initial day.  The stricter usage is in UTC, and counts
# from midday on the initial day.  This is referred to in the
# Date class as the *Astronomical* *Julian* *Day* *Number*, and
# abbreviated as +ajd+.  In the Date class, the Astronomical
# Julian Day Number includes fractional days.
#
# Another absolute day count is the *Modified* *Julian* *Day*
# *Number*, which takes November 17, 1858 as its initial day.
# This is abbreviated as +mjd+ in the Date class.  There
# is also an *Astronomical* *Modified* *Julian* *Day* *Number*,
# which is in UTC and includes fractional days.  This is
# abbreviated as +amjd+ in the Date class.  Like the Modified
# Julian Day Number (and unlike the Astronomical Julian
# Day Number), it counts from midnight.
#
# Alternative calendars such as the Ethiopic Solar Calendar,
# the Islamic Lunar Calendar, or the French Revolutionary Calendar
# are not supported by the Date class; nor are calendars that
# are based on an Era different from the Common Era, such as
# the Japanese Era.
#
# === Calendar Reform
#
# The standard civil year is 365 days long.  However, the
# solar year is fractionally longer than this.  To account
# for this, a *leap* *year* is occasionally inserted.  This
# is a year with 366 days, the extra day falling on February 29.
# In the early days of the civil calendar, every fourth
# year without exception was a leap year.  This way of
# reckoning leap years is the *Julian* *Calendar*.
#
# However, the solar year is marginally shorter than 365 1/4
# days, and so the *Julian* *Calendar* gradually ran slow
# over the centuries.  To correct this, every 100th year
# (but not every 400th year) was excluded as a leap year.
# This way of reckoning leap years, which we use today, is
# the *Gregorian* *Calendar*.
#
# The Gregorian Calendar was introduced at different times
# in different regions.  The day on which it was introduced
# for a particular region is the *Day* *of* *Calendar*
# *Reform* for that region.  This is abbreviated as +sg+
# (for Start of Gregorian calendar) in the Date class.
#
# Two such days are of particular
# significance.  The first is October 15, 1582, which was
# the Day of Calendar Reform for Italy and most Catholic
# countries.  The second is September 14, 1752, which was
# the Day of Calendar Reform for England and its colonies
# (including what is now the United States).  These two
# dates are available as the constants Date::ITALY and
# Date::ENGLAND, respectively.  (By comparison, Germany and
# Holland, less Catholic than Italy but less stubborn than
# England, changed over in 1698; Sweden in 1753; Russia not
# till 1918, after the Revolution; and Greece in 1923.  Many
# Orthodox churches still use the Julian Calendar.  A complete
# list of Days of Calendar Reform can be found at
# http://www.polysyllabic.com/GregConv.html.)
#
# Switching from the Julian to the Gregorian calendar
# involved skipping a number of days to make up for the
# accumulated lag, and the later the switch was (or is)
# done, the more days need to be skipped.  So in 1582 in Italy,
# 4th October was followed by 15th October, skipping 10 days; in 1752
# in England, 2nd September was followed by 14th September, skipping
# 11 days; and if I decided to switch from Julian to Gregorian
# Calendar this midnight, I would go from 27th July 2003 (Julian)
# today to 10th August 2003 (Gregorian) tomorrow, skipping
# 13 days.  The Date class is aware of this gap, and a supposed
# date that would fall in the middle of it is regarded as invalid.
#
# The Day of Calendar Reform is relevant to all date representations
# involving years.  It is not relevant to the Julian Day Numbers,
# except for converting between them and year-based representations.
#
# In the Date and DateTime classes, the Day of Calendar Reform or
# +sg+ can be specified a number of ways.  First, it can be as
# the Julian Day Number of the Day of Calendar Reform.  Second,
# it can be using the constants Date::ITALY or Date::ENGLAND; these
# are in fact the Julian Day Numbers of the Day of Calendar Reform
# of the respective regions.  Third, it can be as the constant
# Date::JULIAN, which means to always use the Julian Calendar.
# Finally, it can be as the constant Date::GREGORIAN, which means
# to always use the Gregorian Calendar.
#
# Note: in the Julian Calendar, New Years Day was March 25.  The
# Date class does not follow this convention.
#
# === Offsets
#
# DateTime objects support a simple representation
# of offsets.  Offsets are represented as an offset
# from UTC (UTC is not identical GMT; GMT is a historical term),
# as a fraction of a day.  This offset is the
# how much local time is later (or earlier) than UTC.
# As you travel east, the offset increases until you
# reach the dateline in the middle of the Pacific Ocean;
# as you travel west, the offset decreases.  This offset
# is abbreviated as +of+ in the Date class.
#
# This simple representation of offsets does not take
# into account the common practice of Daylight Savings
# Time or Summer Time.
#
# Most DateTime methods return the date and the
# time in local time.  The two exceptions are
# #ajd() and #amjd(), which return the date and time
# in UTC time, including fractional days.
#
# The Date class does not support offsets, in that
# there is no way to create a Date object with non-utc offset.
#
# == Examples of use
#
# === Print out the date of every Sunday between two dates.
#
#     def print_sundays(d1, d2)
#         d1 += 1 until d1.sunday?
#         d1.step(d2, 7) do |d|
#             puts d.strftime('%B %-d')
#         end
#     end
#
#     print_sundays(Date.new(2003, 4, 8), Date.new(2003, 5, 23))

require 'date/format'

# Class representing a date.
#
# See the documentation to the file date.rb for an overview.
#
# Internally, the date is represented as an Astronomical
# Julian Day Number, +ajd+.  The Day of Calendar Reform, +sg+, is
# also stored, for conversions to other date formats.  (There
# is also an +of+ field for a time zone offset, but this
# is only for the use of the DateTime subclass.)
#
# A new Date object is created using one of the object creation
# class methods named after the corresponding date format, and the
# arguments appropriate to that date format; for instance,
# Date::civil() (aliased to Date::new()) with year, month,
# and day-of-month, or Date::ordinal() with year and day-of-year.
# All of these object creation class methods also take the
# Day of Calendar Reform as an optional argument.
#
# Date objects are immutable once created.
#
# Once a Date has been created, date values
# can be retrieved for the different date formats supported
# using instance methods.  For instance, #mon() gives the
# Civil month, #cwday() gives the Commercial day of the week,
# and #yday() gives the Ordinal day of the year.  Date values
# can be retrieved in any format, regardless of what format
# was used to create the Date instance.
#
# The Date class includes the Comparable module, allowing
# date objects to be compared and sorted, ranges of dates
# to be created, and so forth.
class Date

  include Comparable

  # Full month names, in English.  Months count from 1 to 12; a
  # month's numerical representation indexed into this array
  # gives the name of that month (hence the first element is nil).
  MONTHNAMES = [nil] + %w(January February March April May June July
			  August September October November December)

  # Full names of days of the week, in English.  Days of the week
  # count from 0 to 6 (except in the commercial week); a day's numerical
  # representation indexed into this array gives the name of that day.
  DAYNAMES = %w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)

  # Abbreviated month names, in English.
  ABBR_MONTHNAMES = [nil] + %w(Jan Feb Mar Apr May Jun
			       Jul Aug Sep Oct Nov Dec)

  # Abbreviated day names, in English.
  ABBR_DAYNAMES = %w(Sun Mon Tue Wed Thu Fri Sat)

  [MONTHNAMES, DAYNAMES, ABBR_MONTHNAMES, ABBR_DAYNAMES].each do |xs|
    xs.each{|x| x.freeze unless x.nil?}.freeze
  end

  # now only for marshal dumped
  class Infinity < Numeric # :nodoc:

    include Comparable

    def initialize(d=1) @d = d <=> 0 end

    def d() @d end

    protected :d

    def zero? () false end
    def finite? () false end
    def infinite? () d.nonzero? end
    def nan? () d.zero? end

    def abs() self.class.new end

    def -@ () self.class.new(-d) end
    def +@ () self.class.new(+d) end

    def <=> (other)
      case other
      when Infinity; return d <=> other.d
      when Numeric; return d
      else
	begin
	  l, r = other.coerce(self)
	  return l <=> r
	rescue NoMethodError
	end
      end
      nil
    end

    def coerce(other)
      case other
      when Numeric; return -d, d
      else
	super
      end
    end

  end

  # The Julian Day Number of the Day of Calendar Reform for Italy
  # and the Catholic countries.
  ITALY     = 2299161 # 1582-10-15

  # The Julian Day Number of the Day of Calendar Reform for England
  # and her Colonies.
  ENGLAND   = 2361222 # 1752-09-14

  # A constant used to indicate that a Date should always use the
  # Julian calendar.
  JULIAN    =  Float::INFINITY

  # A constant used to indicate that a Date should always use the
  # Gregorian calendar.
  GREGORIAN = -Float::INFINITY

  HALF_DAYS_IN_DAY       = Rational(1, 2) # :nodoc:
  HOURS_IN_DAY           = Rational(1, 24) # :nodoc:
  MINUTES_IN_DAY         = Rational(1, 1440) # :nodoc:
  SECONDS_IN_DAY         = Rational(1, 86400) # :nodoc:
  MILLISECONDS_IN_DAY    = Rational(1, 86400*10**3) # :nodoc:
  NANOSECONDS_IN_DAY     = Rational(1, 86400*10**9) # :nodoc:
  MILLISECONDS_IN_SECOND = Rational(1, 10**3) # :nodoc:
  NANOSECONDS_IN_SECOND  = Rational(1, 10**9) # :nodoc:

  MJD_EPOCH_IN_AJD       = Rational(4800001, 2) # 1858-11-17 # :nodoc:
  UNIX_EPOCH_IN_AJD      = Rational(4881175, 2) # 1970-01-01 # :nodoc:
  MJD_EPOCH_IN_CJD       = 2400001 # :nodoc:
  UNIX_EPOCH_IN_CJD      = 2440588 # :nodoc:
  LD_EPOCH_IN_CJD        = 2299160 # :nodoc:

  t = Module.new do

    private

    def find_fdoy(y, sg) # :nodoc:
      j = nil
      1.upto(31) do |d|
	break if j = _valid_civil?(y, 1, d, sg)
      end
      j
    end

    def find_ldoy(y, sg) # :nodoc:
      j = nil
      31.downto(1) do |d|
	break if j = _valid_civil?(y, 12, d, sg)
      end
      j
    end

    def find_fdom(y, m, sg) # :nodoc:
      j = nil
      1.upto(31) do |d|
	break if j = _valid_civil?(y, m, d, sg)
      end
      j
    end

    def find_ldom(y, m, sg) # :nodoc:
      j = nil
      31.downto(1) do |d|
	break if j = _valid_civil?(y, m, d, sg)
      end
      j
    end

    # Convert an Ordinal Date to a Julian Day Number.
    #
    # +y+ and +d+ are the year and day-of-year to convert.
    # +sg+ specifies the Day of Calendar Reform.
    #
    # Returns the corresponding Julian Day Number.
    def ordinal_to_jd(y, d, sg=GREGORIAN) # :nodoc:
      find_fdoy(y, sg) + d - 1
    end

    # Convert a Julian Day Number to an Ordinal Date.
    #
    # +jd+ is the Julian Day Number to convert.
    # +sg+ specifies the Day of Calendar Reform.
    #
    # Returns the corresponding Ordinal Date as
    # [year, day_of_year]
    def jd_to_ordinal(jd, sg=GREGORIAN) # :nodoc:
      y = jd_to_civil(jd, sg)[0]
      j = find_fdoy(y, sg)
      doy = jd - j + 1
      return y, doy
    end

    # Convert a Civil Date to a Julian Day Number.
    # +y+, +m+, and +d+ are the year, month, and day of the
    # month.  +sg+ specifies the Day of Calendar Reform.
    #
    # Returns the corresponding Julian Day Number.
    def civil_to_jd(y, m, d, sg=GREGORIAN) # :nodoc:
      if m <= 2
	y -= 1
	m += 12
      end
      a = (y / 100.0).floor
      b = 2 - a + (a / 4.0).floor
      jd = (365.25 * (y + 4716)).floor +
	(30.6001 * (m + 1)).floor +
	d + b - 1524
      if jd < sg
	jd -= b
      end
      jd
    end

    # Convert a Julian Day Number to a Civil Date.  +jd+ is
    # the Julian Day Number. +sg+ specifies the Day of
    # Calendar Reform.
    #
    # Returns the corresponding [year, month, day_of_month]
    # as a three-element array.
    def jd_to_civil(jd, sg=GREGORIAN) # :nodoc:
      if jd < sg
	a = jd
      else
	x = ((jd - 1867216.25) / 36524.25).floor
	a = jd + 1 + x - (x / 4.0).floor
      end
      b = a + 1524
      c = ((b - 122.1) / 365.25).floor
      d = (365.25 * c).floor
      e = ((b - d) / 30.6001).floor
      dom = b - d - (30.6001 * e).floor
      if e <= 13
	m = e - 1
	y = c - 4716
      else
	m = e - 13
	y = c - 4715
      end
      return y, m, dom
    end

    # Convert a Commercial Date to a Julian Day Number.
    #
    # +y+, +w+, and +d+ are the (commercial) year, week of the year,
    # and day of the week of the Commercial Date to convert.
    # +sg+ specifies the Day of Calendar Reform.
    def commercial_to_jd(y, w, d, sg=GREGORIAN) # :nodoc:
      j = find_fdoy(y, sg) + 3
      (j - (((j - 1) + 1) % 7)) +
	7 * (w - 1) +
	(d - 1)
    end

    # Convert a Julian Day Number to a Commercial Date
    #
    # +jd+ is the Julian Day Number to convert.
    # +sg+ specifies the Day of Calendar Reform.
    #
    # Returns the corresponding Commercial Date as
    # [commercial_year, week_of_year, day_of_week]
    def jd_to_commercial(jd, sg=GREGORIAN) # :nodoc:
      a = jd_to_civil(jd - 3, sg)[0]
      y = if jd >= commercial_to_jd(a + 1, 1, 1, sg) then a + 1 else a end
      w = 1 + ((jd - commercial_to_jd(y, 1, 1, sg)) / 7).floor
      d = (jd + 1) % 7
      d = 7 if d == 0
      return y, w, d
    end

    def weeknum_to_jd(y, w, d, f=0, sg=GREGORIAN) # :nodoc:
      a = find_fdoy(y, sg) + 6
      (a - ((a - f) + 1) % 7 - 7) + 7 * w + d
    end

    def jd_to_weeknum(jd, f=0, sg=GREGORIAN) # :nodoc:
      y, _, d = jd_to_civil(jd, sg)
      a = find_fdoy(y, sg) + 6
      w, d = (jd - (a - ((a - f) + 1) % 7) + 7).divmod(7)
      return y, w, d
    end

    def nth_kday_to_jd(y, m, n, k, sg=GREGORIAN) # :nodoc:
      j = if n > 0
	    find_fdom(y, m, sg) - 1
	  else
	    find_ldom(y, m, sg) + 7
	  end
      (j - (((j - k) + 1) % 7)) + 7 * n
    end

    def jd_to_nth_kday(jd, sg=GREGORIAN) # :nodoc:
      y, m, = jd_to_civil(jd, sg)
      j = find_fdom(y, m, sg)
      return y, m, ((jd - j) / 7).floor + 1, jd_to_wday(jd)
    end

    # Convert an Astronomical Julian Day Number to a (civil) Julian
    # Day Number.
    #
    # +ajd+ is the Astronomical Julian Day Number to convert.
    # +of+ is the offset from UTC as a fraction of a day (defaults to 0).
    #
    # Returns the (civil) Julian Day Number as [day_number,
    # fraction] where +fraction+ is always 1/2.
    def ajd_to_jd(ajd, of=0) (ajd + of + HALF_DAYS_IN_DAY).divmod(1) end # :nodoc:

    # Convert a (civil) Julian Day Number to an Astronomical Julian
    # Day Number.
    #
    # +jd+ is the Julian Day Number to convert, and +fr+ is a
    # fractional day.
    # +of+ is the offset from UTC as a fraction of a day (defaults to 0).
    #
    # Returns the Astronomical Julian Day Number as a single
    # numeric value.
    def jd_to_ajd(jd, fr, of=0) jd + fr - of - HALF_DAYS_IN_DAY end # :nodoc:

    # Convert a fractional day +fr+ to [hours, minutes, seconds,
    # fraction_of_a_second]
    def day_fraction_to_time(fr) # :nodoc:
      ss,  fr = fr.divmod(SECONDS_IN_DAY) # 4p
      h,   ss = ss.divmod(3600)
      min, s  = ss.divmod(60)
      return h, min, s, fr * 86400
    end

    def day_fraction_to_time_wo_sf(fr) # :nodoc:
      ss      = fr.div(SECONDS_IN_DAY) # 4p
      h,   ss = ss.divmod(3600)
      min, s  = ss.divmod(60)
      return h, min, s
    end

    # Convert an +h+ hour, +min+ minutes, +s+ seconds period
    # to a fractional day.
    begin
      Rational(Rational(1, 2), 2) # a challenge

      def time_to_day_fraction(h, min, s)
	Rational(h * 3600 + min * 60 + s, 86400) # 4p
      end
    rescue
      def time_to_day_fraction(h, min, s)
	if Integer === h && Integer === min && Integer === s
	  Rational(h * 3600 + min * 60 + s, 86400) # 4p
	else
	  (h * 3600 + min * 60 + s).to_r/86400 # 4p
	end
      end
    end

    # Convert an Astronomical Modified Julian Day Number to an
    # Astronomical Julian Day Number.
    def amjd_to_ajd(amjd) amjd + MJD_EPOCH_IN_AJD end # :nodoc:

    # Convert an Astronomical Julian Day Number to an
    # Astronomical Modified Julian Day Number.
    def ajd_to_amjd(ajd) ajd - MJD_EPOCH_IN_AJD end # :nodoc:

    # Convert a Modified Julian Day Number to a Julian
    # Day Number.
    def mjd_to_jd(mjd) mjd + MJD_EPOCH_IN_CJD end # :nodoc:

    # Convert a Julian Day Number to a Modified Julian Day
    # Number.
    def jd_to_mjd(jd) jd - MJD_EPOCH_IN_CJD end # :nodoc:

    # Convert a count of the number of days since the adoption
    # of the Gregorian Calendar (in Italy) to a Julian Day Number.
    def ld_to_jd(ld) ld +  LD_EPOCH_IN_CJD end # :nodoc:

    # Convert a Julian Day Number to the number of days since
    # the adoption of the Gregorian Calendar (in Italy).
    def jd_to_ld(jd) jd -  LD_EPOCH_IN_CJD end # :nodoc:

    # Convert a Julian Day Number to the day of the week.
    #
    # Sunday is day-of-week 0; Saturday is day-of-week 6.
    def jd_to_wday(jd) (jd + 1) % 7 end # :nodoc:

    # Is +jd+ a valid Julian Day Number?
    #
    # If it is, returns it.  In fact, any value is treated as a valid
    # Julian Day Number.
    def _valid_jd? (jd, sg=GREGORIAN) jd end # :nodoc:

    # Do the year +y+ and day-of-year +d+ make a valid Ordinal Date?
    # Returns the corresponding Julian Day Number if they do, or
    # nil if they don't.
    #
    # +d+ can be a negative number, in which case it counts backwards
    # from the end of the year (-1 being the last day of the year).
    # No year wraparound is performed, however, so valid values of
    # +d+ are -365 .. -1, 1 .. 365 on a non-leap-year,
    # -366 .. -1, 1 .. 366 on a leap year.
    # A date falling in the period skipped in the Day of Calendar Reform
    # adjustment is not valid.
    #
    # +sg+ specifies the Day of Calendar Reform.
    def _valid_ordinal? (y, d, sg=GREGORIAN) # :nodoc:
      if d < 0
	return unless j = find_ldoy(y, sg)
	ny, nd = jd_to_ordinal(j + d + 1, sg)
	return unless ny == y
	d = nd
      end
      jd = ordinal_to_jd(y, d, sg)
      return unless [y, d] == jd_to_ordinal(jd, sg)
      jd
    end

    # Do year +y+, month +m+, and day-of-month +d+ make a
    # valid Civil Date?  Returns the corresponding Julian
    # Day Number if they do, nil if they don't.
    #
    # +m+ and +d+ can be negative, in which case they count
    # backwards from the end of the year and the end of the
    # month respectively.  No wraparound is performed, however,
    # and invalid values cause an ArgumentError to be raised.
    # A date falling in the period skipped in the Day of Calendar
    # Reform adjustment is not valid.
    #
    # +sg+ specifies the Day of Calendar Reform.
    def _valid_civil? (y, m, d, sg=GREGORIAN) # :nodoc:
      if m < 0
	m += 13
      end
      if d < 0
	return unless j = find_ldom(y, m, sg)
	ny, nm, nd = jd_to_civil(j + d + 1, sg)
	return unless [ny, nm] == [y, m]
	d = nd
      end
      jd = civil_to_jd(y, m, d, sg)
      return unless [y, m, d] == jd_to_civil(jd, sg)
      jd
    end

    # Do year +y+, week-of-year +w+, and day-of-week +d+ make a
    # valid Commercial Date?  Returns the corresponding Julian
    # Day Number if they do, nil if they don't.
    #
    # Monday is day-of-week 1; Sunday is day-of-week 7.
    #
    # +w+ and +d+ can be negative, in which case they count
    # backwards from the end of the year and the end of the
    # week respectively.  No wraparound is performed, however,
    # and invalid values cause an ArgumentError to be raised.
    # A date falling in the period skipped in the Day of Calendar
    # Reform adjustment is not valid.
    #
    # +sg+ specifies the Day of Calendar Reform.
    def _valid_commercial? (y, w, d, sg=GREGORIAN) # :nodoc:
      if d < 0
	d += 8
      end
      if w < 0
	ny, nw, =
	  jd_to_commercial(commercial_to_jd(y + 1, 1, 1, sg) + w * 7, sg)
	return unless ny == y
	w = nw
      end
      jd = commercial_to_jd(y, w, d, sg)
      return unless [y, w, d] == jd_to_commercial(jd, sg)
      jd
    end

    def _valid_weeknum? (y, w, d, f, sg=GREGORIAN) # :nodoc:
      if d < 0
	d += 7
      end
      if w < 0
	ny, nw, =
	  jd_to_weeknum(weeknum_to_jd(y + 1, 1, f, f, sg) + w * 7, f, sg)
	return unless ny == y
	w = nw
      end
      jd = weeknum_to_jd(y, w, d, f, sg)
      return unless [y, w, d] == jd_to_weeknum(jd, f, sg)
      jd
    end

    def _valid_nth_kday? (y, m, n, k, sg=GREGORIAN) # :nodoc:
      if k < 0
	k += 7
      end
      if n < 0
	ny, nm = (y * 12 + m).divmod(12)
	nm,    = (nm + 1)    .divmod(1)
	ny, nm, nn, =
	  jd_to_nth_kday(nth_kday_to_jd(ny, nm, 1, k, sg) + n * 7, sg)
	return unless [ny, nm] == [y, m]
	n = nn
      end
      jd = nth_kday_to_jd(y, m, n, k, sg)
      return unless [y, m, n, k] == jd_to_nth_kday(jd, sg)
      jd
    end

    # Do hour +h+, minute +min+, and second +s+ constitute a valid time?
    #
    # If they do, returns their value as a fraction of a day.  If not,
    # returns nil.
    #
    # The 24-hour clock is used.  Negative values of +h+, +min+, and
    # +sec+ are treating as counting backwards from the end of the
    # next larger unit (e.g. a +min+ of -2 is treated as 58).  No
    # wraparound is performed.
    def _valid_time? (h, min, s) # :nodoc:
      h   += 24 if h   < 0
      min += 60 if min < 0
      s   += 60 if s   < 0
      return unless ((0...24) === h &&
		     (0...60) === min &&
		     (0...60) === s) ||
		     (24 == h &&
		       0 == min &&
		       0 == s)
      time_to_day_fraction(h, min, s)
    end

  end

  extend  t
  include t

  # Is a year a leap year in the Julian calendar?
  #
  # All years divisible by 4 are leap years in the Julian calendar.
  def self.julian_leap? (y) y % 4 == 0 end

  # Is a year a leap year in the Gregorian calendar?
  #
  # All years divisible by 4 are leap years in the Gregorian calendar,
  # except for years divisible by 100 and not by 400.
  def self.gregorian_leap? (y) y % 4 == 0 && y % 100 != 0 || y % 400 == 0 end

  class << self; alias_method :leap?, :gregorian_leap? end
  class << self; alias_method :new!, :new end

  def self.valid_jd? (jd, sg=ITALY)
    !!_valid_jd?(jd, sg)
  end

  def self.valid_ordinal? (y, d, sg=ITALY)
    !!_valid_ordinal?(y, d, sg)
  end

  def self.valid_civil? (y, m, d, sg=ITALY)
    !!_valid_civil?(y, m, d, sg)
  end

  class << self; alias_method :valid_date?, :valid_civil? end

  def self.valid_commercial? (y, w, d, sg=ITALY)
    !!_valid_commercial?(y, w, d, sg)
  end

  def self.valid_weeknum? (y, w, d, f, sg=ITALY) # :nodoc:
    !!_valid_weeknum?(y, w, d, f, sg)
  end

  private_class_method :valid_weeknum?

  def self.valid_nth_kday? (y, m, n, k, sg=ITALY) # :nodoc:
    !!_valid_nth_kday?(y, m, n, k, sg)
  end

  private_class_method :valid_nth_kday?

  def self.valid_time? (h, min, s) # :nodoc:
    !!_valid_time?(h, min, s)
  end

  private_class_method :valid_time?

  # Create a new Date object from a Julian Day Number.
  #
  # +jd+ is the Julian Day Number; if not specified, it defaults to
  # 0.
  # +sg+ specifies the Day of Calendar Reform.
  def self.jd(jd=0, sg=ITALY)
    jd = _valid_jd?(jd, sg)
    new!(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  # Create a new Date object from an Ordinal Date, specified
  # by year +y+ and day-of-year +d+. +d+ can be negative,
  # in which it counts backwards from the end of the year.
  # No year wraparound is performed, however.  An invalid
  # value for +d+ results in an ArgumentError being raised.
  #
  # +y+ defaults to -4712, and +d+ to 1; this is Julian Day
  # Number day 0.
  #
  # +sg+ specifies the Day of Calendar Reform.
  def self.ordinal(y=-4712, d=1, sg=ITALY)
    unless jd = _valid_ordinal?(y, d, sg)
      raise ArgumentError, 'invalid date'
    end
    new!(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  # Create a new Date object for the Civil Date specified by
  # year +y+, month +m+, and day-of-month +d+.
  #
  # +m+ and +d+ can be negative, in which case they count
  # backwards from the end of the year and the end of the
  # month respectively.  No wraparound is performed, however,
  # and invalid values cause an ArgumentError to be raised.
  # can be negative
  #
  # +y+ defaults to -4712, +m+ to 1, and +d+ to 1; this is
  # Julian Day Number day 0.
  #
  # +sg+ specifies the Day of Calendar Reform.
  def self.civil(y=-4712, m=1, d=1, sg=ITALY)
    unless jd = _valid_civil?(y, m, d, sg)
      raise ArgumentError, 'invalid date'
    end
    new!(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  class << self; alias_method :new, :civil end

  # Create a new Date object for the Commercial Date specified by
  # year +y+, week-of-year +w+, and day-of-week +d+.
  #
  # Monday is day-of-week 1; Sunday is day-of-week 7.
  #
  # +w+ and +d+ can be negative, in which case they count
  # backwards from the end of the year and the end of the
  # week respectively.  No wraparound is performed, however,
  # and invalid values cause an ArgumentError to be raised.
  #
  # +y+ defaults to -4712, +w+ to 1, and +d+ to 1; this is
  # Julian Day Number day 0.
  #
  # +sg+ specifies the Day of Calendar Reform.
  def self.commercial(y=-4712, w=1, d=1, sg=ITALY)
    unless jd = _valid_commercial?(y, w, d, sg)
      raise ArgumentError, 'invalid date'
    end
    new!(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  def self.weeknum(y=-4712, w=0, d=1, f=0, sg=ITALY)
    unless jd = _valid_weeknum?(y, w, d, f, sg)
      raise ArgumentError, 'invalid date'
    end
    new!(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  private_class_method :weeknum

  def self.nth_kday(y=-4712, m=1, n=1, k=1, sg=ITALY)
    unless jd = _valid_nth_kday?(y, m, n, k, sg)
      raise ArgumentError, 'invalid date'
    end
    new!(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  private_class_method :nth_kday

  def self.rewrite_frags(elem) # :nodoc:
    elem ||= {}
    if seconds = elem[:seconds]
      d,   fr = seconds.divmod(86400)
      h,   fr = fr.divmod(3600)
      min, fr = fr.divmod(60)
      s,   fr = fr.divmod(1)
      elem[:jd] = UNIX_EPOCH_IN_CJD + d
      elem[:hour] = h
      elem[:min] = min
      elem[:sec] = s
      elem[:sec_fraction] = fr
      elem.delete(:seconds)
      elem.delete(:offset)
    end
    elem
  end

  private_class_method :rewrite_frags

  def self.complete_frags(elem) # :nodoc:
    i = 0
    g = [[:time, [:hour, :min, :sec]],
	 [nil, [:jd]],
	 [:ordinal, [:year, :yday, :hour, :min, :sec]],
	 [:civil, [:year, :mon, :mday, :hour, :min, :sec]],
	 [:commercial, [:cwyear, :cweek, :cwday, :hour, :min, :sec]],
	 [:wday, [:wday, :hour, :min, :sec]],
	 [:wnum0, [:year, :wnum0, :wday, :hour, :min, :sec]],
	 [:wnum1, [:year, :wnum1, :wday, :hour, :min, :sec]],
	 [nil, [:cwyear, :cweek, :wday, :hour, :min, :sec]],
	 [nil, [:year, :wnum0, :cwday, :hour, :min, :sec]],
	 [nil, [:year, :wnum1, :cwday, :hour, :min, :sec]]].
      collect{|k, a| e = elem.values_at(*a).compact; [k, a, e]}.
      select{|k, a, e| e.size > 0}.
      sort_by{|k, a, e| [e.size, i -= 1]}.last

    d = nil

    if g && g[0] && (g[1].size - g[2].size) != 0
      d ||= Date.today

      case g[0]
      when :ordinal
	elem[:year] ||= d.year
	elem[:yday] ||= 1
      when :civil
	g[1].each do |e|
	  break if elem[e]
	  elem[e] = d.__send__(e)
	end
	elem[:mon]  ||= 1
	elem[:mday] ||= 1
      when :commercial
	g[1].each do |e|
	  break if elem[e]
	  elem[e] = d.__send__(e)
	end
	elem[:cweek] ||= 1
	elem[:cwday] ||= 1
      when :wday
	elem[:jd] ||= (d - d.wday + elem[:wday]).jd
      when :wnum0
	g[1].each do |e|
	  break if elem[e]
	  elem[e] = d.__send__(e)
	end
	elem[:wnum0] ||= 0
	elem[:wday]  ||= 0
      when :wnum1
	g[1].each do |e|
	  break if elem[e]
	  elem[e] = d.__send__(e)
	end
	elem[:wnum1] ||= 0
	elem[:wday]  ||= 1
      end
    end

    if g && g[0] == :time
      if self <= DateTime
	d ||= Date.today
	elem[:jd] ||= d.jd
      end
    end

    elem[:hour] ||= 0
    elem[:min]  ||= 0
    elem[:sec]  ||= 0
    elem[:sec] = [elem[:sec], 59].min

    elem
  end

  private_class_method :complete_frags

  def self.valid_date_frags?(elem, sg) # :nodoc:
    catch :jd do
      a = elem.values_at(:jd)
      if a.all?
	if jd = _valid_jd?(*(a << sg))
	  throw :jd, jd
	end
      end

      a = elem.values_at(:year, :yday)
      if a.all?
	if jd = _valid_ordinal?(*(a << sg))
	  throw :jd, jd
	end
      end

      a = elem.values_at(:year, :mon, :mday)
      if a.all?
	if jd = _valid_civil?(*(a << sg))
	  throw :jd, jd
	end
      end

      a = elem.values_at(:cwyear, :cweek, :cwday)
      if a[2].nil? && elem[:wday]
	a[2] = elem[:wday].nonzero? || 7
      end
      if a.all?
	if jd = _valid_commercial?(*(a << sg))
	  throw :jd, jd
	end
      end

      a = elem.values_at(:year, :wnum0, :wday)
      if a[2].nil? && elem[:cwday]
	a[2] = elem[:cwday] % 7
      end
      if a.all?
	if jd = _valid_weeknum?(*(a << 0 << sg))
	  throw :jd, jd
	end
      end

      a = elem.values_at(:year, :wnum1, :wday)
      if a[2]
	a[2] = (a[2] - 1) % 7
      end
      if a[2].nil? && elem[:cwday]
	a[2] = (elem[:cwday] - 1) % 7
      end
      if a.all?
	if jd = _valid_weeknum?(*(a << 1 << sg))
	  throw :jd, jd
	end
      end
    end
  end

  private_class_method :valid_date_frags?

  def self.valid_time_frags? (elem) # :nodoc:
    h, min, s = elem.values_at(:hour, :min, :sec)
    _valid_time?(h, min, s)
  end

  private_class_method :valid_time_frags?

  def self.new_by_frags(elem, sg) # :nodoc:
    elem = rewrite_frags(elem)
    elem = complete_frags(elem)
    unless jd = valid_date_frags?(elem, sg)
      raise ArgumentError, 'invalid date'
    end
    new!(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  private_class_method :new_by_frags

  # Create a new Date object by parsing from a String
  # according to a specified format.
  #
  # +str+ is a String holding a date representation.
  # +fmt+ is the format that the date is in.  See
  # date/format.rb for details on supported formats.
  #
  # The default +str+ is '-4712-01-01', and the default
  # +fmt+ is '%F', which means Year-Month-Day_of_Month.
  # This gives Julian Day Number day 0.
  #
  # +sg+ specifies the Day of Calendar Reform.
  #
  # An ArgumentError will be raised if +str+ cannot be
  # parsed.
  def self.strptime(str='-4712-01-01', fmt='%F', sg=ITALY)
    elem = _strptime(str, fmt)
    new_by_frags(elem, sg)
  end

  # Create a new Date object by parsing from a String,
  # without specifying the format.
  #
  # +str+ is a String holding a date representation.
  # +comp+ specifies whether to interpret 2-digit years
  # as 19XX (>= 69) or 20XX (< 69); the default is to.
  # The method will attempt to parse a date from the String
  # using various heuristics; see #_parse in date/format.rb
  # for more details.  If parsing fails, an ArgumentError
  # will be raised.
  #
  # The default +str+ is '-4712-01-01'; this is Julian
  # Day Number day 0.
  #
  # +sg+ specifies the Day of Calendar Reform.
  def self.parse(str='-4712-01-01', comp=true, sg=ITALY)
    elem = _parse(str, comp)
    new_by_frags(elem, sg)
  end

  def self.iso8601(str='-4712-01-01', sg=ITALY) # :nodoc:
    elem = _iso8601(str)
    new_by_frags(elem, sg)
  end

  def self.rfc3339(str='-4712-01-01T00:00:00+00:00', sg=ITALY) # :nodoc:
    elem = _rfc3339(str)
    new_by_frags(elem, sg)
  end

  def self.xmlschema(str='-4712-01-01', sg=ITALY) # :nodoc:
    elem = _xmlschema(str)
    new_by_frags(elem, sg)
  end

  def self.rfc2822(str='Mon, 1 Jan -4712 00:00:00 +0000', sg=ITALY) # :nodoc:
    elem = _rfc2822(str)
    new_by_frags(elem, sg)
  end

  class << self; alias_method :rfc822, :rfc2822 end

  def self.httpdate(str='Mon, 01 Jan -4712 00:00:00 GMT', sg=ITALY) # :nodoc:
    elem = _httpdate(str)
    new_by_frags(elem, sg)
  end

  def self.jisx0301(str='-4712-01-01', sg=ITALY) # :nodoc:
    elem = _jisx0301(str)
    new_by_frags(elem, sg)
  end

  class << self

    def once(*ids) # :nodoc: -- restricted
      for id in ids
	module_eval <<-"end;"
	  alias_method :__#{id.object_id}__, :#{id.to_s}
	  private :__#{id.object_id}__
	  def #{id.to_s}(*args)
	    @__ca__[#{id.object_id}] ||= __#{id.object_id}__(*args)
	  end
	end;
      end
    end

    private :once

  end

  # *NOTE* this is the documentation for the method new!().  If
  # you are reading this as the documentation for new(), that is
  # because rdoc doesn't fully support the aliasing of the
  # initialize() method.
  # new() is in
  # fact an alias for #civil(): read the documentation for that
  # method instead.
  #
  # Create a new Date object.
  #
  # +ajd+ is the Astronomical Julian Day Number.
  # +of+ is the offset from UTC as a fraction of a day.
  # Both default to 0.
  #
  # +sg+ specifies the Day of Calendar Reform to use for this
  # Date object.
  #
  # Using one of the factory methods such as Date::civil is
  # generally easier and safer.
  def initialize(ajd=0, of=0, sg=ITALY)
    @ajd, @of, @sg = ajd, of, sg
    @__ca__ = {}
  end

  # Get the date as an Astronomical Julian Day Number.
  def ajd() @ajd end

  # Get the date as an Astronomical Modified Julian Day Number.
  def amjd() ajd_to_amjd(@ajd) end

  once :amjd

  def daynum() ajd_to_jd(@ajd, @of) end

  once :daynum

  # Get the date as a Julian Day Number.
  def jd() daynum[0] end

  # Get any fractional day part of the date.
  def day_fraction() daynum[1] end

  # Get the date as a Modified Julian Day Number.
  def mjd() jd_to_mjd(jd) end

  # Get the date as the number of days since the Day of Calendar
  # Reform (in Italy and the Catholic countries).
  def ld() jd_to_ld(jd) end

  once :jd, :day_fraction, :mjd, :ld

  # Get the date as a Civil Date, [year, month, day_of_month]
  def civil() jd_to_civil(jd, @sg) end # :nodoc:

  # Get the date as an Ordinal Date, [year, day_of_year]
  def ordinal() jd_to_ordinal(jd, @sg) end # :nodoc:

  # Get the date as a Commercial Date, [year, week_of_year, day_of_week]
  def commercial() jd_to_commercial(jd, @sg) end # :nodoc:

  def weeknum0() jd_to_weeknum(jd, 0, @sg) end # :nodoc:
  def weeknum1() jd_to_weeknum(jd, 1, @sg) end # :nodoc:

  once :civil, :ordinal, :commercial, :weeknum0, :weeknum1
  private :civil, :ordinal, :commercial, :weeknum0, :weeknum1

  # Get the year of this date.
  def year() civil[0] end

  # Get the day-of-the-year of this date.
  #
  # January 1 is day-of-the-year 1
  def yday() ordinal[1] end

  # Get the month of this date.
  #
  # January is month 1.
  def mon() civil[1] end

  # Get the day-of-the-month of this date.
  def mday() civil[2] end

  alias_method :month, :mon
  alias_method :day, :mday

  def wnum0() weeknum0[1] end # :nodoc:
  def wnum1() weeknum1[1] end # :nodoc:

  private :wnum0, :wnum1

  # Get the time of this date as [hours, minutes, seconds,
  # fraction_of_a_second]
  def time() day_fraction_to_time(day_fraction) end # :nodoc:
  def time_wo_sf() day_fraction_to_time_wo_sf(day_fraction) end # :nodoc:
  def time_sf() day_fraction % SECONDS_IN_DAY * 86400 end # :nodoc:

  once :time, :time_wo_sf, :time_sf
  private :time, :time_wo_sf, :time_sf

  # Get the hour of this date.
  def hour() time_wo_sf[0] end # 4p

  # Get the minute of this date.
  def min() time_wo_sf[1] end # 4p

  # Get the second of this date.
  def sec() time_wo_sf[2] end # 4p

  # Get the fraction-of-a-second of this date.
  def sec_fraction() time_sf end # 4p

  alias_method :minute, :min
  alias_method :second, :sec
  alias_method :second_fraction, :sec_fraction

  private :hour, :min, :sec, :sec_fraction,
	  :minute, :second, :second_fraction

  def zone # 4p - strftime('%:z')
    sign = if offset < 0 then '-' else '+' end
    fr = offset.abs
    ss = fr.div(SECONDS_IN_DAY)
    hh, ss = ss.divmod(3600)
    mm     = ss.div(60)
    format('%s%02d:%02d', sign, hh, mm)
  end

  private :zone

  # Get the commercial year of this date.  See *Commercial* *Date*
  # in the introduction for how this differs from the normal year.
  def cwyear() commercial[0] end

  # Get the commercial week of the year of this date.
  def cweek() commercial[1] end

  # Get the commercial day of the week of this date.  Monday is
  # commercial day-of-week 1; Sunday is commercial day-of-week 7.
  def cwday() commercial[2] end

  # Get the week day of this date.  Sunday is day-of-week 0;
  # Saturday is day-of-week 6.
  def wday() jd_to_wday(jd) end

  once :wday

=begin
  MONTHNAMES.each_with_index do |n, i|
    if n
      define_method(n.downcase + '?'){mon == i}
    end
  end
=end

  DAYNAMES.each_with_index do |n, i|
    define_method(n.downcase + '?'){wday == i}
  end

  def nth_kday? (n, k)
    k == wday && jd === nth_kday_to_jd(year, mon, n, k, start)
  end

  private :nth_kday?

  # Is the current date old-style (Julian Calendar)?
  def julian? () jd < @sg end

  # Is the current date new-style (Gregorian Calendar)?
  def gregorian? () !julian? end

  once :julian?, :gregorian?

  def fix_style # :nodoc:
    if julian?
    then self.class::JULIAN
    else self.class::GREGORIAN end
  end

  private :fix_style

  # Is this a leap year?
  def leap?
    jd_to_civil(civil_to_jd(year, 3, 1, fix_style) - 1,
		fix_style)[-1] == 29
  end

  once :leap?

  # When is the Day of Calendar Reform for this Date object?
  def start() @sg end

  # Create a copy of this Date object using a new Day of Calendar Reform.
  def new_start(sg=self.class::ITALY) self.class.new!(@ajd, @of, sg) end

  # Create a copy of this Date object that uses the Italian/Catholic
  # Day of Calendar Reform.
  def italy() new_start(self.class::ITALY) end

  # Create a copy of this Date object that uses the English/Colonial
  # Day of Calendar Reform.
  def england() new_start(self.class::ENGLAND) end

  # Create a copy of this Date object that always uses the Julian
  # Calendar.
  def julian() new_start(self.class::JULIAN) end

  # Create a copy of this Date object that always uses the Gregorian
  # Calendar.
  def gregorian() new_start(self.class::GREGORIAN) end

  def offset() @of end

  def new_offset(of=0)
    if String === of
      of = Rational(zone_to_diff(of) || 0, 86400)
    end
    self.class.new!(@ajd, of, @sg)
  end

  private :offset, :new_offset

  # Return a new Date object that is +n+ days later than the
  # current one.
  #
  # +n+ may be a negative value, in which case the new Date
  # is earlier than the current one; however, #-() might be
  # more intuitive.
  #
  # If +n+ is not a Numeric, a TypeError will be thrown.  In
  # particular, two Dates cannot be added to each other.
  def + (n)
    case n
    when Numeric; return self.class.new!(@ajd + n, @of, @sg)
    end
    raise TypeError, 'expected numeric'
  end

  # If +x+ is a Numeric value, create a new Date object that is
  # +x+ days earlier than the current one.
  #
  # If +x+ is a Date, return the number of days between the
  # two dates; or, more precisely, how many days later the current
  # date is than +x+.
  #
  # If +x+ is neither Numeric nor a Date, a TypeError is raised.
  def - (x)
    case x
    when Numeric; return self.class.new!(@ajd - x, @of, @sg)
    when Date;    return @ajd - x.ajd
    end
    raise TypeError, 'expected numeric or date'
  end

  # Compare this date with another date.
  #
  # +other+ can also be a Numeric value, in which case it is
  # interpreted as an Astronomical Julian Day Number.
  #
  # Comparison is by Astronomical Julian Day Number, including
  # fractional days.  This means that both the time and the
  # offset are taken into account when comparing
  # two DateTime instances.  When comparing a DateTime instance
  # with a Date instance, the time of the latter will be
  # considered as falling on midnight UTC.
  def <=> (other)
    case other
    when Numeric; return @ajd <=> other
    when Date;    return @ajd <=> other.ajd
    else
      begin
        l, r = other.coerce(self)
        return l <=> r
      rescue NoMethodError
      end
    end
    nil
  end

  # The relationship operator for Date.
  #
  # Compares dates by Julian Day Number.  When comparing
  # two DateTime instances, or a DateTime with a Date,
  # the instances will be regarded as equivalent if they
  # fall on the same date in local time.
  def === (other)
    case other
    when Numeric; return jd == other
    when Date;    return jd == other.jd
    else
      l, r = other.coerce(self)
      return l === r
    end
    false
  end

  def next_day(n=1) self + n end
  def prev_day(n=1) self - n end

  # Return a new Date one day after this one.
  def next() next_day end

  alias_method :succ, :next

  # Return a new Date object that is +n+ months later than
  # the current one.
  #
  # If the day-of-the-month of the current Date is greater
  # than the last day of the target month, the day-of-the-month
  # of the returned Date will be the last day of the target month.
  def >> (n)
    y, m = (year * 12 + (mon - 1) + n).divmod(12)
    m,   = (m + 1)                    .divmod(1)
    d = mday
    until jd2 = _valid_civil?(y, m, d, @sg)
      d -= 1
      raise ArgumentError, 'invalid date' unless d > 0
    end
    self + (jd2 - jd)
  end

  # Return a new Date object that is +n+ months earlier than
  # the current one.
  #
  # If the day-of-the-month of the current Date is greater
  # than the last day of the target month, the day-of-the-month
  # of the returned Date will be the last day of the target month.
  def << (n) self >> -n end

  def next_month(n=1) self >> n end
  def prev_month(n=1) self << n end

  def next_year(n=1) self >> n * 12 end
  def prev_year(n=1) self << n * 12 end

  require 'enumerator'

  # Step the current date forward +step+ days at a
  # time (or backward, if +step+ is negative) until
  # we reach +limit+ (inclusive), yielding the resultant
  # date at each step.
  def step(limit, step=1) # :yield: date
=begin
    if step.zero?
      raise ArgumentError, "step can't be 0"
    end
=end
    unless block_given?
      return to_enum(:step, limit, step)
    end
    da = self
    op = %w(- <= >=)[step <=> 0]
    while da.__send__(op, limit)
      yield da
      da += step
    end
    self
  end

  # Step forward one day at a time until we reach +max+
  # (inclusive), yielding each date as we go.
  def upto(max, &block) # :yield: date
    step(max, +1, &block)
  end

  # Step backward one day at a time until we reach +min+
  # (inclusive), yielding each date as we go.
  def downto(min, &block) # :yield: date
    step(min, -1, &block)
  end

  # Is this Date equal to +other+?
  #
  # +other+ must both be a Date object, and represent the same date.
  def eql? (other) Date === other && self == other end

  # Calculate a hash value for this date.
  def hash() @ajd.hash end

  # Return internal object state as a programmer-readable string.
  def inspect
    format('#<%s: %s (%s,%s,%s)>', self.class, to_s, @ajd, @of, @sg)
  end

  # Return the date as a human-readable string.
  #
  # The format used is YYYY-MM-DD.
  def to_s() format('%.4d-%02d-%02d', year, mon, mday) end # 4p

  # Dump to Marshal format.
  def marshal_dump() [@ajd, @of, @sg] end

  # Load from Marshal format.
  def marshal_load(a)
    @ajd, @of, @sg, = a
    @__ca__ = {}
  end

end

# Class representing a date and time.
#
# See the documentation to the file date.rb for an overview.
#
# DateTime objects are immutable once created.
#
# == Other methods.
#
# The following methods are defined in Date, but declared private
# there.  They are made public in DateTime.  They are documented
# here.
#
# === hour()
#
# Get the hour-of-the-day of the time.  This is given
# using the 24-hour clock, counting from midnight.  The first
# hour after midnight is hour 0; the last hour of the day is
# hour 23.
#
# === min()
#
# Get the minute-of-the-hour of the time.
#
# === sec()
#
# Get the second-of-the-minute of the time.
#
# === sec_fraction()
#
# Get the fraction of a second of the time.  This is returned as
# a +Rational+.
#
# === zone()
#
# Get the time zone as a String.  This is representation of the
# time offset such as "+10:00".
#
# === offset()
#
# Get the time zone offset as a fraction of a day.  This is returned
# as a +Rational+.
#
# === new_offset(of=0)
#
# Create a new DateTime object, identical to the current one, except
# with a new time zone offset of +of+.  +of+ is the new offset from
# UTC as a fraction of a day.
#
class DateTime < Date

  # Create a new DateTime object corresponding to the specified
  # Julian Day Number +jd+ and hour +h+, minute +min+, second +s+.
  #
  # The 24-hour clock is used.  Negative values of +h+, +min+, and
  # +sec+ are treating as counting backwards from the end of the
  # next larger unit (e.g. a +min+ of -2 is treated as 58).  No
  # wraparound is performed.  If an invalid time portion is specified,
  # an ArgumentError is raised.
  #
  # +of+ is the offset from UTC as a fraction of a day (defaults to 0).
  # +sg+ specifies the Day of Calendar Reform.
  #
  # All day/time values default to 0.
  def self.jd(jd=0, h=0, min=0, s=0, of=0, sg=ITALY)
    unless (jd = _valid_jd?(jd, sg)) &&
	   (fr = _valid_time?(h, min, s))
      raise ArgumentError, 'invalid date'
    end
    if String === of
      of = Rational(zone_to_diff(of) || 0, 86400)
    end
    new!(jd_to_ajd(jd, fr, of), of, sg)
  end

  # Create a new DateTime object corresponding to the specified
  # Ordinal Date and hour +h+, minute +min+, second +s+.
  #
  # The 24-hour clock is used.  Negative values of +h+, +min+, and
  # +sec+ are treating as counting backwards from the end of the
  # next larger unit (e.g. a +min+ of -2 is treated as 58).  No
  # wraparound is performed.  If an invalid time portion is specified,
  # an ArgumentError is raised.
  #
  # +of+ is the offset from UTC as a fraction of a day (defaults to 0).
  # +sg+ specifies the Day of Calendar Reform.
  #
  # +y+ defaults to -4712, and +d+ to 1; this is Julian Day Number
  # day 0.  The time values default to 0.
  def self.ordinal(y=-4712, d=1, h=0, min=0, s=0, of=0, sg=ITALY)
    unless (jd = _valid_ordinal?(y, d, sg)) &&
	   (fr = _valid_time?(h, min, s))
      raise ArgumentError, 'invalid date'
    end
    if String === of
      of = Rational(zone_to_diff(of) || 0, 86400)
    end
    new!(jd_to_ajd(jd, fr, of), of, sg)
  end

  # Create a new DateTime object corresponding to the specified
  # Civil Date and hour +h+, minute +min+, second +s+.
  #
  # The 24-hour clock is used.  Negative values of +h+, +min+, and
  # +sec+ are treating as counting backwards from the end of the
  # next larger unit (e.g. a +min+ of -2 is treated as 58).  No
  # wraparound is performed.  If an invalid time portion is specified,
  # an ArgumentError is raised.
  #
  # +of+ is the offset from UTC as a fraction of a day (defaults to 0).
  # +sg+ specifies the Day of Calendar Reform.
  #
  # +y+ defaults to -4712, +m+ to 1, and +d+ to 1; this is Julian Day
  # Number day 0.  The time values default to 0.
  def self.civil(y=-4712, m=1, d=1, h=0, min=0, s=0, of=0, sg=ITALY)
    unless (jd = _valid_civil?(y, m, d, sg)) &&
	   (fr = _valid_time?(h, min, s))
      raise ArgumentError, 'invalid date'
    end
    if String === of
      of = Rational(zone_to_diff(of) || 0, 86400)
    end
    new!(jd_to_ajd(jd, fr, of), of, sg)
  end

  class << self; alias_method :new, :civil end

  # Create a new DateTime object corresponding to the specified
  # Commercial Date and hour +h+, minute +min+, second +s+.
  #
  # The 24-hour clock is used.  Negative values of +h+, +min+, and
  # +sec+ are treating as counting backwards from the end of the
  # next larger unit (e.g. a +min+ of -2 is treated as 58).  No
  # wraparound is performed.  If an invalid time portion is specified,
  # an ArgumentError is raised.
  #
  # +of+ is the offset from UTC as a fraction of a day (defaults to 0).
  # +sg+ specifies the Day of Calendar Reform.
  #
  # +y+ defaults to -4712, +w+ to 1, and +d+ to 1; this is
  # Julian Day Number day 0.
  # The time values default to 0.
  def self.commercial(y=-4712, w=1, d=1, h=0, min=0, s=0, of=0, sg=ITALY)
    unless (jd = _valid_commercial?(y, w, d, sg)) &&
	   (fr = _valid_time?(h, min, s))
      raise ArgumentError, 'invalid date'
    end
    if String === of
      of = Rational(zone_to_diff(of) || 0, 86400)
    end
    new!(jd_to_ajd(jd, fr, of), of, sg)
  end

  def self.weeknum(y=-4712, w=0, d=1, f=0, h=0, min=0, s=0, of=0, sg=ITALY) # :nodoc:
    unless (jd = _valid_weeknum?(y, w, d, f, sg)) &&
	   (fr = _valid_time?(h, min, s))
      raise ArgumentError, 'invalid date'
    end
    if String === of
      of = Rational(zone_to_diff(of) || 0, 86400)
    end
    new!(jd_to_ajd(jd, fr, of), of, sg)
  end

  private_class_method :weeknum

  def self.nth_kday(y=-4712, m=1, n=1, k=1, h=0, min=0, s=0, of=0, sg=ITALY) # :nodoc:
    unless (jd = _valid_nth_kday?(y, m, n, k, sg)) &&
	   (fr = _valid_time?(h, min, s))
      raise ArgumentError, 'invalid date'
    end
    if String === of
      of = Rational(zone_to_diff(of) || 0, 86400)
    end
    new!(jd_to_ajd(jd, fr, of), of, sg)
  end

  private_class_method :nth_kday

  def self.new_by_frags(elem, sg) # :nodoc:
    elem = rewrite_frags(elem)
    elem = complete_frags(elem)
    unless (jd = valid_date_frags?(elem, sg)) &&
	   (fr = valid_time_frags?(elem))
      raise ArgumentError, 'invalid date'
    end
    fr += (elem[:sec_fraction] || 0) / 86400
    of = Rational(elem[:offset] || 0, 86400)
    new!(jd_to_ajd(jd, fr, of), of, sg)
  end

  private_class_method :new_by_frags

  # Create a new DateTime object by parsing from a String
  # according to a specified format.
  #
  # +str+ is a String holding a date-time representation.
  # +fmt+ is the format that the date-time is in.  See
  # date/format.rb for details on supported formats.
  #
  # The default +str+ is '-4712-01-01T00:00:00+00:00', and the default
  # +fmt+ is '%FT%T%z'.  This gives midnight on Julian Day Number day 0.
  #
  # +sg+ specifies the Day of Calendar Reform.
  #
  # An ArgumentError will be raised if +str+ cannot be
  # parsed.
  def self.strptime(str='-4712-01-01T00:00:00+00:00', fmt='%FT%T%z', sg=ITALY)
    elem = _strptime(str, fmt)
    new_by_frags(elem, sg)
  end

  # Create a new DateTime object by parsing from a String,
  # without specifying the format.
  #
  # +str+ is a String holding a date-time representation.
  # +comp+ specifies whether to interpret 2-digit years
  # as 19XX (>= 69) or 20XX (< 69); the default is to.
  # The method will attempt to parse a date-time from the String
  # using various heuristics; see #_parse in date/format.rb
  # for more details.  If parsing fails, an ArgumentError
  # will be raised.
  #
  # The default +str+ is '-4712-01-01T00:00:00+00:00'; this is Julian
  # Day Number day 0.
  #
  # +sg+ specifies the Day of Calendar Reform.
  def self.parse(str='-4712-01-01T00:00:00+00:00', comp=true, sg=ITALY)
    elem = _parse(str, comp)
    new_by_frags(elem, sg)
  end

  def self.iso8601(str='-4712-01-01T00:00:00+00:00', sg=ITALY) # :nodoc:
    elem = _iso8601(str)
    new_by_frags(elem, sg)
  end

  def self.xmlschema(str='-4712-01-01T00:00:00+00:00', sg=ITALY) # :nodoc:
    elem = _xmlschema(str)
    new_by_frags(elem, sg)
  end

  def self.rfc2822(str='Mon, 1 Jan -4712 00:00:00 +0000', sg=ITALY) # :nodoc:
    elem = _rfc2822(str)
    new_by_frags(elem, sg)
  end

  class << self; alias_method :rfc822, :rfc2822 end

  def self.httpdate(str='Mon, 01 Jan -4712 00:00:00 GMT', sg=ITALY) # :nodoc:
    elem = _httpdate(str)
    new_by_frags(elem, sg)
  end

  def self.jisx0301(str='-4712-01-01T00:00:00+00:00', sg=ITALY) # :nodoc:
    elem = _jisx0301(str)
    new_by_frags(elem, sg)
  end

  public :hour, :min, :sec, :sec_fraction, :zone, :offset, :new_offset,
	 :minute, :second, :second_fraction

  def to_s # 4p
    format('%.4d-%02d-%02dT%02d:%02d:%02d%s',
	   year, mon, mday, hour, min, sec, zone)
  end

end

class Time

  def to_time() getlocal end

  def to_date
    jd = Date.__send__(:civil_to_jd, year, mon, mday, Date::ITALY)
    Date.new!(Date.__send__(:jd_to_ajd, jd, 0, 0), 0, Date::ITALY)
  end

  def to_datetime
    jd = DateTime.__send__(:civil_to_jd, year, mon, mday, DateTime::ITALY)
    fr = DateTime.__send__(:time_to_day_fraction, hour, min, [sec, 59].min) +
      Rational(subsec, 86400)
    of = Rational(utc_offset, 86400)
    DateTime.new!(DateTime.__send__(:jd_to_ajd, jd, fr, of),
		  of, DateTime::ITALY)
  end

end

class Date

  def to_time() Time.local(year, mon, mday) end
  def to_date() self end
  def to_datetime() DateTime.new!(jd_to_ajd(jd, 0, 0), @of, @sg) end

  # Create a new Date object representing today.
  #
  # +sg+ specifies the Day of Calendar Reform.
  def self.today(sg=ITALY)
    t = Time.now
    jd = civil_to_jd(t.year, t.mon, t.mday, sg)
    new!(jd_to_ajd(jd, 0, 0), 0, sg)
  end

  # Create a new DateTime object representing the current time.
  #
  # +sg+ specifies the Day of Calendar Reform.
  def self.now(sg=ITALY)
    t = Time.now
    jd = civil_to_jd(t.year, t.mon, t.mday, sg)
    fr = time_to_day_fraction(t.hour, t.min, [t.sec, 59].min) +
      Rational(t.subsec, 86400)
    of = Rational(t.utc_offset, 86400)
    new!(jd_to_ajd(jd, fr, of), of, sg)
  end

  private_class_method :now

end

class DateTime < Date

  def to_time
    d = new_offset(0)
    d.instance_eval do
      Time.utc(year, mon, mday, hour, min, sec +
	       sec_fraction)
    end.
	getlocal
  end

  def to_date() Date.new!(jd_to_ajd(jd, 0, 0), 0, @sg) end
  def to_datetime() self end

  private_class_method :today
  public_class_method  :now

end
