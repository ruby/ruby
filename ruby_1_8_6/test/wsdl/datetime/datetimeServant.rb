require 'datetime.rb'

class DatetimePortType
  # SYNOPSIS
  #   now(now)
  #
  # ARGS
  #   now		 - {http://www.w3.org/2001/XMLSchema}dateTime
  #
  # RETURNS
  #   now		 - {http://www.w3.org/2001/XMLSchema}dateTime
  #
  # RAISES
  #   (undefined)
  #
  def now(now)
    #raise NotImplementedError.new
    now + 1
  end
end

