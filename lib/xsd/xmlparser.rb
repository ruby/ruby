# XSD4R - XML Instance parser library.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


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
