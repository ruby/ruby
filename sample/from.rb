#! /usr/local/bin/ruby

require "parsedate"
require "kconv"
require "mailread"

include ParseDate
include Kconv

class String

  public :kconv

  def kconv(code = Kconv::EUC)
    Kconv.kconv(self, code, Kconv::AUTO)
  end

  def kjust(len)
    len += 1
    me = self[0, len].ljust(len)
    if me =~ /.$/ and $&.size == 2
      me[-2, 2] = '  '
    end
    me.chop!
  end

end

if ARGV[0] == '-w'
  wait = TRUE
  ARGV.shift
end

if ARGV.length == 0
  user = ENV['USER']
else
  user = ARGV[0]
end

[ENV['SPOOLDIR'], '/usr/spool', '/var/spool', '/usr', '/var'].each do |m|
  break if File.exist? ARGV[0] = "#{m}/mail/#{user}" 
end

$outcount = 0;
def fromout(date, from, subj)
  return if !date
  y = m = d = 0
  y, m, d = parsedate(date) if date
  if from
    from.gsub! /\n/, ""
  else
    from = "sombody@somewhere"
  end
  if subj
    subj.gsub! /\n/, ""
  else
    subj = "(nil)"
  end
  if ENV['LANG'] =~ /sjis/i
    lang = Kconv::SJIS
  else
    lang = Kconv::EUC
  end
  from = from.kconv(lang).kjust(28)
  subj = subj.kconv(lang).kjust(40)
  printf "%02d/%02d/%02d [%s] %s\n",y,m,d,from,subj
  $outcount += 1
end

for file in ARGV
  next if !File.exist?(file)
  f = open(file, "r")
  while !f.eof?
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
