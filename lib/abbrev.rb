#!/usr/bin/env ruby
#--
# Copyright (c) 2001,2003 Akinori MUSHA <knu@iDaemons.org>
#
# All rights reserved.  You can redistribute and/or modify it under
# the same terms as Ruby.
#
# $Idaemons: /home/cvs/rb/abbrev.rb,v 1.2 2001/05/30 09:37:45 knu Exp $
# $RoughId: abbrev.rb,v 1.4 2003/10/14 19:45:42 knu Exp $
# $Id$
#++

##
# Calculates the set of unique abbreviations for a given set of strings.
#
#   require 'abbrev'
#   require 'pp'
#
#   pp Abbrev.abbrev(['ruby', 'rules'])
#
# Generates:
#
#   { "rub"   =>  "ruby",
#     "ruby"  =>  "ruby",
#     "rul"   =>  "rules",
#     "rule"  =>  "rules",
#     "rules" =>  "rules" }
#
# It also provides an array core extension, Array#abbrev.
#
#   pp %w{summer winter}.abbrev
#   #=> {"summe"=>"summer",
#        "summ"=>"summer",
#        "sum"=>"summer",
#        "su"=>"summer",
#        "s"=>"summer",
#        "winte"=>"winter",
#        "wint"=>"winter",
#        "win"=>"winter",
#        "wi"=>"winter",
#        "w"=>"winter",
#        "summer"=>"summer",
#        "winter"=>"winter"}

module Abbrev

  # Given a set of strings, calculate the set of unambiguous
  # abbreviations for those strings, and return a hash where the keys
  # are all the possible abbreviations and the values are the full
  # strings.
  #
  # Thus, given +words+ is "car" and "cone", the keys pointing to "car" would
  # be "ca" and "car", while those pointing to "cone" would be "co", "con", and
  # "cone".
  #
  #   require 'abbrev'
  #
  #   Abbrev.abbrev(['car', 'cone'])
  #   #=> {"ca"=>"car", "con"=>"cone", "co"=>"cone", "car"=>"car", "cone"=>"cone"}
  #
  # The optional +pattern+ parameter is a pattern or a string. Only
  # input strings that match the pattern or start with the string
  # are included in the output hash.
  #
  #   Abbrev.abbrev(%w{car box cone}, /b/)
  #   #=> {"bo"=>"box", "b"=>"box", "box"=>"box"}
  def abbrev(words, pattern = nil)
    table = {}
    seen = Hash.new(0)

    if pattern.is_a?(String)
      pattern = /\A#{Regexp.quote(pattern)}/  # regard as a prefix
    end

    words.each do |word|
      next if word.empty?
      word.size.downto(1) { |len|
        abbrev = word[0...len]

        next if pattern && pattern !~ abbrev

        case seen[abbrev] += 1
        when 1
          table[abbrev] = word
        when 2
          table.delete(abbrev)
        else
          break
        end
      }
    end

    words.each do |word|
      next if pattern && pattern !~ word

      table[word] = word
    end

    table
  end

  module_function :abbrev
end

class Array
  # Calculates the set of unambiguous abbreviations for the strings in
  # +self+.
  #
  #   require 'abbrev'
  #   %w{ car cone }.abbrev
  #   #=> {"ca" => "car", "con"=>"cone", "co" => "cone",
  #        "car"=>"car", "cone" => "cone"}
  #
  # The optional +pattern+ parameter is a pattern or a string. Only
  # input strings that match the pattern or start with the string
  # are included in the output hash.
  #
  #   %w{ fast boat day }.abbrev(/^.a/)
  #   #=> {"fas"=>"fast", "fa"=>"fast", "da"=>"day",
  #        "fast"=>"fast", "day"=>"day"}
  #
  # See also Abbrev.abbrev
  def abbrev(pattern = nil)
    Abbrev::abbrev(self, pattern)
  end
end

if $0 == __FILE__
  while line = gets
    hash = line.split.abbrev

    hash.sort.each do |k, v|
      puts "#{k} => #{v}"
    end
  end
end
