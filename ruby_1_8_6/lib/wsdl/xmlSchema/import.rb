# WSDL4R - XMLSchema import definition.
# Copyright (C) 2002, 2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/xmlSchema/importer'


module WSDL
module XMLSchema


class Import < Info
  attr_reader :namespace
  attr_reader :schemalocation
  attr_reader :content

  def initialize
    super
    @namespace = nil
    @schemalocation = nil
    @content = nil
  end

  def parse_element(element)
    nil
  end

  def parse_attr(attr, value)
    case attr
    when NamespaceAttrName
      @namespace = value.source
    when SchemaLocationAttrName
      @schemalocation = URI.parse(value.source)
      if @schemalocation.relative? and !parent.location.nil? and
          !parent.location.relative?
        @schemalocation = parent.location + @schemalocation
      end
      if root.importedschema.key?(@schemalocation)
        @content = root.importedschema[@schemalocation]
      else
        root.importedschema[@schemalocation] = nil      # placeholder
        @content = import(@schemalocation)
        root.importedschema[@schemalocation] = @content
      end
      @schemalocation
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
end
