# WSDL4R - WSDL SOAP body definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL
module SOAP


class HeaderFault < Info
  attr_reader :message	# required
  attr_reader :part	# required
  attr_reader :use	# required
  attr_reader :encodingstyle
  attr_reader :namespace

  def initialize
    super
    @message = nil
    @part = nil
    @use = nil
    @encodingstyle = nil
    @namespace = nil
  end

  def parse_element(element)
    nil
  end

  def parse_attr(attr, value)
    case attr
    when MessageAttrName
      @message = value
    when PartAttrName
      @part = value.source
    when UseAttrName
      @use = value.source
    when EncodingStyleAttrName
      @encodingstyle = value.source
    when NamespaceAttrName
      @namespace = value.source
    else
      nil
    end
  end
end


end
end
