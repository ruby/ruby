# WSDL4R - WSDL import definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


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
      @namespace = value.source
      if @content
	@content.targetnamespace = @namespace
      end
      @namespace
    when LocationAttrName
      @location = URI.parse(value.source)
      if @location.relative? and !parent.location.nil? and
          !parent.location.relative?
        @location = parent.location + @location
      end
      if root.importedschema.key?(@location)
        @content = root.importedschema[@location]
      else
        root.importedschema[@location] = nil      # placeholder
        @content = import(@location)
        if @content.is_a?(Definitions)
          @content.root = root
          if @namespace
            @content.targetnamespace = @namespace
          end
        end
        root.importedschema[@location] = @content
      end
      @location
    else
      nil
    end
  end

private

  def import(location)
    Importer.import(location, root)
  end
end


end
