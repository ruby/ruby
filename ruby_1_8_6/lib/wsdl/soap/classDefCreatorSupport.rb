# WSDL4R - Creating class code support from WSDL.
# Copyright (C) 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'soap/mapping'
require 'soap/mapping/typeMap'
require 'xsd/codegen/gensupport'


module WSDL
module SOAP


module ClassDefCreatorSupport
  include XSD::CodeGen::GenSupport

  def create_class_name(qname)
    if klass = basetype_mapped_class(qname)
      ::SOAP::Mapping::DefaultRegistry.find_mapped_obj_class(klass).name
    else
      safeconstname(qname.name)
    end
  end

  def basetype_mapped_class(name)
    ::SOAP::TypeMap[name]
  end

  def dump_method_signature(operation)
    name = operation.name.name
    input = operation.input
    output = operation.output
    fault = operation.fault
    signature = "#{ name }#{ dump_inputparam(input) }"
    str = <<__EOD__
# SYNOPSIS
#   #{name}#{dump_inputparam(input)}
#
# ARGS
#{dump_inout_type(input).chomp}
#
# RETURNS
#{dump_inout_type(output).chomp}
#
__EOD__
    unless fault.empty?
      faultstr = (fault.collect { |f| dump_inout_type(f).chomp }).join(', ')
      str <<<<__EOD__
# RAISES
#   #{faultstr}
#
__EOD__
    end
    str
  end

  def dq(ele)
    ele.dump
  end

  def ndq(ele)
    ele.nil? ? 'nil' : dq(ele)
  end

  def sym(ele)
    ':' + ele
  end

  def dqname(qname)
    qname.dump
  end

private

  def dump_inout_type(param)
    if param
      message = param.find_message
      params = ""
      message.parts.each do |part|
        name = safevarname(part.name)
        if part.type
          typename = safeconstname(part.type.name)
          params << add_at("#   #{name}", "#{typename} - #{part.type}\n", 20)
        elsif part.element
          typename = safeconstname(part.element.name)
          params << add_at("#   #{name}", "#{typename} - #{part.element}\n", 20)
        end
      end
      unless params.empty?
        return params
      end
    end
    "#   N/A\n"
  end

  def dump_inputparam(input)
    message = input.find_message
    params = ""
    message.parts.each do |part|
      params << ", " unless params.empty?
      params << safevarname(part.name)
    end
    if params.empty?
      ""
    else
      "(#{ params })"
    end
  end

  def add_at(base, str, pos)
    if base.size >= pos
      base + ' ' + str
    else
      base + ' ' * (pos - base.size) + str
    end
  end
end


end
end
