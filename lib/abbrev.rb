#!/usr/bin/env ruby
#
# Copyright (c) 2001,2003 Akinori MUSHA <knu@iDaemons.org>
#
# All rights reserved.  You can redistribute and/or modify it under
# the same terms as Ruby.
#
# $Idaemons: /home/cvs/rb/abbrev.rb,v 1.2 2001/05/30 09:37:45 knu Exp $
# $RoughId: abbrev.rb,v 1.4 2003/10/14 19:45:42 knu Exp $
# $Id$

module Abbrev
  def abbrev(words, pattern = nil)
    table = {}
    seen = Hash.new(0)

    if pattern.is_a?(String)
      pattern = /^#{Regexp.quote(pattern)}/	# regard as a prefix
    end

    words.each do |word|
      next if (abbrev = word).empty?
      while (len = abbrev.rindex(/[\w\W]\z/)) > 0
	abbrev = word[0,len]

	next if pattern && pattern !~ abbrev

	case seen[abbrev] += 1
	when 1
	  table[abbrev] = word
	when 2
	  table.delete(abbrev)
	else
	  break
	end
      end
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
