# XSD4R - XMLScan XML parser library.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/xmlparser'
require 'xmlscan/scanner'


module XSD
module XMLParser


class XMLScanner < XSD::XMLParser::Parser
  include XMLScan::Visitor

  def do_parse(string_or_readable)
    @attrs = {}
    @curattr = nil
    @scanner = XMLScan::XMLScanner.new(self)
    @scanner.kcode = ::XSD::Charset.charset_str(charset) if charset
    @scanner.parse(string_or_readable)
  end

  def scanner_kcode=(charset)
    @scanner.kcode = ::XSD::Charset.charset_str(charset) if charset
    self.xmldecl_encoding = charset
  end

  ENTITY_REF_MAP = {
    'lt' => '<',
    'gt' => '>',
    'amp' => '&',
    'quot' => '"',
    'apos' => '\''
  }

  def parse_error(msg)
    raise ParseError.new(msg)
  end

  def wellformed_error(msg)
    raise NotWellFormedError.new(msg)
  end

  def valid_error(msg)
    raise NotValidError.new(msg)
  end

  def warning(msg)
    p msg if $DEBUG
  end

  # def on_xmldecl; end

  def on_xmldecl_version(str)
    # 1.0 expected.
  end

  def on_xmldecl_encoding(str)
    self.scanner_kcode = str
  end

  # def on_xmldecl_standalone(str); end

  # def on_xmldecl_other(name, value); end

  # def on_xmldecl_end; end

  # def on_doctype(root, pubid, sysid); end

  # def on_prolog_space(str); end

  # def on_comment(str); end

  # def on_pi(target, pi); end

  def on_chardata(str)
    characters(str)
  end

  # def on_cdata(str); end

  def on_etag(name)
    end_element(name)
  end

  def on_entityref(ref)
    characters(ENTITY_REF_MAP[ref])
  end

  def on_charref(code)
    characters([code].pack('U'))
  end

  def on_charref_hex(code)
    on_charref(code)
  end

  # def on_start_document; end

  # def on_end_document; end

  def on_stag(name)
    @attrs = {}
  end

  def on_attribute(name)
    @attrs[name] = @curattr = ''
  end

  def on_attr_value(str)
    @curattr << str
  end

  def on_attr_entityref(ref)
    @curattr << ENTITY_REF_MAP[ref]
  end

  def on_attr_charref(code)
    @curattr << [code].pack('U')
  end

  def on_attr_charref_hex(code)
    on_attr_charref(code)
  end

  # def on_attribute_end(name); end

  def on_stag_end_empty(name)
    on_stag_end(name)
    on_etag(name)
  end

  def on_stag_end(name)
    start_element(name, @attrs)
  end

  add_factory(self)
end


end
end
