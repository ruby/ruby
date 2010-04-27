require 'rdoc'

##
# RDoc::Markup parses plain text documents and attempts to decompose them into
# their constituent parts.  Some of these parts are high-level: paragraphs,
# chunks of verbatim text, list entries and the like.  Other parts happen at
# the character level: a piece of bold text, a word in code font.  This markup
# is similar in spirit to that used on WikiWiki webs, where folks create web
# pages using a simple set of formatting rules.
#
# RDoc::Markup itself does no output formatting: this is left to a different
# set of classes.
#
# RDoc::Markup is extendable at runtime: you can add \new markup elements to
# be recognised in the documents that RDoc::Markup parses.
#
# RDoc::Markup is intended to be the basis for a family of tools which share
# the common requirement that simple, plain-text should be rendered in a
# variety of different output formats and media.  It is envisaged that
# RDoc::Markup could be the basis for formatting RDoc style comment blocks,
# Wiki entries, and online FAQs.
#
# == Synopsis
#
# This code converts +input_string+ to HTML.  The conversion takes place in
# the +convert+ method, so you can use the same RDoc::Markup converter to
# convert multiple input strings.
#
#   require 'rdoc/markup/to_html'
#
#   h = RDoc::Markup::ToHtml.new
#
#   puts h.convert(input_string)
#
# You can extend the RDoc::Markup parser to recognise new markup
# sequences, and to add special processing for text that matches a
# regular expression.  Here we make WikiWords significant to the parser,
# and also make the sequences {word} and \<no>text...</no> signify
# strike-through text.  When then subclass the HTML output class to deal
# with these:
#
#   require 'rdoc/markup'
#   require 'rdoc/markup/to_html'
#
#   class WikiHtml < RDoc::Markup::ToHtml
#     def handle_special_WIKIWORD(special)
#       "<font color=red>" + special.text + "</font>"
#     end
#   end
#
#   m = RDoc::Markup.new
#   m.add_word_pair("{", "}", :STRIKE)
#   m.add_html("no", :STRIKE)
#
#   m.add_special(/\b([A-Z][a-z]+[A-Z]\w+)/, :WIKIWORD)
#
#   wh = WikiHtml.new
#   wh.add_tag(:STRIKE, "<strike>", "</strike>")
#
#   puts "<body>#{wh.convert ARGF.read}</body>"
#
#--
# Author::   Dave Thomas,  dave@pragmaticprogrammer.com
# License::  Ruby license

class RDoc::Markup

  attr_reader :attribute_manager

  ##
  # Take a block of text and use various heuristics to determine it's
  # structure (paragraphs, lists, and so on).  Invoke an event handler as we
  # identify significant chunks.

  def initialize
    @attribute_manager = RDoc::Markup::AttributeManager.new
    @output = nil
  end

  ##
  # Add to the sequences used to add formatting to an individual word (such
  # as *bold*).  Matching entries will generate attributes that the output
  # formatters can recognize by their +name+.

  def add_word_pair(start, stop, name)
    @attribute_manager.add_word_pair(start, stop, name)
  end

  ##
  # Add to the sequences recognized as general markup.

  def add_html(tag, name)
    @attribute_manager.add_html(tag, name)
  end

  ##
  # Add to other inline sequences.  For example, we could add WikiWords using
  # something like:
  #
  #    parser.add_special(/\b([A-Z][a-z]+[A-Z]\w+)/, :WIKIWORD)
  #
  # Each wiki word will be presented to the output formatter via the
  # accept_special method.

  def add_special(pattern, name)
    @attribute_manager.add_special(pattern, name)
  end

  ##
  # We take +text+, parse it then invoke the output +formatter+ using a
  # Visitor to render the result.

  def convert text, formatter
    document = RDoc::Markup::Parser.parse text

    document.accept formatter
  end

end

require 'rdoc/markup/parser'
require 'rdoc/markup/attribute_manager'
require 'rdoc/markup/inline'

