=begin
WSDL4R - WSDL bound operation definition.
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


class OperationBinding < Info
  attr_reader :name		# required
  attr_reader :input
  attr_reader :output
  attr_reader :fault
  attr_reader :soapoperation

  def initialize
    super
    @name = nil
    @input = nil
    @output = nil
    @fault = nil
    @soapoperation = nil
  end

  def targetnamespace
    parent.targetnamespace
  end

  def porttype
    root.porttype(parent.type)
  end

  def find_operation
    porttype.operations[@name]
  end

  def parse_element(element)
    case element
    when InputName
      o = Param.new
      @input = o
      o
    when OutputName
      o = Param.new
      @output = o
      o
    when FaultName
      o = Param.new
      @fault = o
      o
    when SOAPOperationName
      o = WSDL::SOAP::Operation.new
      @soapoperation = o
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
    when NameAttrName
      @name = XSD::QName.new(targetnamespace, value)
    else
      nil
    end
  end
end


end
