# WSDL4R - XMLSchema complexType definition for WSDL.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/xmlSchema/content'
require 'xsd/namedelements'


module WSDL
module XMLSchema


class ComplexType < Info
  attr_accessor :name
  attr_accessor :complexcontent
  attr_accessor :content
  attr_accessor :final
  attr_accessor :mixed
  attr_reader :attributes

  def initialize(name = nil)
    super()
    @name = name
    @complexcontent = nil
    @content = nil
    @final = nil
    @mixed = false
    @attributes = XSD::NamedElements.new
  end

  def targetnamespace
    parent.targetnamespace
  end

  def each_element
    if @content
      @content.elements.each do |element|
	yield(element.name, element)
      end
    end
  end

  def find_element(name)
    if @content
      @content.elements.each do |element|
	return element if name == element.name
      end
    end
    nil
  end

  def find_element_by_name(name)
    if @content
      @content.elements.each do |element|
	return element if name == element.name.name
      end
    end
    nil
  end

  def sequence_elements=(elements)
    @content = Sequence.new
    elements.each do |element|
      @content << element
    end
  end

  def all_elements=(elements)
    @content = All.new
    elements.each do |element|
      @content << element
    end
  end

  def parse_element(element)
    case element
    when AllName
      @content = All.new
      @content
    when SequenceName
      @content = Sequence.new
      @content
    when ChoiceName
      @content = Choice.new
      @content
    when ComplexContentName
      @complexcontent = ComplexContent.new
      @complexcontent
    when AttributeName
      o = Attribute.new
      @attributes << o
      o
    else
      nil
    end
  end

  def parse_attr(attr, value)
    case attr
    when FinalAttrName
      @final = value
    when MixedAttrName
      @mixed = (value == 'true')
    when NameAttrName
      @name = XSD::QName.new(targetnamespace, value)
    else
      nil
    end
  end
end


end
end
