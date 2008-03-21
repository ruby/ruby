#
# shellwords.rb: Manipulates strings a la UNIX Bourne shell
#

#
# This module manipulates strings according to the word parsing rules
# of the UNIX Bourne shell.
#
# The shellwords() function was originally a port of shellwords.pl,
# but modified to conform to POSIX / SUSv3 (IEEE Std 1003.1-2001).
#
# Authors:
#   - Wakou Aoyama
#   - Akinori MUSHA <knu@iDaemons.org>
#
# Contact:
#   - Akinori MUSHA <knu@iDaemons.org> (current maintainer)
#
module Shellwords
  #
  # Splits a string into an array of tokens in the same way the UNIX
  # Bourne shell does.
  #
  #   argv = Shellwords.split('here are "two words"')
  #   argv #=> ["here", "are", "two words"]
  #
  # +String#shellsplit+ is a shorthand for this function.
  #
  #   argv = 'here are "two words"'.shellsplit
  #   argv #=> ["here", "are", "two words"]
  #
  def shellsplit(line)
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

  alias shellwords shellsplit

  module_function :shellsplit, :shellwords

  class << self
    alias split shellsplit
  end

  #
  # Escapes a string so that it can be safely used in a Bourne shell
  # command line.
  #
  # Note that a resulted string should be used unquoted and is not
  # intended for use in double quotes nor in single quotes.
  #
  #   open("| grep #{Shellwords.escape(pattern)} file") { |pipe|
  #     # ...
  #   }
  #
  # +String#shellescape+ is a shorthand for this function.
  #
  #   open("| grep #{pattern.shellescape} file") { |pipe|
  #     # ...
  #   }
  #
  def shellescape(str)
    # An empty argument will be skipped, so return empty quotes.
    return "''" if str.empty?

    str = str.dup

    # Process as a single byte sequence because not all shell
    # implementations are multibyte aware.
    str.gsub!(/([^A-Za-z0-9_\-.,:\/@\n])/n, "\\\\\\1")

    # A LF cannot be escaped with a backslash because a backslash + LF
    # combo is regarded as line continuation and simply ignored.
    str.gsub!(/\n/, "'\n'")

    return str
  end

  module_function :shellescape

  class << self
    alias escape shellescape
  end

  #
  # Builds a command line string from an argument list +array+ joining
  # all elements escaped for Bourne shell and separated by a space.
  #
  #   open('|' + Shellwords.join(['grep', pattern, *files])) { |pipe|
  #     # ...
  #   }
  #
  # +Array#shelljoin+ is a shorthand for this function.
  #
  #   open('|' + ['grep', pattern, *files].shelljoin) { |pipe|
  #     # ...
  #   }
  #
  def shelljoin(array)
    array.map { |arg| shellescape(arg) }.join(' ')
  end

  module_function :shelljoin

  class << self
    alias join shelljoin
  end
end

class String
  #
  # call-seq:
  #   str.shellsplit => array
  #
  # Splits +str+ into an array of tokens in the same way the UNIX
  # Bourne shell does.  See +Shellwords::shellsplit+ for details.
  #
  def shellsplit
    Shellwords.split(self)
  end

  #
  # call-seq:
  #   str.shellescape => string
  #
  # Escapes +str+ so that it can be safely used in a Bourne shell
  # command line.  See +Shellwords::shellescape+ for details.
  #
  def shellescape
    Shellwords.escape(self)
  end
end

class Array
  #
  # call-seq:
  #   array.shelljoin => string
  #
  # Builds a command line string from an argument list +array+ joining
  # all elements escaped for Bourne shell and separated by a space.
  # See +Shellwords::shelljoin+ for details.
  #
  def shelljoin
    Shellwords.join(self)
  end
end
