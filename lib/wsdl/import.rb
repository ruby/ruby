=begin
WSDL4R - WSDL import definition.
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
require 'wsdl/importer'


module WSDL


class Import < Info
  attr_reader :namespace
  attr_reader :location
  attr_reader :content

  def initialize
    super
    @namespace = nil
    @location = nil
    @content = nil
    @web_client = nil
  end

  def parse_element(element)
    case element
    when DocumentationName
      o = Documentation.new
      o
    else
      nil
    end
  end

  def parse_attr(attr, value)
    case attr
    when NamespaceAttrName
      @namespace = value
      if @content
	@content.targetnamespace = @namespace
      end
      @namespace
    when LocationAttrName
      @location = value
      @content = import(@location)
      if @content.is_a?(Definitions)
	@content.root = root
	if @namespace
	  @content.targetnamespace = @namespace
	end
      end
      @location
    else
      nil
    end
  end

private

  def import(location)
    Importer.import(location)
  end
end


end
