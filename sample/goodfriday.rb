#! /usr/local/bin/ruby

# goodfriday.rb: Written by Tadayoshi Funaba 1998
# $Id: goodfriday.rb,v 1.3 1999/08/04 14:54:18 tadf Exp $

require 'date2'
require 'holiday'

es = Date.easter(Date.today.year)
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
  puts ((es + xs.shift).to_s + '  ' + xs.shift)
end
