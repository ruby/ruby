#! /usr/bin/env ruby

# goodfriday.rb: Written by Tadayoshi Funaba 1998, 2000, 2002
# $Id: goodfriday.rb,v 1.1 1998-03-08 18:44:44+09 tadf Exp $

require 'date'

def easter(y)
  g = (y % 19) + 1
  c = (y / 100) + 1
  x = (3 * c / 4) - 12
  z = ((8 * c + 5) / 25) - 5
  d = (5 * y / 4) - x - 10
  e = (11 * g + 20 + z - x) % 30
  e += 1 if e == 25 and g > 11 or e == 24
  n = 44 - e
  n += 30 if n < 21
  n = n + 7 - ((d + n) % 7)
  if n <= 31 then [y, 3, n] else [y, 4, n - 31] end
end

es = Date.new(*easter(Time.now.year))
[[-9*7, 'Septuagesima Sunday'],
 [-8*7, 'Sexagesima Sunday'],
 [-7*7, 'Quinquagesima Sunday (Shrove Sunday)'],
 [-48,  'Shrove Monday'],
 [-47,  'Shrove Tuesday'],
 [-46,  'Ash Wednesday'],
 [-6*7, 'Quadragesima Sunday'],
 [-3*7, 'Mothering Sunday'],
 [-2*7, 'Passion Sunday'],
 [-7,   'Palm Sunday'],
 [-3,   'Maunday Thursday'],
 [-2,   'Good Friday'],
 [-1,   'Easter Eve'],
 [0,    'Easter Day'],
 [1,    'Easter Monday'],
 [7,    'Low Sunday'],
 [5*7,  'Rogation Sunday'],
 [39,   'Ascension Day (Holy Thursday)'],
 [42,   'Sunday after Ascension Day'],
 [7*7,  'Pentecost (Whitsunday)'],
 [50,   'Whitmonday'],
 [8*7,  'Trinity Sunday'],
 [60,   'Corpus Christi (Thursday after Trinity)']].
each do |xs|
  puts((es + xs.shift).to_s + '  ' + xs.shift)
end
