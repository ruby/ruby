# WSDL4R - XMLSchema complexType definition for WSDL.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL
module XMLSchema


class Content < Info
  attr_accessor :final
  attr_accessor :mixed
  attr_accessor :type
  attr_reader :contents
  attr_reader :elements

  def initialize
    super()
    @final = nil
    @mixed = false
    @type = nil
    @contents = []
    @elements = []
  end

  def targetnamespace
    parent.targetnamespace
  end

  def <<(content)
    @contents << content
    update_elements
  end

  def each
    @contents.each do |content|
      yield content
    end
  end

  def parse_element(element)
    case element
    when AllName, SequenceName, ChoiceName
      o = Content.new
      o.type = element.name
      @contents << o
      o
    when AnyName
      o = Any.new
      @contents << o
      o
    when ElementName
      o = Element.new
      @contents << o
      o
    else
      nil
    end
  end

  def parse_attr(attr, value)
    case attr
    when FinalAttrName
      @final = value.source
    when MixedAttrName
      @mixed = (value.source == 'true')
    else
      nil
    end
  end

  def parse_epilogue
    update_elements
  end

private

  def update_elements
    @elements = []
    @contents.each do |content|
      if content.is_a?(Element)
	@elements << [content.name, content]
      end
    end
  end
end


end
end
