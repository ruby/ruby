module ParseDate
  MONTHS = {
    'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4,
    'may' => 5, 'jun' => 6, 'jul' => 7, 'aug' => 8,
    'sep' => 9, 'oct' =>10, 'nov' =>11, 'dec' =>12 }
  MONTHPAT = MONTHS.keys.join('|')
  DAYPAT = 'mon|tue|wed|thu|fri|sat|sun'
  
  def parsedate(date) 
    if date.sub!(/(#{DAYPAT})/i, ' ')
      dayofweek = $1
    end
    if date.sub!(/\s+(\d+:\d+(:\d+)?)/, ' ')
      time = $1
    end
    if date =~ /19(\d\d)/
      year = $1
    end
    if date.sub!(/\s*(\d+)\s+(#{MONTHPAT})\S*\s+/i, ' ')
      dayofmonth = $1
      monthname  = $2
    elsif date.sub!(/\s*(#{MONTHPAT})\S*\s+(\d+)\s+/i, ' ')
      monthname  = $1
      dayofmonth = $2
    elsif date.sub!(/\s*(#{MONTHPAT})\S*\s+(\d+)\D+/i, ' ')
      monthname  = $1
      dayofmonth = $2
    elsif date.sub!(/\s*(\d\d?)\/(\d\d?)/, ' ')
      month  = $1
      dayofmonth = $2
    end
    if monthname
      month = MONTHS[monthname.downcase]
    end
    if ! year && date =~ /\d\d/
      year = $&
    end
    return year, month, dayofmonth
  end

  module_function :parsedate
end
