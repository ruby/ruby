# WSDL4R - XMLSchema any definition for WSDL.
# Copyright (C) 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL
module XMLSchema


class Any < Info
  attr_accessor :maxoccurs
  attr_accessor :minoccurs
  attr_accessor :namespace
  attr_accessor :process_contents

  def initialize
    super()
    @maxoccurs = '1'
    @minoccurs = '1'
    @namespace = '##any'
    @process_contents = 'strict'
  end

  def targetnamespace
    parent.targetnamespace
  end

  def parse_element(element)
    nil
  end

  def parse_attr(attr, value)
    case attr
    when MaxOccursAttrName
      @maxoccurs = value.source
    when MinOccursAttrName
      @minoccurs = value.source
    when NamespaceAttrName
      @namespace = value.source
    when ProcessContentsAttrName
      @process_contents = value.source
    else
      nil
    end
  end
end


end
end
