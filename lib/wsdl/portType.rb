=begin
WSDL4R - WSDL portType definition.
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
require 'xsd/namedelements'


module WSDL


class PortType < Info
  attr_reader :name		# required
  attr_reader :operations

  def targetnamespace
    parent.targetnamespace
  end

  def initialize
    super
    @name = nil
    @operations = XSD::NamedElements.new
  end

  def find_binding
    root.bindings.find { |item| item.type == @name }
  end

  def locations
    bind_name = find_binding.name
    result = []
    root.services.each do |service|
      service.ports.each do |port|
        if port.binding == bind_name
          result << port.soap_address.location if port.soap_address
        end
      end
    end
    result
  end

  def parse_element(element)
    case element
    when OperationName
      o = Operation.new
      @operations << o
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
