#!/mp/free/bin/ruby
#
#		biorhythm.rb - 
#			$Release Version: $
#			$Revision: 1.6 $
#			$Date: 1994/02/24 10:23:34 $
#			by Yasuo OHBA(STAFS Development Room)
#
# --
#
#	
#

$RCS_ID="$Header: /var/ohba/RCS/biorhythm.rb,v 1.6 1994/02/24 10:23:34 ohba Exp ohba $"

include Math
load("parsearg.rb")

$wochentag = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" ]
monatstag1 = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
monatstag2 = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

def usage()
  print("Usage:\n")
  print("biorhythm.rb [options]\n")
  print("  options...\n")
  print("    -D YYYYMMDD(birthday)     : すべて default 値を使う. \n")
  print("    --sdate | --date YYYYMMDD : system date もしくは指定した日付を使う.\n")
  print("    --birthday YYYYMMDD       : 誕生日の指定をする.  \n")
  print("    -v | -g                   : Values or Graph の指定. \n")
  print("    --days DAYS               : 期間の指定をする(Graph の時のみ有効). \n")
  print("    --help                    : help\n")
end
$USAGE = 'usage'

def leapyear(y)
  ta = 0
  if ((y % 4.0) == 0); ta = 1; end
  if ((y % 100.0) == 0); ta = 0; end
  if ((y % 400.0) == 0); ta = 1; end
  return ta
end
  
def bcalc(t, m, j)
  ta = 0
  if (m <= 2)
    ta = (m - 1) * 31
  else
    ta = leapyear(j)
    ta = ta + ((306 * m - 324) / 10.0).to_i
  end
  ta = ta + (j - 1) * 365 + ((j - 1) / 4.0).to_i
  ta = ta - ((j - 1) / 100) + ((j - 1) / 400.0).to_i
  ta = ta + t
  return ta
end

def printHeader(tg, mg, jg, gtag, tage)
  print("\n")
  print("    Biorhythm\n")
  print("    =========\n")
  print("\n")
  printf("The birthday %04d.%02d.%02d is a %s\n", jg, mg, tg, $wochentag[gtag])
  printf("Age in days: [%d]\n", tage)
end

def getPosition(z)
  pi = 3.14159265
  $phys = (50.0 * (1.0 + sin((z / 23.0 - (z / 23)) * 360.0 * pi / 180.0))).to_i
  $emot = (50.0 * (1.0 + sin((z / 28.0 - (z / 28)) * 360.0 * pi / 180.0))).to_i
  $geist =(50.0 * (1.0 + sin((z / 33.0 - (z / 33)) * 360.0 * pi / 180.0))).to_i
end

#
# main program
#
parseArgs(0, nil, "vg", "D:", "sdate", "date:", "birthday:", "days:")

printf($stderr, "\n")
printf($stderr, "Biorhythm (c) 1987-1994 V3.0\n")
printf($stderr, "\n")
if ($OPT_D)
  dtmp = Time.now.strftime("%Y%m%d")
  jh = dtmp[0,4].to_i
  mh = dtmp[4,2].to_i
  th = dtmp[6,2].to_i
  dtmp = $OPT_D
  jg = dtmp[0,4].to_i
  mg = dtmp[4,2].to_i
  tg = dtmp[6,2].to_i
  gtag = bcalc(tg, mg, jg) % 7
  ausgabeart = "g"
else
  if ($OPT_birthday)
    dtmp = $OPT_birthday
  else
    printf($stderr, "Birthday 			  (YYYYMMDD) : ")
    dtmp = $stdin.gets.chop
  end
  if (dtmp.length != 8)
    printf($stderr, "BAD Input Birthday!!\n")
    exit()
  end
  jg = dtmp[0,4].to_i
  mg = dtmp[4,2].to_i
  tg = dtmp[6,2].to_i
  
  gtag = bcalc(tg, mg, jg) % 7
  
  if ($OPT_sdate)
    dtmp = Time.now.strftime("%Y%m%d")
  elsif ($OPT_date)
    dtmp = $OPT_date
  else
    printf($stderr, "Date	[<RETURN> for Systemdate] (YYYYMMDD) : ")
    dtmp = $stdin.gets.chop
  end
  if (dtmp.length != 8)
    dtmp = Time.now.strftime("%Y%m%d")
  end
  jh = dtmp[0,4].to_i
  mh = dtmp[4,2].to_i
  th = dtmp[6,2].to_i
  
  if ($OPT_v)
    ausgabeart = "v"
  elsif ($OPT_g)
    ausgabeart = "g"
  else
    printf($stderr, "Values for today or Graph  (v/g) [default g] : ")
    ausgabeart = $stdin.gets.chop
  end
end
if (ausgabeart == "v")
  tag = bcalc(tg, mg, jg)
  tah = bcalc(th, mh, jh)
  tage = tah - tag
  printHeader(tg, mg, jg, gtag, tage)
  print("\n")
  
  getPosition(tage)
  printf("Biorhythm:   %04d.%02d.%02d\n", jh, mh, th)
  printf("Physical:    %d%%\n", $phys)
  printf("Emotional:   %d%%\n", $emot)
  printf("Mental:      %d%%\n", $geist)
  print("\n")
else
  if ($OPT_days)
    ktage = $OPT_days.to_i
  else
    if ($OPT_D)
      ktage = 9
    else
      printf($stderr, "Graph for how many days 	[default 10] : ")
      ktage = $stdin.gets.chop
      if (ktage == "")
	ktage = 9
      else
	ktage = ktage.to_i - 1
      end
    end
  end
  tag = bcalc(tg, mg, jg)
  tah = bcalc(th, mh, jh)
  tage = tah - tag
  printHeader(tg, mg, jg, gtag, tage)
  print("		      P=physical, E=emotional, M=mental\n")
  print("             -------------------------+-------------------------\n")
  print("                     Bad Condition    |    Good Condition\n")
  print("             -------------------------+-------------------------\n")
  
  for z in tage..(tage + ktage)
    getPosition(z)
    
    printf("%04d.%02d.%02d : ", jh, mh, th)
    p = ($phys / 2.0 + 0.5).to_i
    e = ($emot / 2.0 + 0.5).to_i
    g = ($geist / 2.0 + 0.5).to_i
    graph = "." * 51
    graph[25] = ?|
    graph[p] = ?P
    graph[e] = ?E
    graph[g] = ?M
    print(graph, "\n")
    th = th + 1
    if (leapyear(jh) == 0)
      $MONATSTAG = monatstag1
    else
      $MONATSTAG = monatstag2
    end
    if (th > $MONATSTAG[mh - 1])
      mh = mh + 1
      th = 1
    end
    if (mh > 12)
      jh = jh + 1
      mh = 1
    end
  end
  print("             -------------------------+-------------------------\n\n")
end
