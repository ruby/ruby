#! /usr/local/bin/ruby

require "parsedate"
require "base64"

include ParseDate

if ARGV[0] == '-w'
  wait = TRUE
  ARGV.shift
end

class Mail

  def Mail.new(f)
    if !f.kind_of?(IO)
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
      $_.chop!
      next if /^From /	# skip From-line  
      break if /^$/		# end of header
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

ARGV[0] = '/usr/spool/mail/' + ENV['USER'] if ARGV.length == 0

$outcount = 0;
def fromout(date, from, subj)
  return if !date
  y = m = d = 0
  esc = "\033\(B"
  y, m, d = parsedate(date) if date
  from = "sombody@somewhere" if ! from
  subj = "(nil)" if ! subj
  from = decode_b(from)
  subj = decode_b(subj)
  printf "%-02d/%02d/%02d [%-28.28s%s] %-40.40s%s\n",y,m,d,from,esc,subj,esc
  $outcount += 1
end

for file in ARGV
  next if !File.exist?(file)
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
