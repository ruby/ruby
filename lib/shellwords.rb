# shellwords.rb
# original is shellwords.pl
#
# Usage:
#       require 'shellwords'
#       words = Shellwords.shellwords(line)
#
#	   or
#
#       require 'shellwords'
#       include Shellwords
#       words = shellwords(line)

module Shellwords
  def shellwords(line)
    unless line.kind_of?(String)
      raise ArgumentError, "Argument must be String class object."
    end
    line = line.sub(/\A\s+/, '')
    words = []
    while line != ''
      field = ''
      while true
	if line.sub!(/\A"(([^"\\]|\\.)*)"/, '') then #"
	  snippet = $1
	  snippet.gsub!(/\\(.)/, '\1')
	elsif line =~ /\A"/ then #"
	  raise ArgumentError, "Unmatched double quote: #{line}"
        elsif line.sub!(/\A'(([^'\\]|\\.)*)'/, '') then #'
	  snippet = $1
	  snippet.gsub!(/\\(.)/, '\1')
	elsif line =~ /\A'/ then #'
	  raise ArgumentError, "Unmatched single quote: #{line}"
	elsif line.sub!(/\A\\(.)/, '') then
	  snippet = $1
	elsif line.sub!(/\A([^\s\\'"]+)/, '') then #'
	  snippet = $1
	else
	  line.sub!(/\A\s+/, '')
	  break
	end
	field.concat(snippet)
      end
      words.push(field)
    end
    words
  end
  module_function :shellwords
end
