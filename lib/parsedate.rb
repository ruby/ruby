module ParseDate
  MONTHS = {
    'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4,
    'may' => 5, 'jun' => 6, 'jul' => 7, 'aug' => 8,
    'sep' => 9, 'oct' =>10, 'nov' =>11, 'dec' =>12 }
  MONTHPAT = MONTHS.keys.join('|')
  DAYS = {
    'sun' => 0, 'mon' => 1, 'tue' => 2, 'wed' => 3,
    'thu' => 4, 'fri' => 5, 'sat' => 6 }
  DAYPAT = DAYS.keys.join('|')

  def parsedate(date, guess=false) 
    # part of ISO 8601
    # yyyy-mm-dd | yyyy-mm | yyyy
    # date hh:mm:ss | date Thh:mm:ss
    if date =~ /^(\d\d\d\d)-?(?:(\d\d)-?(\d\d)?)? *T?(?:(\d\d):?(\d\d):?(\d\d)?)?$/
      return $1.to_i,
	if $2 then $2.to_i else 1 end,
	if $3 then $3.to_i else 1 end,
	if $4 then $4.to_i end,
	if $5 then $5.to_i end,
	if $6 then $6.to_i end,
	nil,
	nil
    end
    date = date.dup
    if date.sub!(/(#{DAYPAT})[a-z]*,?/i, ' ')
      wday = DAYS[$1.downcase]
    end
    if date.sub!(/(\d+):(\d+)(?::(\d+))?(?:\s*(am|pm))?(?:\s+([a-z]{1,4}(?:\s+[a-z]{1,4}|[-+]\d{4})?))?/i, ' ')
      hour = $1.to_i
      min = $2.to_i
      if $3
	sec = $3.to_i
      end
      if $4 == 'pm'
	hour += 12
      end
      if $5
	zone = $5
      end
    end
    if date.sub!(/(\d+)\S*\s+(#{MONTHPAT})\S*(?:\s+(\d+))?/i, ' ')
      mday = $1.to_i
      mon = MONTHS[$2.downcase]
      if $3
	year = $3.to_i
      end
    elsif date.sub!(/(#{MONTHPAT})\S*\s+(\d+)\S*,?(?:\s+(\d+))?/i, ' ')
      mon = MONTHS[$1.downcase]
      mday = $2.to_i
      if $3
	year = $3.to_i
      end
    elsif date.sub!(/(\d+)\/(\d+)(?:\/(\d+))/, ' ')
      mon = $1.to_i
      mday = $2.to_i
      if $3
	year = $3.to_i
      end
    elsif date.sub!(/(\d+)-(#{MONTHPAT})-(\d+)/i, ' ')
      mday = $1.to_i
      mon = MONTHS[$2.downcase]
      year = $3.to_i
    elsif date.sub!(/(\d+)-(#{MONTHPAT})-(\d+)/i, ' ')
      mday = $1.to_i
      mon = MONTHS[$2.downcase]
      year = $3.to_i
    end
    if date.sub!(/\d{4}/i, ' ')
      year = $&.to_i
    elsif date.sub!(/\d\d/i, ' ')
      year = $&.to_i
    end
    if guess and year
      if year < 100
	if year >= 69
	  year += 1900
	else
	  year += 2000
	end
      end
    end
    return year, mon, mday, hour, min, sec, zone, wday
  end

  module_function :parsedate
end

if __FILE__ == $0
  p Time.now.asctime
  p ParseDate.parsedate(Time.now.asctime)
end
