=begin
WSDL4R - WSDL SOAP body definition.
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

  def find_message
    root.message(@message)
  end

  def find_part
    find_message.parts.each do |part|
      if part.name == @part
	return part
      end
    end
    nil
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
      @message = value
    when PartAttrName
      @part = value
    when UseAttrName
      @use = value
    when EncodingStyleAttrName
      @encodingstyle = value
    when NamespaceAttrName
      @namespace = value
    else
      nil
    end
  end
end


end
end
