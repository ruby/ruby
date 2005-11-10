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
    words = []
    field = ''
    word = sq = dq = esc = garbage = sep = nil
    line.scan(/\G\s*(?>([^\s\\\'\"]+)|'([^\']*)'|"((?:[^\"\\]|\\.)*)"|(\\.?)|(\S))(\s|\z)?/m) do
      |word, sq, dq, esc, garbage, sep|
      raise ArgumentError, "Unmatched double quote: #{line.inspect}" if garbage
      field << (word || sq || (dq || esc).gsub(/\\(?=.)/, ''))
      if sep
        words << field
        field = ''
      end
    end
    words
  end

  module_function :shellwords
end
