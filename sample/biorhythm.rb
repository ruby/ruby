#!/usr/local/bin/ruby
#
#               biorhythm.rb - 
#                       $Release Version: $
#                       $Revision$
#                       $Date$
#                       by Yasuo OHBA(STAFS Development Room)
#
# --
#
#       
#

include Math
require "date.rb"
require "parsearg.rb"

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
  pi = 3.14159265
  phys = (50.0 * (1.0 + sin((z / 23.0 - (z / 23)) * 360.0 * pi / 180.0))).to_i
  emot = (50.0 * (1.0 + sin((z / 28.0 - (z / 28)) * 360.0 * pi / 180.0))).to_i
  geist =(50.0 * (1.0 + sin((z / 33.0 - (z / 33)) * 360.0 * pi / 180.0))).to_i
  return phys, emot, geist
end

#
# main program
#
parseArgs(0, nil, "vg", "D:", "sdate", "date:", "birthday:", "days:")

if $OPT_D
  dd = Date.new(Time.now.strftime("%Y%m%d"))
  bd = Date.new($OPT_D)
  ausgabeart = "g"
else
  if $OPT_birthday
    bd = Date.new($OPT_birthday)
  else
    printf(STDERR, "Birthday                      (YYYYMMDD) : ")
    if (si = STDIN.gets.chop) != ""
      bd = Date.new(si)
    end
  end
  if !bd
    printf STDERR, "BAD Input Birthday!!\n"
    exit()
  end
  
  if $OPT_sdate
    dd = Date.new(Time.now.strftime("%Y%m%d"))
  elsif $OPT_date
    dd = Date.new($OPT_date)
  else
    printf(STDERR, "Date        [<RETURN> for Systemdate] (YYYYMMDD) : ")
    if (si = STDIN.gets.chop) != ""
      dd = Date.new(si)
    end
  end
  if !dd
    dd = Date.new(Time.now.strftime("%Y%m%d"))
  end

  if $OPT_v
    ausgabeart = "v"
  elsif $OPT_g
    ausgabeart = "g"
  else
    printf(STDERR, "Values for today or Graph  (v/g) [default g] : ")
    ausgabeart = STDIN.gets.chop
  end
end
if (ausgabeart == "v")
  printHeader(bd.year, bd.month, bd.day, dd.period - bd.period, bd.name_of_week)
  print "\n"
  
  phys, emot, geist = getPosition(dd.period - bd.period)
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
    printf(STDERR, "Graph for how many days     [default 10] : ")
    display_period = STDIN.gets.chop
    if (display_period == "")
      display_period = 9
    else
      display_period = display_period.to_i - 1
    end
  end

  printHeader(bd.year, bd.month, bd.day, dd.period - bd.period, bd.name_of_week)
  print "                     P=physical, E=emotional, M=mental\n"
  print "             -------------------------+-------------------------\n"
  print "                     Bad Condition    |    Good Condition\n"
  print "             -------------------------+-------------------------\n"
  
  for z in (dd.period - bd.period)..(dd.period - bd.period + display_period)
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
