=begin
WSDL4R - WSDL definitions.
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


class Definitions < Info
  attr_reader :name
  attr_reader :targetnamespace
  attr_reader :imports

  # Overrides Info#root
  def root
    @root
  end

  def root=(root)
    @root = root
  end

  def initialize
    super
    @name = nil
    @targetnamespace = nil
    @types = nil
    @imports = []
    @messages = XSD::NamedElements.new
    @porttypes = XSD::NamedElements.new
    @bindings = XSD::NamedElements.new
    @services = XSD::NamedElements.new

    @anontypes = XSD::NamedElements.new
    @root = self
  end

  def targetnamespace=(targetnamespace)
    @targetnamespace = targetnamespace
    if @name
      @name = XSD::QName.new(@targetnamespace, @name.name)
    end
  end

  def collect_elements
    result = XSD::NamedElements.new
    if @types
      @types.schemas.each do |schema|
	result.concat(schema.elements)
      end
    end
    @imports.each do |import|
      result.concat(import.content.collect_elements)
    end
    result
  end

  def collect_complextypes
    result = @anontypes.dup
    if @types
      @types.schemas.each do |schema|
	result.concat(schema.complextypes)
      end
    end
    @imports.each do |import|
      result.concat(import.content.collect_complextypes)
    end
    result
  end

  def add_type(complextype)
    @anontypes << complextype
  end

  def messages
    result = @messages.dup
    @imports.each do |import|
      result.concat(import.content.messages) if self.class === import.content
    end
    result
  end

  def porttypes
    result = @porttypes.dup
    @imports.each do |import|
      result.concat(import.content.porttypes) if self.class === import.content
    end
    result
  end

  def bindings
    result = @bindings.dup
    @imports.each do |import|
      result.concat(import.content.bindings) if self.class === import.content
    end
    result
  end

  def services
    result = @services.dup
    @imports.each do |import|
      result.concat(import.content.services) if self.class === import.content
    end
    result
  end

  def message(name)
    message = @messages[name]
    return message if message
    @imports.each do |import|
      message = import.content.message(name) if self.class === import.content
      return message if message
    end
    nil
  end

  def porttype(name)
    porttype = @porttypes[name]
    return porttype if porttype
    @imports.each do |import|
      porttype = import.content.porttype(name) if self.class === import.content
      return porttype if porttype
    end
    nil
  end

  def binding(name)
    binding = @bindings[name]
    return binding if binding
    @imports.each do |import|
      binding = import.content.binding(name) if self.class === import.content
      return binding if binding
    end
    nil
  end

  def service(name)
    service = @services[name]
    return service if service
    @imports.each do |import|
      service = import.content.service(name) if self.class === import.content
      return service if service
    end
    nil
  end

  def porttype_binding(name)
    binding = @bindings.find { |item| item.type == name }
    return binding if binding
    @imports.each do |import|
      binding = import.content.porttype_binding(name) if self.class === import.content
      return binding if binding
    end
    nil
  end

  def parse_element(element)
    case element
    when ImportName
      o = Import.new
      @imports << o
      o
    when TypesName
      o = Types.new
      @types = o
      o
    when MessageName
      o = Message.new
      @messages << o
      o
    when PortTypeName
      o = PortType.new
      @porttypes << o
      o
    when BindingName
      o = Binding.new
      @bindings << o
      o
    when ServiceName
      o = Service.new
      @services << o
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
      @name = XSD::QName.new(@targetnamespace, value)
    when TargetNamespaceAttrName
      self.targetnamespace = value
    else
      nil
    end
  end

  def self.parse_element(element)
    if element == DefinitionsName
      Definitions.new
    else
      nil
    end
  end

private

end


end
