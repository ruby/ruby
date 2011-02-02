$DEBUG_RDOC = nil

# :main: README.txt

##
# = \RDoc - Ruby Documentation System
#
# This package contains RDoc and RDoc::Markup.  RDoc is an application that
# produces documentation for one or more Ruby source files.  It works similarly
# to JavaDoc, parsing the source, and extracting the definition for classes,
# modules, and methods (along with includes and requires).  It associates with
# these optional documentation contained in the immediately preceding comment
# block, and then renders the result using a pluggable output formatter.
# RDoc::Markup is a library that converts plain text into various output
# formats.  The markup library is used to interpret the comment blocks that
# RDoc uses to document methods, classes, and so on.
#
# == Roadmap
#
# * If you want to use RDoc to create documentation for your Ruby source files,
#   read the summary below, and refer to <tt>rdoc --help</tt> for command line
#   usage, and RDoc::Markup for a detailed description of RDoc's markup.
# * If you want to generate documentation for extensions written in C, see
#   RDoc::Parser::C
# * If you want to drive RDoc programmatically, see RDoc::RDoc.
# * If you want to use the library to format text blocks into HTML, look at
#   RDoc::Markup.
# * If you want to make an RDoc plugin such as a generator or directive
#   handler see RDoc::RDoc.
# * If you want to try writing your own output generator see RDoc::Generator.
#
# == Summary
#
# Once installed, you can create documentation using the +rdoc+ command
#
#   % rdoc [options] [names...]
#
# For an up-to-date option summary, type
#
#   % rdoc --help
#
# A typical use might be to generate documentation for a package of Ruby
# source (such as RDoc itself).
#
#   % rdoc
#
# This command generates documentation for all the Ruby and C source
# files in and below the current directory.  These will be stored in a
# documentation tree starting in the subdirectory +doc+.
#
# You can make this slightly more useful for your readers by having the
# index page contain the documentation for the primary file.  In our
# case, we could type
#
#   % rdoc --main README.txt
#
# You'll find information on the various formatting tricks you can use
# in comment blocks in the documentation this generates.
#
# RDoc uses file extensions to determine how to process each file.  File names
# ending +.rb+ and +.rbw+ are assumed to be Ruby source.  Files
# ending +.c+ are parsed as C files.  All other files are assumed to
# contain just Markup-style markup (with or without leading '#' comment
# markers).  If directory names are passed to RDoc, they are scanned
# recursively for C and Ruby source files only.
#
# == Other stuff
#
# RDoc is currently being maintained by Eric Hodel <drbrain@segment7.net>.
#
# Dave Thomas <dave@pragmaticprogrammer.com> is the original author of RDoc.
#
# == Credits
#
# * The Ruby parser in rdoc/parse.rb is based heavily on the outstanding
#   work of Keiju ISHITSUKA of Nippon Rational Inc, who produced the Ruby
#   parser for irb and the rtags package.

module RDoc

  ##
  # Exception thrown by any rdoc error.

  class Error < RuntimeError; end

  def self.const_missing const_name # :nodoc:
    if const_name.to_s == 'RDocError' then
      warn "RDoc::RDocError is deprecated"
      return Error
    end

    super
  end

  ##
  # RDoc version you are using

  VERSION = '3.5.1'

  ##
  # Method visibilities

  VISIBILITIES = [:public, :protected, :private]

  ##
  # Name of the dotfile that contains the description of files to be processed
  # in the current directory

  DOT_DOC_FILENAME = ".document"

  ##
  # General RDoc modifiers

  GENERAL_MODIFIERS = %w[nodoc].freeze

  ##
  # RDoc modifiers for classes

  CLASS_MODIFIERS = GENERAL_MODIFIERS

  ##
  # RDoc modifiers for attributes

  ATTR_MODIFIERS = GENERAL_MODIFIERS

  ##
  # RDoc modifiers for constants

  CONSTANT_MODIFIERS = GENERAL_MODIFIERS

  ##
  # RDoc modifiers for methods

  METHOD_MODIFIERS = GENERAL_MODIFIERS +
    %w[arg args yield yields notnew not-new not_new doc]

end

