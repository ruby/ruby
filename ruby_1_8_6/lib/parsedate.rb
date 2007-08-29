#
# = parsedate.rb: Parses dates
#
# Author:: Tadayoshi Funaba
# Documentation:: Konrad Meyer
#
# ParseDate munches on a date and turns it into an array of values.
#

#
# ParseDate converts a date into an array of values.
# For example:
#
#   require 'parsedate'
#
#   ParseDate.parsedate "Tuesday, July 6th, 2007, 18:35:20 UTC"
#   # => [2007, 7, 6, 18, 35, 20, "UTC", 2]
#
# The order is of the form [year, month, day of month, hour, minute, second,
# timezone, day of the week].

require 'date/format'

module ParseDate
  #
  # Parse a string representation of a date into values.
  # For example:
  #
  #   require 'parsedate'
  #
  #   ParseDate.parsedate "Tuesday, July 5th, 2007, 18:35:20 UTC"
  #   # => [2007, 7, 5, 18, 35, 20, "UTC", 2]
  #
  # The order is of the form [year, month, day of month, hour, minute,
  # second, timezone, day of week].
  #
  # ParseDate.parsedate can also take a second argument, +comp+, which
  # is a boolean telling the method to compensate for dates with years
  # expressed as two digits. Example:
  #
  #   require 'parsedate'
  #
  #   ParseDate.parsedate "Mon Dec 25 00 06:53:24 UTC", true
  #   # => [2000, 12, 25, 6, 53, 24, "UTC", 1]
  #
  def parsedate(str, comp=false)
    Date._parse(str, comp).
      values_at(:year, :mon, :mday, :hour, :min, :sec, :zone, :wday)
  end

  module_function :parsedate

end
