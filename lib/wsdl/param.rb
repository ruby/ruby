=begin
WSDL4R - WSDL param definition.
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


class Param < Info
  attr_reader :message	# required
  attr_reader :name	# optional but required for fault.
  attr_reader :soapbody
  attr_reader :soapheader
  attr_reader :soapfault

  def initialize
    super
    @message = nil
    @name = nil
    @soapbody = nil
    @soapheader = []
    @soapfault = nil
  end

  def targetnamespace
    parent.targetnamespace
  end

  def find_message
    root.message(@message)
  end

  def parse_element(element)
    case element
    when SOAPBodyName
      o = WSDL::SOAP::Body.new
      @soapbody = o
      o
    when SOAPHeaderName
      o = WSDL::SOAP::Header.new
      @soapheader << o
      o
    when SOAPFaultName
      o = WSDL::SOAP::Fault.new
      @soap_fault = o
      o
    when DocumentationName
      o = Documentation.new
      o
    else
      nil
    end
  end

  def parse_attr(attr, value)
    case attr
    when MessageAttrName
      @message = value
    when NameAttrName
      @name = XSD::QName.new(targetnamespace, value)
    else
      nil
    end
  end
end


end
