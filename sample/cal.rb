#! /usr/local/bin/ruby

# cal.rb (bsd compatible version): Written by Tadayoshi Funaba 1998
# $Id: bsdcal.rb,v 1.2 1998/12/01 13:47:40 tadf Exp $

require 'date2'

$tab =
{
  'cn' => true,    # China
  'de' => 2342032, # Germany (protestant states)
  'dk' => 2342032, # Denmark
  'es' => 2299161, # Spain
  'fi' => 2361390, # Finland
  'fr' => 2299227, # France
  'gb' => 2361222, # United Kingdom
  'gr' => 2423868, # Greece
  'hu' => 2301004, # Hungary
  'it' => 2299161, # Italy
  'jp' => true,    # Japan
  'no' => 2342032, # Norway
  'pl' => 2299161, # Poland
  'pt' => 2299161, # Portugal
  'ru' => 2421639, # Russia
  'se' => 2361390, # Sweden
  'us' => 2361222, # United States
  'os' => false,   # (old style)
  'ns' => true     # (new style)
}

$cc = 'gb'

def usage
  $stderr.puts 'usage: cal [-c iso3166] [-jy] [[month] year]'
  exit 1
end

def cal(m, y, gs)
  for d in 1..31
    break if jd = Date.exist?(y, m, d, gs)
  end
  fst = cur = Date.new(jd, gs)
  ti = Date::MONTHNAMES[m]
  ti << ' ' << y.to_s unless $yr
  mo = ti.center((($w + 1) * 7) - 1) << "\n"
  mo << ['S', 'M', 'Tu', 'W', 'Th', 'F', 'S'].
    collect{|x| x.rjust($w)}.join(' ') << "\n"
  mo << ' ' * (($w + 1) * fst.wday)
  while cur.mon == fst.mon
    mo << (if $jd then cur.yday else cur.mday end).to_s.rjust($w)
    mo << (if (cur += 1).wday != 0 then "\s" else "\n" end)
  end
  mo << "\n" * (6 - ((fst.wday + (cur - fst)) / 7))
  mo
end

def zip(xs)
  yr = ''
  until xs.empty?
    ln = (if $jd then l,    r, *xs = xs; [l,    r]
		 else l, c, r, *xs = xs; [l, c, r] end).
      collect{|x| x.split(/\n/no, -1)}
    8.times do
      yr << ln.collect{|x|
	x.shift.ljust((($w + 1) * 7) - 1)}.join('  ') << "\n"
    end
  end
  yr
end

while /^-(.*)$/no =~ $*[0]
  a = $1
  if /^c(.+)?$/no =~ a then
    if $1 then
      $cc = $1.downcase
    elsif $*.length >= 2 then
      $cc = $*[1].downcase
      $*.shift
    else
      usage
    end
  else
    a.scan(/./no) do |c|
      case c
      when 'j'; $jd = true
      when 'y'; $yr = true
      else usage
      end
    end
  end
  $*.shift
end
usage if (gs = $tab[$cc]).nil?
case $*.length
when 0
  td = Date.today
  m = td.mon
  y = td.year
when 1
  y = $*[0].to_i
  $yr = true
when 2
  m = $*[0].to_i
  y = $*[1].to_i
else
  usage
end
usage unless m.nil? or (1..12) === m
usage unless y >= -4712
$w = if $jd then 3 else 2 end
unless $yr then
  print cal(m, y, gs)
else
  print y.to_s.center(((($w + 1) * 7) - 1) *
		      (if $jd then 2 else 3 end) +
		      (if $jd then 2 else 4 end)), "\n\n",
    zip((1..12).collect{|m| cal(m, y, gs)}), "\n"
end
