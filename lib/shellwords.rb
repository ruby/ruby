# shellwords.rb
# original is shellwords.pl
#
# Usage:
#       require 'shellwords.rb'
#       words = Shellwords.shellwords(line)
#
#	   or
#
#       include Shellwords
#       words = shellwords(line)

module Shellwords
  def shellwords(line)
    return '' unless line
    line.sub! /^\s+/, ''
    words = []
    while line != ''
      field = ''
      while TRUE
	if line.sub! /^"(([^"\\]|\\.)*)"/, '' then
	  snippet = $1
	  snippet.gsub! /\\(.)/, '\1'
	elsif line =~ /^"/ then
	  STDOUT.print "Unmatched double quote: $_\n"
	  exit
        elsif line.sub! /^'(([^'\\]|\\.)*)'/, '' then
	  snippet = $1
	  snippet.gsub! /\\(.)/, '\1'
	elsif line =~ /^'/ then
	  STDOUT.print "Unmatched single quote: $_\n"
	  exit
	elsif line.sub! /^\\(.)/, '' then
	  snippet = $1
	elsif line.sub! /^([^\s\\'"]+)/, '' then
	  snippet = $1
	else
	  line.sub! /^\s+/, ''
	  break
	end
	field += snippet
      end
      words += field
    end
    words
  end
  module_function :shellwords
end
