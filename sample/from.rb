#! /usr/local/bin/ruby

module ParseDate
  MONTHS = {
    'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4,
    'may' => 5, 'jun' => 6, 'jul' => 7, 'aug' => 8,
    'sep' => 9, 'oct' =>10, 'nov' =>11, 'dec' =>12 }
  MONTHPAT = MONTHS.keys.join('|')
  DAYPAT = 'mon|tue|wed|thu|fri|sat|sun'
  
  def parsedate(date) 
    if date.sub(/(#{DAYPAT})/i, ' ')
      dayofweek = $1
    end
    if date.sub(/\s+(\d+:\d+(:\d+)?)/, ' ')
      time = $1
    end
    if date =~ /19(\d\d)/
      year = $1
    end
    if date.sub(/\s*(\d+)\s+(#{MONTHPAT})\S*\s+/i, ' ')
      dayofmonth = $1
      monthname  = $2
    elsif date.sub(/\s*(#{MONTHPAT})\S*\s+(\d+)\s+/i, ' ')
      monthname  = $1
      dayofmonth = $2
    elsif date.sub(/\s*(#{MONTHPAT})\S*\s+(\d+)\D+/i, ' ')
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

include ParseDate

def decode64(str)
  e = -1;
  c = ","
  for line in str.split("\n")
    line.tr 'A-Za-z0-9+/', "\000-\377"
    line.each_byte { |ch|
      e+=1
      if e==0
	c = ch << 2
      elsif e==1
	c |= ch >>4
	string += [c].pack('c')
	c = ch << 4
      elsif e == 2
	c |= ch >> 2
	string += [c].pack('c'); 
	c = ch << 6
      elsif e==3
	c |= ch
	string += [c].pack('c')
	e = -1;
      end
    }
  end
  return string;
end

def j2e(str)
  while str =~ /\033\$B([^\033]*)\033\(B/
    s = $1
    pre, post = $`, $'
    s.gsub(/./) { |ch|
      (ch[0]|0x80).chr
    }
    str = pre + s + post
  end
  str
end

def decode_b(str)
  while str =~ /=\?ISO-2022-JP\?B\?(.*)=\?=/
    pre, post = $`, $'
    s = decode64($1)
    str =  pre + s + post
  end
  j2e(str)
end

if $ARGV[0] == '-w'
  wait = TRUE
  $ARGV.shift
end

class Mail

  def Mail.new(f)
    if !f.is_kind_of(IO)
      f = open(f, "r")
      me = super
      f.close
    else
      me = super
    end
    return me
  end

  def initialize(f)
    @header = {}
    @body = []
    while f.gets()
      $_.chop
      continue if /^From /	# skip From-line  
      break if /^[ \t]*$/	# end of header
      if /^(\S+):\s*(.*)/
	@header[attr = $1.capitalize] = $2
      elsif attr
	sub(/^\s*/, '')
	@header[attr] += "\n" + $_
      end
    end

    return if ! $_

    while f.gets()
      break if /^From /
      @body.push($_)
    end
  end

  def header
    return @header
  end

  def body
    return @body
  end

end

$ARGV[0] = '/usr/spool/mail/' + ENV['USER'] if $ARGV.length == 0

$outcount = 0;
def fromout(date, from, subj)
  return if !date
  y = m = d = 0
  y, m, d = parsedate(date) if date
  from = "sombody@somewhere" if ! from
  subj = "(nil)" if ! subj
  from = decode_b(from)
  subj = decode_b(subj)
  printf "%-02d/%02d/%02d [%-28.28s] %-40.40s\n", y, m, d, from, subj
  $outcount += 1
end

for file in $ARGV
  continue if !File.exists(file)
  f = open(file, "r")
  while !f.eof
    mail = Mail.new(f)
    fromout mail.header['Date'], mail.header['From'], mail.header['Subject']
  end
  f.close
end

if $outcount == 0
  print "You have no mail.\n"
  sleep 2 if wait
elsif wait
  system "stty cbreak -echo"
  getc()
  system "stty cooked echo"
end
