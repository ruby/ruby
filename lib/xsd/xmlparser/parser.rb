=begin
XSD4R - XML Instance parser library.
Copyright (C) 2002, 2003  NAKAMURA, Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end


require 'xsd/qname'
require 'xsd/ns'
require 'xsd/charset'


module XSD
module XMLParser


class Parser
  class ParseError < Error; end
  class FormatDecodeError < ParseError; end
  class UnknownElementError < FormatDecodeError; end
  class UnknownAttributeError < FormatDecodeError; end
  class UnexpectedElementError < FormatDecodeError; end
  class ElementConstraintError < FormatDecodeError; end

  @@parser_factory = nil

  def self.factory
    @@parser_factory
  end

  def self.create_parser(host, opt = {})
    @@parser_factory.new(host, opt)
  end

  def self.add_factory(factory)
    if $DEBUG
      puts "Set #{ factory } as XML processor."
    end
    @@parser_factory = factory
  end

public

  attr_accessor :charset

  def initialize(host, opt = {})
    @host = host
    @charset = opt[:charset] || 'us-ascii'
  end

  def parse(string_or_readable)
    @textbuf = ''
    prologue
    do_parse(string_or_readable)
    epilogue
  end

private

  def do_parse(string_or_readable)
    raise NotImplementError.new(
      'Method do_parse must be defined in derived class.')
  end

  def start_element(name, attrs)
    @host.start_element(name, attrs)
  end

  def characters(text)
    @host.characters(text)
  end

  def end_element(name)
    @host.end_element(name)
  end

  def prologue
  end

  def epilogue
  end

  def xmldecl_encoding=(charset)
    if @charset.nil?
      @charset = charset
    else
      # Definition in a stream (like HTTP) has a priority.
      p "encoding definition: #{ charset } is ignored." if $DEBUG
    end
  end
end


end
end
