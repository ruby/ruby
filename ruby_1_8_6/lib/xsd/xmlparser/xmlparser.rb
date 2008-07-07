# XSD4R - XMLParser XML parser library.
# Copyright (C) 2001, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/xmlparser'
require 'xml/parser'


module XSD
module XMLParser


class XMLParser < XSD::XMLParser::Parser
  class Listener < XML::Parser
    begin
      require 'xml/encoding-ja'
      include XML::Encoding_ja
    rescue LoadError
      # uconv may not be installed.
    end
  end

  def do_parse(string_or_readable)
    # XMLParser passes a String in utf-8.
    @charset = 'utf-8'
    @parser = Listener.new
    @parser.parse(string_or_readable) do |type, name, data|
      case type
      when XML::Parser::START_ELEM
	start_element(name, data)
      when XML::Parser::END_ELEM
	end_element(name)
      when XML::Parser::CDATA
	characters(data)
      else
	raise FormatDecodeError.new("Unexpected XML: #{ type }/#{ name }/#{ data }.")
      end
    end
  end

  add_factory(self)
end


end
end
