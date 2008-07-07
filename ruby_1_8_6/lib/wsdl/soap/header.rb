# WSDL4R - WSDL SOAP body definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL
module SOAP


class Header < Info
  attr_reader :headerfault

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
    @headerfault = nil
  end

  def targetnamespace
    parent.targetnamespace
  end

  def find_message
    root.message(@message) or raise RuntimeError.new("#{@message} not found")
  end

  def find_part
    find_message.parts.each do |part|
      if part.name == @part
	return part
      end
    end
    raise RuntimeError.new("#{@part} not found")
  end

  def parse_element(element)
    case element
    when HeaderFaultName
      o = WSDL::SOAP::HeaderFault.new
      @headerfault = o
      o
    else
      nil
    end
  end

  def parse_attr(attr, value)
    case attr
    when MessageAttrName
      if value.namespace.nil?
        value = XSD::QName.new(targetnamespace, value.source)
      end
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
