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


require 'xsd/xmlparser/parser'


module XSD


module XMLParser
  def create_parser(host, opt)
    XSD::XMLParser::Parser.create_parser(host, opt)
  end
  module_function :create_parser

  # $1 is necessary.
  NSParseRegexp = Regexp.new('^xmlns:?(.*)$')

  def filter_ns(ns, attrs)
    return attrs if attrs.nil? or attrs.empty?
    newattrs = {}
    attrs.each do |key, value|
      if (NSParseRegexp =~ key)
	# '' means 'default namespace'.
	tag = $1 || ''
	ns.assign(value, tag)
      else
	newattrs[key] = value
      end
    end
    newattrs
  end
  module_function :filter_ns
end


end


# Try to load XML processor.
loaded = false
[
  'xsd/xmlparser/xmlscanner',
  'xsd/xmlparser/xmlparser',
  'xsd/xmlparser/rexmlparser',
].each do |lib|
  begin
    require lib
    loaded = true
    break
  rescue LoadError
  end
end
unless loaded
  raise RuntimeError.new("XML processor module not found.")
end
