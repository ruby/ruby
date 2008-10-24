$DEBUG_RDOC = nil

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
#   read on.
# * If you want to include extensions written in C, see RDoc::Parser::C
# * If you want to drive RDoc programmatically, see RDoc::RDoc.
# * If you want to use the library to format text blocks into HTML, have a look
#   at RDoc::Markup.
# * If you want to try writing your own HTML output template, see
#   RDoc::Generator::HTML
#
# == Summary
#
# Once installed, you can create documentation using the +rdoc+ command
#
#   % rdoc [options] [names...]
#
# For an up-to-date option summary, type
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
#   % rdoc --main rdoc.rb
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
# == \Options
# rdoc can be passed a variety of command-line options.  In addition,
# options can be specified via the +RDOCOPT+ environment variable, which
# functions similarly to the +RUBYOPT+ environment variable.
#
#   % export RDOCOPT="-S"
#
# will make rdoc default to inline method source code.  Command-line options
# always will override those in +RDOCOPT+.
#
# Run
# 
#   % rdoc --help
#
# for full details on rdoc's options.
#
# Here are some of the most commonly used options.
# [-d, --diagram]
#   Generate diagrams showing modules and
#   classes. You need dot V1.8.6 or later to
#   use the --diagram option correctly. Dot is
#   available from http://graphviz.org
#
# [-S, --inline-source]
#   Show method source code inline, rather than via a popup link.
#
# [-T, --template=NAME]
#   Set the template used when generating output.
#
# == Documenting Source Code
#
# Comment blocks can be written fairly naturally, either using +#+ on
# successive lines of the comment, or by including the comment in
# a =begin/=end block.  If you use the latter form, the =begin line must be
# flagged with an RDoc tag:
#
#   =begin rdoc
#   Documentation to be processed by RDoc.
#   
#   ...
#   =end
#
# RDoc stops processing comments if it finds a comment line containing
# a <tt>--</tt>.  This can be used to separate external from internal
# comments, or to stop a comment being associated with a method, class, or
# module.  Commenting can be turned back on with a line that starts with a
# <tt>++</tt>.
#
#   ##
#   # Extract the age and calculate the date-of-birth.
#   #--
#   # FIXME: fails if the birthday falls on February 29th
#   #++
#   # The DOB is returned as a Time object.
#   
#   def get_dob(person)
#     # ...
#   end
#
# Names of classes, files, and any method names containing an
# underscore or preceded by a hash character are automatically hyperlinked
# from comment text to their description.
#
# Method parameter lists are extracted and displayed with the method
# description.  If a method calls +yield+, then the parameters passed to yield
# will also be displayed:
#
#   def fred
#     ...
#     yield line, address
#
# This will get documented as:
#
#   fred() { |line, address| ... }
#
# You can override this using a comment containing ':yields: ...' immediately
# after the method definition
#
#   def fred # :yields: index, position
#     # ...
#   
#     yield line, address
#
# which will get documented as
#
#    fred() { |index, position| ... }
#
# +:yields:+ is an example of a documentation directive.  These appear
# immediately after the start of the document element they are modifying.
#
# == \Markup
#
# * The markup engine looks for a document's natural left margin.  This is
#   used as the initial margin for the document.
#
# * Consecutive lines starting at this margin are considered to be a
#   paragraph.
#
# * If a paragraph starts with a "*", "-", or with "<digit>.", then it is
#   taken to be the start of a list.  The margin in increased to be the first
#   non-space following the list start flag.  Subsequent lines should be
#   indented to this new margin until the list ends.  For example:
#
#      * this is a list with three paragraphs in
#        the first item.  This is the first paragraph.
#
#        And this is the second paragraph.
#
#        1. This is an indented, numbered list.
#        2. This is the second item in that list
#
#        This is the third conventional paragraph in the
#        first list item.
#
#      * This is the second item in the original list
#
# * You can also construct labeled lists, sometimes called description
#   or definition lists.  Do this by putting the label in square brackets
#   and indenting the list body:
#
#       [cat]  a small furry mammal
#              that seems to sleep a lot
#
#       [ant]  a little insect that is known
#              to enjoy picnics
#
#   A minor variation on labeled lists uses two colons to separate the
#   label from the list body:
#
#       cat::  a small furry mammal
#              that seems to sleep a lot
#
#       ant::  a little insect that is known
#              to enjoy picnics
#
#   This latter style guarantees that the list bodies' left margins are
#   aligned: think of them as a two column table.
#
# * Any line that starts to the right of the current margin is treated
#   as verbatim text.  This is useful for code listings.  The example of a
#   list above is also verbatim text.
#
# * A line starting with an equals sign (=) is treated as a
#   heading.  Level one headings have one equals sign, level two headings
#   have two,and so on.
#
# * A line starting with three or more hyphens (at the current indent)
#   generates a horizontal rule.  The more hyphens, the thicker the rule
#   (within reason, and if supported by the output device)
#
# * You can use markup within text (except verbatim) to change the
#   appearance of parts of that text.  Out of the box, RDoc::Markup
#   supports word-based and general markup.
#
#   Word-based markup uses flag characters around individual words:
#
#   [\*word*]  displays word in a *bold* font
#   [\_word_]  displays word in an _emphasized_ font
#   [\+word+]  displays word in a +code+ font
#
#   General markup affects text between a start delimiter and and end
#   delimiter.  Not surprisingly, these delimiters look like HTML markup.
#
#   [\<b>text...</b>]    displays word in a *bold* font
#   [\<em>text...</em>]  displays word in an _emphasized_ font
#   [\\<i>text...</i>]    displays word in an <i>italicized</i> font
#   [\<tt>text...</tt>]  displays word in a +code+ font
#
#   Unlike conventional Wiki markup, general markup can cross line
#   boundaries.  You can turn off the interpretation of markup by
#   preceding the first character with a backslash.  This only works for
#   simple markup, not HTML-style markup.
#
# * Hyperlinks to the web starting http:, mailto:, ftp:, or www. are
#   recognized.  An HTTP url that references an external image file is
#   converted into an inline <IMG..>.  Hyperlinks starting 'link:' are
#   assumed to refer to local files whose path is relative to the --op
#   directory.
#
#   Hyperlinks can also be of the form <tt>label</tt>[url], in which
#   case the label is used in the displayed text, and +url+ is
#   used as the target.  If +label+ contains multiple words,
#   put it in braces: <em>{multi word label}[</em>url<em>]</em>.
#
# == Directives
#
# [+:nodoc:+ / +:nodoc:+ all]
#   This directive prevents documentation for the element from
#   being generated.  For classes and modules, the methods, aliases,
#   constants, and attributes directly within the affected class or
#   module also will be omitted.  By default, though, modules and
#   classes within that class of module _will_ be documented.  This is
#   turned off by adding the +all+ modifier.
#   
#     module MyModule # :nodoc:
#       class Input
#       end
#     end
#     
#     module OtherModule # :nodoc: all
#       class Output
#       end
#     end
#
#   In the above code, only class <tt>MyModule::Input</tt> will be documented.
#   The +:nodoc:+ directive is global across all files for the class or module
#   to which it applies, so use +:stopdoc:+/+:startdoc:+ to suppress
#   documentation only for a particular set of methods, etc.
#
# [+:doc:+]
#   Forces a method or attribute to be documented even if it wouldn't be
#   otherwise.  Useful if, for example, you want to include documentation of a
#   particular private method.
#
# [+:notnew:+]
#   Only applicable to the +initialize+ instance method.  Normally RDoc
#   assumes that the documentation and parameters for +initialize+ are
#   actually for the +new+ method, and so fakes out a +new+ for the class.
#   The +:notnew:+ modifier stops this.  Remember that +initialize+ is private,
#   so you won't see the documentation unless you use the +-a+ command line
#   option.
#
# Comment blocks can contain other directives:
#
# [<tt>:section: title</tt>]
#   Starts a new section in the output.  The title following +:section:+ is
#   used as the section heading, and the remainder of the comment containing
#   the section is used as introductory text.  Subsequent methods, aliases,
#   attributes, and classes will be documented in this section.  A :section:
#   comment block may have one or more lines before the :section: directive.
#   These will be removed, and any identical lines at the end of the block are
#   also removed.  This allows you to add visual cues such as:
#     
#     # ----------------------------------------
#     # :section: My Section
#     # This is the section that I wrote.
#     # See it glisten in the noon-day sun.
#     # ----------------------------------------
#
# [+:call-seq:+]
#   Lines up to the next blank line in the comment are treated as the method's
#   calling sequence, overriding the default parsing of method parameters and
#   yield arguments.
#
# [+:include:+ _filename_]
#   \Include the contents of the named file at this point.  The file will be
#   searched for in the directories listed by the +--include+ option, or in
#   the current directory by default.  The contents of the file will be
#   shifted to have the same indentation as the ':' at the start of
#   the :include: directive.
#
# [+:title:+ _text_]
#   Sets the title for the document.  Equivalent to the <tt>--title</tt>
#   command line parameter.  (The command line parameter overrides any :title:
#   directive in the source).
#
# [+:enddoc:+]
#   Document nothing further at the current level.
#
# [+:main:+ _name_]
#   Equivalent to the <tt>--main</tt> command line parameter.
#
# [+:stopdoc:+ / +:startdoc:+]
#   Stop and start adding new documentation elements to the current container.
#   For example, if a class has a number of constants that you don't want to
#   document, put a +:stopdoc:+ before the first, and a +:startdoc:+ after the
#   last.  If you don't specify a +:startdoc:+ by the end of the container,
#   disables documentation for the entire class or module.
#
# == Other stuff
#
# RDoc is currently being maintained by Eric Hodel <drbrain@segment7.net>
#
# Dave Thomas <dave@pragmaticprogrammer.com> is the original author of RDoc.
#
# == Credits
#
# * The Ruby parser in rdoc/parse.rb is based heavily on the outstanding
#   work of Keiju ISHITSUKA of Nippon Rational Inc, who produced the Ruby
#   parser for irb and the rtags package.
#
# * Code to diagram classes and modules was written by Sergey A Yanovitsky
#   (Jah) of Enticla.
#
# * Charset patch from MoonWolf.
#
# * Rich Kilmer wrote the kilmer.rb output template.
#
# * Dan Brickley led the design of the RDF format.
#
# == License
#
# RDoc is Copyright (c) 2001-2003 Dave Thomas, The Pragmatic Programmers.  It
# is free software, and may be redistributed under the terms specified
# in the README file of the Ruby distribution.
#
# == Warranty
#
# This software is provided "as is" and without any express or implied
# warranties, including, without limitation, the implied warranties of
# merchantibility and fitness for a particular purpose.

module RDoc

  ##
  # Exception thrown by any rdoc error.

  class Error < RuntimeError; end

  RDocError = Error # :nodoc:

  ##
  # RDoc version you are using

  VERSION = "2.2.2"

  ##
  # Name of the dotfile that contains the description of files to be processed
  # in the current directory

  DOT_DOC_FILENAME = ".document"

  GENERAL_MODIFIERS = %w[nodoc].freeze

  CLASS_MODIFIERS = GENERAL_MODIFIERS

  ATTR_MODIFIERS  = GENERAL_MODIFIERS

  CONSTANT_MODIFIERS = GENERAL_MODIFIERS

  METHOD_MODIFIERS = GENERAL_MODIFIERS +
    %w[arg args yield yields notnew not-new not_new doc]

end

