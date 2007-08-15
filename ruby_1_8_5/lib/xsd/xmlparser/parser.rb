# XSD4R - XML Instance parser library.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


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
    @charset = opt[:charset] || nil
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
