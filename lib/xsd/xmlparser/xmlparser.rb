=begin
XSD4R - XMLParser XML parser library.
Copyright (C) 2001, 2003  NAKAMURA, Hiroshi.

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
