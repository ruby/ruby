# WSDL4R - XMLSchema include definition.
# Copyright (C) 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/xmlSchema/importer'


module WSDL
module XMLSchema


class Include < Info
  attr_reader :schemalocation
  attr_reader :content

  def initialize
    super
    @schemalocation = nil
    @content = nil
  end

  def parse_element(element)
    nil
  end

  def parse_attr(attr, value)
    case attr
    when SchemaLocationAttrName
      @schemalocation = URI.parse(value.source)
      if @schemalocation.relative?
        @schemalocation = parent.location + @schemalocation
      end
      @content = import(@schemalocation)
      @schemalocation
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
end
