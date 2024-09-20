# frozen_string_literal: true
##
# RDoc::RD implements the RD format from the rdtool gem.
#
# To choose RD as your only default format see
# RDoc::Options@Saved+Options for instructions on setting up a
# <code>.doc_options</code> file to store your project default.
#
# == LICENSE
#
# The grammar that produces RDoc::RD::BlockParser and RDoc::RD::InlineParser
# is included in RDoc under the Ruby License.
#
# You can find the original source for rdtool at
# https://github.com/uwabami/rdtool/
#
# You can use, re-distribute or change these files under Ruby's License or GPL.
#
# 1. You may make and give away verbatim copies of the source form of the
#    software without restriction, provided that you duplicate all of the
#    original copyright notices and associated disclaimers.
#
# 2. You may modify your copy of the software in any way, provided that
#    you do at least ONE of the following:
#
#    a. place your modifications in the Public Domain or otherwise
#       make them Freely Available, such as by posting said
#       modifications to Usenet or an equivalent medium, or by allowing
#       the author to include your modifications in the software.
#
#    b. use the modified software only within your corporation or
#       organization.
#
#    c. give non-standard binaries non-standard names, with
#       instructions on where to get the original software distribution.
#
#    d. make other distribution arrangements with the author.
#
# 3. You may distribute the software in object code or binary form,
#    provided that you do at least ONE of the following:
#
#    a. distribute the binaries and library files of the software,
#       together with instructions (in the manual page or equivalent)
#       on where to get the original distribution.
#
#    b. accompany the distribution with the machine-readable source of
#       the software.
#
#    c. give non-standard binaries non-standard names, with
#       instructions on where to get the original software distribution.
#
#    d. make other distribution arrangements with the author.
#
# 4. You may modify and include the part of the software into any other
#    software (possibly commercial).  But some files in the distribution
#    are not written by the author, so that they are not under these terms.
#
#    For the list of those files and their copying conditions, see the
#    file LEGAL.
#
# 5. The scripts and library files supplied as input to or produced as
#    output from the software do not automatically fall under the
#    copyright of the software, but belong to whomever generated them,
#    and may be sold commercially, and may be aggregated with this
#    software.
#
# 6. THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
#    IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
#    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
#    PURPOSE.

class RDoc::RD

  ##
  # Parses +rd+ source and returns an RDoc::Markup::Document.  If the
  # <tt>=begin</tt> or <tt>=end</tt> lines are missing they will be added.

  def self.parse rd
    rd = rd.lines.to_a

    if rd.find { |i| /\S/ === i } and !rd.find{|i| /^=begin\b/ === i } then
      rd.unshift("=begin\n").push("=end\n")
    end

    parser = RDoc::RD::BlockParser.new
    document = parser.parse rd

    # isn't this always true?
    document.parts.shift if RDoc::Markup::BlankLine === document.parts.first
    document.parts.pop   if RDoc::Markup::BlankLine === document.parts.last

    document
  end

  autoload :BlockParser,  "#{__dir__}/rd/block_parser"
  autoload :InlineParser, "#{__dir__}/rd/inline_parser"
  autoload :Inline,       "#{__dir__}/rd/inline"

end
