# parsedate.rb: Written by Tadayoshi Funaba 2001, 2002
# $Id: parsedate.rb,v 2.6 2002-05-14 07:43:18+09 tadf Exp $

require 'date/format'

module ParseDate

  def parsedate(str, comp=false)
    Date._parse(str, comp).
      values_at(:year, :mon, :mday, :hour, :min, :sec, :zone, :wday)
  end

  module_function :parsedate

end
