#! /usr/local/bin/ruby

require "parsedate"
require "kconv"
require "mailread"

include ParseDate
include Kconv

class String

  def kconv(code = Kconv::EUC)
    Kconv.kconv(self, code, Kconv::AUTO)
  end

  def kjust(len)
    len += 1
    me = self[0, len].ljust(len)
    if me =~ /.$/ and $&.size == 2
      me[-2..-1] = '  '
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
  file = ENV['MAIL']
  user = ENV['USER'] || ENV['USERNAME'] || ENV['LOGNAME'] 
else
  file = user = ARGV[0]
  ARGV.clear
end

if file == nil or !File.exist? file
  [ENV['SPOOLDIR'], '/usr/spool', '/var/spool', '/usr', '/var'].each do |m|
    if File.exist? f = "#{m}/mail/#{user}"
      file = f
      break 
    end
  end
end

$outcount = 0;
def fromout(date, from, subj)
  return if !date
  y, m, d = parsedate(date) if date
  y ||= 0; m ||= 0; d ||= 0
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
  printf "%02d/%02d/%02d [%s] %s\n",y%100,m,d,from,subj
  $outcount += 1
end

if File.exist?(file)
  atime = File.atime(file)
  mtime = File.mtime(file)
  f = open(file, "r")
  begin
    until f.eof?
      mail = Mail.new(f)
      fromout mail.header['Date'],mail.header['From'],mail.header['Subject']
    end
  ensure
    f.close
    File.utime(atime, mtime, file)
  end
end

if $outcount == 0
  print "You have no mail.\n"
  sleep 2 if wait
elsif wait
  system "stty cbreak -echo"
  getc()
  system "stty cooked echo"
end
