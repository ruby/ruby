#! /usr/local/bin/ruby

$= = TRUE

module ParseDate
  MONTHS = {
    'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4,
    'may' => 5, 'jun' => 6, 'jul' => 7, 'aug' => 8,
    'sep' => 9, 'oct' =>10, 'nov' =>11, 'dec' =>12 }
  MONTHPAT = MONTHS.keys.join('|')
  DAYPAT = 'mon|tue|wed|thu|fri|sat|sun'
  
  def ParseDate.parsedate(date) 
    if date.sub(/(#{DAYPAT})/i, ' ')
      dayofweek = $1
    end
    if date.sub(/\s+(\d+:\d+(:\d+)?)/, ' ')
      time = $1
    end
    if date =~ /19(\d\d)/
      year = $1
    end
    if date.sub(/\s*(\d+)\s+(#{MONTHPAT})\S*\s+/, ' ')
      dayofmonth = $1
      monthname  = $2
    elsif date.sub(/\s*(#{MONTHPAT})\S*\s+(\d+)\s+/, ' ')
      monthname  = $1
      dayofmonth = $2
    elsif date.sub(/\s*(#{MONTHPAT})\S*\s+(\d+)\D+/, ' ')
      monthname  = $1
      dayofmonth = $2
    elsif date.sub(/\s*(\d\d?)\/(\d\d?)/, ' ')
      month  = $1
      dayofmonth = $2
    end
    if monthname
      month = MONTHS[monthname.tolower]
    end
    if ! year && date =~ /\d\d/
      year = $&
    end
    return year, month, dayofmonth
  end

end

  def parsedate(date)
    ParseDate.parsedate(date)
  end

# include ParseDate

if $ARGV[0] == '-w'
  wait = TRUE
  $ARGV.shift
end

$ARGV[0] = '/usr/spool/mail/' + ENV['USER'] if $ARGV.length == 0

$outcount = 0;
def fromout(date, from, subj)
  y, m, d = parsedate(date)
  printf "%-2d/%02d/%02d [%.28s] %.40s\n", y, m, d, from, subj
  $outcount += 1
end
  
while TRUE
  fields = {}
  while gets()
    $_.chop
    continue if /^From /	# skip From-line  
    break if /^[ \t]*$/		# end of header
    if /^(\S+):\s*(.*)/
      fields[attr = $1] = $2
    elsif attr
      sub(/^\s*/, '')
      fields[attr] += "\n" + $_
    end
  end

  break if ! $_

  fromout fields['Date'], fields['From'], fields['Subject']

  while gets()
#    print $_
    break if /^From /
  end

  break if ! $_
end

if $outcount == 0
  print "You have no mail.\n"
  sleep 2 if wait
elsif wait
  system "stty cbreak -echo"
  getc()
  system "stty cooked echo"
end
