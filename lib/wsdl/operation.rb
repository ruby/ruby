# WSDL4R - WSDL operation definition.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'


module WSDL


class Operation < Info
  class NameInfo
    attr_reader :op_name
    attr_reader :optype_name
    attr_reader :parts
    def initialize(op_name, optype_name, parts)
      @op_name = op_name
      @optype_name = optype_name
      @parts = parts
    end
  end

  attr_reader :name		# required
  attr_reader :parameter_order	# optional
  attr_reader :input
  attr_reader :output
  attr_reader :fault
  attr_reader :type		# required

  def initialize
    super
    @name = nil
    @type = nil
    @parameter_order = nil
    @input = nil
    @output = nil
    @fault = []
  end

  def targetnamespace
    parent.targetnamespace
  end

  def input_info
    typename = input.find_message.name
    NameInfo.new(@name, typename, inputparts)
  end

  def output_info
    typename = output.find_message.name
    NameInfo.new(@name, typename, outputparts)
  end

  def inputparts
    sort_parts(input.find_message.parts)
  end

  def inputname
    XSD::QName.new(targetnamespace, input.name ? input.name.name : @name.name)
  end

  def outputparts
    sort_parts(output.find_message.parts)
  end

  def outputname
    XSD::QName.new(targetnamespace,
      output.name ? output.name.name : @name.name + 'Response')
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
      @fault << o
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
      @name = XSD::QName.new(targetnamespace, value.source)
    when TypeAttrName
      @type = value
    when ParameterOrderAttrName
      @parameter_order = value.source.split(/\s+/)
    else
      nil
    end
  end

private

  def sort_parts(parts)
    return parts.dup unless parameter_order
    result = []
    parameter_order.each do |orderitem|
      if (ele = parts.find { |part| part.name == orderitem })
	result << ele
      end
    end
    if result.length == 0
      return parts.dup
    end
    # result length can be shorter than parts's.
    # return part must not be a part of the parameterOrder.
    result
  end
end


end
