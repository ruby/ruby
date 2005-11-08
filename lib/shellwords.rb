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
    words = []
    field = ''
    last = 0
    sep = nil
    line.scan(/\G\s*(?:([^\s\\\'\"]+)|'([^\']*)'|"((?:[^\"\\]|\\.)*)"|(\\.?))(\s+|\z)?/m) do
      last = $~.end(0)
      sep = $~.begin(5)
      field << ($1 || $2 || ($3 || $4).gsub(/\\(?=.)/, ''))
      if sep
        words << field
        field = ''
      end
    end
    raise ArgumentError, "Unmatched double quote: #{line}" if line[last]
    words
  end

  module_function :shellwords
end
