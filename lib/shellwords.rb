#
# shellwords.rb: Split text into an array of tokens a la UNIX shell
#

#
# This module is originally a port of shellwords.pl, but modified to
# conform to POSIX / SUSv3 (IEEE Std 1003.1-2001).
#
# Examples:
#
#   require 'shellwords'
#   words = Shellwords.shellwords(line)
#
# or
#
#   require 'shellwords'
#   include Shellwords
#   words = shellwords(line)
#
module Shellwords

  #
  # Split text into an array of tokens in the same way the UNIX Bourne
  # shell does.
  #
  # See the +Shellwords+ module documentation for an example.
  #
  def shellwords(line)
    line = String.new(line) rescue
      raise(ArgumentError, "Argument must be a string")
    line.lstrip!
    words = []
    until line.empty?
      field = ''
      loop do
	if line.sub!(/\A"(([^"\\]|\\.)*)"/, '') then
	  snippet = $1.gsub(/\\(.)/, '\1')
	elsif line =~ /\A"/ then
	  raise ArgumentError, "Unmatched double quote: #{line}"
	elsif line.sub!(/\A'([^']*)'/, '') then
	  snippet = $1
	elsif line =~ /\A'/ then
	  raise ArgumentError, "Unmatched single quote: #{line}"
	elsif line.sub!(/\A\\(.)?/, '') then
	  snippet = $1 || '\\'
	elsif line.sub!(/\A([^\s\\'"]+)/, '') then
	  snippet = $1
	else
	  line.lstrip!
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
