require 'rdoc'
require 'rdoc/code_objects'
require 'rdoc/markup/preprocess'
require 'rdoc/stats'

##
# A parser is simple a class that implements
#
#   #initialize(file_name, body, options)
#
# and
#
#   #scan
#
# The initialize method takes a file name to be used, the body of the file,
# and an RDoc::Options object. The scan method is then called to return an
# appropriately parsed TopLevel code object.
#
# The ParseFactory is used to redirect to the correct parser given a
# filename extension. This magic works because individual parsers have to
# register themselves with us as they are loaded in. The do this using the
# following incantation
#
#   require "rdoc/parser"
#
#   class RDoc::Parser::Xyz < RDoc::Parser
#     parse_files_matching /\.xyz$/ # <<<<
#
#     def initialize(file_name, body, options)
#       ...
#     end
#
#     def scan
#       ...
#     end
#   end
#
# Just to make life interesting, if we suspect a plain text file, we also
# look for a shebang line just in case it's a potential shell script

class RDoc::Parser

  @parsers = []

  class << self
    attr_reader :parsers
  end

  ##
  # Alias an extension to another extension. After this call, files ending
  # "new_ext" will be parsed using the same parser as "old_ext"

  def self.alias_extension(old_ext, new_ext)
    old_ext = old_ext.sub(/^\.(.*)/, '\1')
    new_ext = new_ext.sub(/^\.(.*)/, '\1')

    parser = can_parse "xxx.#{old_ext}"
    return false unless parser

    RDoc::Parser.parsers.unshift [/\.#{new_ext}$/, parser]

    true
  end

  ##
  # Determines if the file is a "binary" file which basically means it has
  # content that an RDoc parser shouldn't try to consume.

  def self.binary?(file)
    s = File.read(file, 1024) or return false

    if s[0, 2] == Marshal.dump('')[0, 2] then
      true
    elsif file =~ /erb\.rb$/ then
      false
    elsif s.scan(/<%|%>/).length >= 4 || s.index("\x00") then
      true
    elsif 0.respond_to? :fdiv then
      s.count("\x00-\x7F", "^ -~\t\r\n").fdiv(s.size) > 0.3
    else # HACK 1.8.6
      (s.count("\x00-\x7F", "^ -~\t\r\n").to_f / s.size) > 0.3
    end
  end

  ##
  # Checks if +file+ is a zip file in disguise.  Signatures from
  # http://www.garykessler.net/library/file_sigs.html

  def self.zip? file
    zip_signature = File.read file, 4

    zip_signature == "PK\x03\x04" or
      zip_signature == "PK\x05\x06" or
      zip_signature == "PK\x07\x08"
  end

  ##
  # Return a parser that can handle a particular extension

  def self.can_parse(file_name)
    parser = RDoc::Parser.parsers.find { |regexp,| regexp =~ file_name }.last

    # HACK Selenium hides a jar file using a .txt extension
    return if parser == RDoc::Parser::Simple and zip? file_name

    # The default parser must not parse binary files
    ext_name = File.extname file_name
    return parser if ext_name.empty?
    return if parser == RDoc::Parser::Simple and ext_name !~ /txt|rdoc/

    parser
  end

  ##
  # Find the correct parser for a particular file name. Return a SimpleParser
  # for ones that we don't know

  def self.for(top_level, file_name, body, options, stats)
    return if binary? file_name

    # If no extension, look for shebang
    if file_name !~ /\.\w+$/ && body =~ %r{\A#!(.+)} then
      shebang = $1
      case shebang
      when %r{env\s+ruby}, %r{/ruby}
        file_name = "dummy.rb"
      end
    end

    parser = can_parse file_name

    return unless parser

    parser.new top_level, file_name, body, options, stats
  end

  ##
  # Record which file types this parser can understand.
  #
  # It is ok to call this multiple times.

  def self.parse_files_matching(regexp)
    RDoc::Parser.parsers.unshift [regexp, self]
  end

  def initialize(top_level, file_name, content, options, stats)
    @top_level = top_level
    @file_name = file_name
    @content = content
    @options = options
    @stats = stats
  end

end

require 'rdoc/parser/simple'

