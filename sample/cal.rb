#! /usr/local/bin/ruby

# cal.rb: Written by Tadayoshi Funaba 1998-2000
# $Id: cal.rb,v 1.10 2000/05/20 02:09:47 tadf Exp $

require 'date2'
require 'getopts'

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
  $stderr.puts 'usage: cal [-c iso3166] [-jmty] [[month] year]'
  exit 1
end

def pict(y, m, sg)
  d = (1..31).detect{|d| Date.exist?(y, m, d, sg)}
  fi = Date.new3(y, m, d, sg)
  fi -= (fi.jd - $k + 1) % 7

  ve  = (fi..fi +  6).collect{|cu|
    %w(S M Tu W Th F S)[cu.wday]
  }
  ve += (fi..fi + 41).collect{|cu|
    if cu.mon == m then cu.send($da) end.to_s
  }

  ve = ve.collect{|e| e.rjust($dw)}

  gr = group(ve, 7)
  gr = trans(gr) if $OPT_t
  ta = gr.collect{|xs| xs.join(' ')}

  ca = %w(January   February  March     April
	  May       June      July      August
	  September October   November  December)[m - 1]
  ca = ca + ' ' + y.to_s if not $OPT_y
  ca = ca.center($mw)

  ta.unshift(ca)
end

def group(xs, n)
  (0..xs.size / n - 1).collect{|i| xs[i * n, n]}
end

def trans(xs)
  (0..xs[0].size - 1).collect{|i| xs.collect{|x| x[i]}}
end

def unite(xs)
  if xs.empty? then [] else xs[0] + unite(xs[1..-1]) end
end

def block(xs, n)
  unite(group(xs, n).collect{|ys| trans(ys).collect{|zs| zs.join('  ')}})
end

def unlines(xs)
  xs.collect{|x| x + "\n"}.join
end

usage unless getopts('jmty', "c:#{$cc}")

y, m = ARGV.indexes(1, 0).compact.collect{|x| x.to_i}
$OPT_y ||= (y and not m)

to = Date.today
y ||= to.year
m ||= to.mon

usage unless m >= 1 and m <= 12
usage unless y >= -4712
usage unless sg = $tab[$OPT_c]

$dw = if $OPT_j then 3 else 2 end
$mw = ($dw + 1) * 7 - 1
$mn = if $OPT_j then 2 else 3 end
$tw = ($mw + 2) * $mn - 2

$k  = if $OPT_m then 1 else 0 end
$da = if $OPT_j then :yday else :mday end

print (if not $OPT_y
	 unlines(pict(y, m, sg))
       else
	 y.to_s.center($tw) + "\n\n" +
	   unlines(block((1..12).collect{|m| pict(y, m, sg)}, $mn)) + "\n"
       end)
