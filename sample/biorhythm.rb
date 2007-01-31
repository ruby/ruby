#!/usr/local/bin/ruby
#
#               biorhythm.rb - 
#                       $Release Version: $
#                       $Revision: 1.9 $
#                       $Date: 2003/05/05 14:02:14 $
#                       by Yasuo OHBA(STAFS Development Room)
#
# --
#
#       
#

# probably based on:
#
# Newsgroups: comp.sources.misc,de.comp.sources.os9
# From: fkk@stasys.sta.sub.org (Frank Kaefer)
# Subject: v41i126:  br - Biorhythm v3.0, Part01/01
# Message-ID: <1994Feb1.070616.15982@sparky.sterling.com>
# Sender: kent@sparky.sterling.com (Kent Landfield)
# Organization: Sterling Software
# Date: Tue, 1 Feb 1994 07:06:16 GMT
#
# Posting-number: Volume 41, Issue 126
# Archive-name: br/part01
# Environment: basic, dos, os9

include Math
require "date.rb"
require "parsearg.rb"
require "parsedate.rb"

def usage()
  print "Usage:\n"
  print "biorhythm.rb [options]\n"
  print "  options...\n"
  print "    -D YYYYMMDD(birthday)     : use default values.\n"
  print "    --sdate | --date YYYYMMDD : use system date; use specified date.\n"
  print "    --birthday YYYYMMDD       : specifies your birthday.\n"
  print "    -v | -g                   : show values or graph.\n"
  print "    --days DAYS               : graph range (only in effect for graphs).\n"
  print "    --help                    : help\n"
end
$USAGE = 'usage'

def printHeader(y, m, d, p, w)
  print "\n>>> Biorhythm <<<\n"
  printf "The birthday %04d.%02d.%02d is a %s\n", y, m, d, w
  printf "Age in days: [%d]\n\n", p
end

def getPosition(z)
  pi = Math::PI
  z = Integer(z)
  phys = (50.0 * (1.0 + sin((z / 23.0 - (z / 23)) * 360.0 * pi / 180.0))).to_i
  emot = (50.0 * (1.0 + sin((z / 28.0 - (z / 28)) * 360.0 * pi / 180.0))).to_i
  geist =(50.0 * (1.0 + sin((z / 33.0 - (z / 33)) * 360.0 * pi / 180.0))).to_i
  return phys, emot, geist
end

def parsedate(s)
  ParseDate::parsedate(s).values_at(0, 1, 2)
end

def name_of_week(date)
  Date::DAYNAMES[date.wday]
end

#
# main program
#
parseArgs(0, nil, "vg", "D:", "sdate", "date:", "birthday:", "days:")

if $OPT_D
  dd = Date.today
  bd = Date.new(*parsedate($OPT_D))
  ausgabeart = "g"
else
  if $OPT_birthday
    bd = Date.new(*parsedate($OPT_birthday))
  else
    STDERR.print("Birthday                      (YYYYMMDD) : ")
    unless (si = STDIN.gets.chop).empty?
      bd = Date.new(*parsedate(si))
    end
  end
  if !bd
    STDERR.print "BAD Input Birthday!!\n"
    exit()
  end

  if $OPT_sdate
    dd = Date.today
  elsif $OPT_date
    dd = Date.new(*parsedate($OPT_date))
  else
    STDERR.print("Date        [<RETURN> for Systemdate] (YYYYMMDD) : ")
    unless (si = STDIN.gets.chop).empty?
      dd = Date.new(*parsedate(si))
    end
  end
  dd ||= Date.today

  if $OPT_v
    ausgabeart = "v"
  elsif $OPT_g
    ausgabeart = "g"
  else
    STDERR.print("Values for today or Graph  (v/g) [default g] : ")
    ausgabeart = STDIN.gets.chop
  end
end
if ausgabeart == "v"
  printHeader(bd.year, bd.month, bd.day, dd - bd, name_of_week(bd))
  print "\n"
  
  phys, emot, geist = getPosition(dd - bd)
  printf "Biorhythm:   %04d.%02d.%02d\n", dd.year, dd.month, dd.day
  printf "Physical:    %d%%\n", phys
  printf "Emotional:   %d%%\n", emot
  printf "Mental:      %d%%\n", geist
  print "\n"
else
  if $OPT_days
    display_period = $OPT_days.to_i
  elsif $OPT_D
    display_period = 9
  else
    STDERR.printf("Graph for how many days     [default 10] : ")
    display_period = STDIN.gets.chop
    if display_period.empty?
      display_period = 9
    else
      display_period = display_period.to_i - 1
    end
  end

  printHeader(bd.year, bd.month, bd.day, dd - bd, name_of_week(bd))
  print "                     P=physical, E=emotional, M=mental\n"
  print "             -------------------------+-------------------------\n"
  print "                     Bad Condition    |    Good Condition\n"
  print "             -------------------------+-------------------------\n"
  
  (dd - bd).step(dd - bd + display_period) do |z|
    phys, emot, geist = getPosition(z)
    
    printf "%04d.%02d.%02d : ", dd.year, dd.month, dd.day
    p = (phys / 2.0 + 0.5).to_i
    e = (emot / 2.0 + 0.5).to_i
    g = (geist / 2.0 + 0.5).to_i
    graph = "." * 51
    graph[25] = ?|
    graph[p] = ?P
    graph[e] = ?E
    graph[g] = ?M
    print graph, "\n"
    dd = dd + 1
  end
  print "             -------------------------+-------------------------\n\n"
end
