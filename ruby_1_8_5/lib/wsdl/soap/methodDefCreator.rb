# WSDL4R - Creating driver code from WSDL.
# Copyright (C) 2002, 2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/soap/classDefCreatorSupport'
require 'soap/rpc/element'


module WSDL
module SOAP


class MethodDefCreator
  include ClassDefCreatorSupport

  attr_reader :definitions

  def initialize(definitions)
    @definitions = definitions
    @simpletypes = @definitions.collect_simpletypes
    @complextypes = @definitions.collect_complextypes
    @elements = @definitions.collect_elements
    @types = []
  end

  def dump(porttype)
    @types.clear
    result = ""
    operations = @definitions.porttype(porttype).operations
    binding = @definitions.porttype_binding(porttype)
    operations.each do |operation|
      op_bind = binding.operations[operation.name]
      next unless op_bind # no binding is defined
      next unless op_bind.soapoperation # not a SOAP operation binding
      result << ",\n" unless result.empty?
      result << dump_method(operation, op_bind).chomp
    end
    return result, @types
  end

  def collect_rpcparameter(operation)
    result = operation.inputparts.collect { |part|
      collect_type(part.type)
      param_set(::SOAP::RPC::SOAPMethod::IN, part.name, rpcdefinedtype(part))
    }
    outparts = operation.outputparts
    if outparts.size > 0
      retval = outparts[0]
      collect_type(retval.type)
      result << param_set(::SOAP::RPC::SOAPMethod::RETVAL, retval.name,
        rpcdefinedtype(retval))
      cdr(outparts).each { |part|
	collect_type(part.type)
	result << param_set(::SOAP::RPC::SOAPMethod::OUT, part.name,
          rpcdefinedtype(part))
      }
    end
    result
  end

  def collect_documentparameter(operation)
    param = []
    operation.inputparts.each do |input|
      param << param_set(::SOAP::RPC::SOAPMethod::IN, input.name,
        documentdefinedtype(input), elementqualified(input))
    end
    operation.outputparts.each do |output|
      param << param_set(::SOAP::RPC::SOAPMethod::OUT, output.name,
        documentdefinedtype(output), elementqualified(output))
    end
    param
  end

private

  def dump_method(operation, binding)
    name = safemethodname(operation.name.name)
    name_as = operation.name.name
    style = binding.soapoperation_style
    inputuse = binding.input.soapbody_use
    outputuse = binding.output.soapbody_use
    namespace = binding.input.soapbody.namespace
    if style == :rpc
      qname = XSD::QName.new(namespace, name_as)
      paramstr = param2str(collect_rpcparameter(operation))
    else
      qname = nil
      paramstr = param2str(collect_documentparameter(operation))
    end
    if paramstr.empty?
      paramstr = '[]'
    else
      paramstr = "[ " << paramstr.split(/\r?\n/).join("\n    ") << " ]"
    end
    definitions = <<__EOD__
#{ndq(binding.soapaction)},
  #{dq(name)},
  #{paramstr},
  { :request_style =>  #{sym(style.id2name)}, :request_use =>  #{sym(inputuse.id2name)},
    :response_style => #{sym(style.id2name)}, :response_use => #{sym(outputuse.id2name)} }
__EOD__
    if style == :rpc
      return <<__EOD__
[ #{qname.dump},
  #{definitions}]
__EOD__
    else
      return <<__EOD__
[ #{definitions}]
__EOD__
    end
  end

  def rpcdefinedtype(part)
    if mapped = basetype_mapped_class(part.type)
      ['::' + mapped.name]
    elsif definedtype = @simpletypes[part.type]
      ['::' + basetype_mapped_class(definedtype.base).name]
    elsif definedtype = @elements[part.element]
      #['::SOAP::SOAPStruct', part.element.namespace, part.element.name]
      ['nil', part.element.namespace, part.element.name]
    elsif definedtype = @complextypes[part.type]
      case definedtype.compoundtype
      when :TYPE_STRUCT, :TYPE_EMPTY    # ToDo: empty should be treated as void.
        type = create_class_name(part.type)
	[type, part.type.namespace, part.type.name]
      when :TYPE_MAP
	[Hash.name, part.type.namespace, part.type.name]
      when :TYPE_ARRAY
	arytype = definedtype.find_arytype || XSD::AnyTypeName
	ns = arytype.namespace
	name = arytype.name.sub(/\[(?:,)*\]$/, '')
        type = create_class_name(XSD::QName.new(ns, name))
	[type + '[]', ns, name]
      else
	raise NotImplementedError.new("must not reach here")
      end
    else
      raise RuntimeError.new("part: #{part.name} cannot be resolved")
    end
  end

  def documentdefinedtype(part)
    if mapped = basetype_mapped_class(part.type)
      ['::' + mapped.name, nil, part.name]
    elsif definedtype = @simpletypes[part.type]
      ['::' + basetype_mapped_class(definedtype.base).name, nil, part.name]
    elsif definedtype = @elements[part.element]
      ['::SOAP::SOAPElement', part.element.namespace, part.element.name]
    elsif definedtype = @complextypes[part.type]
      ['::SOAP::SOAPElement', part.type.namespace, part.type.name]
    else
      raise RuntimeError.new("part: #{part.name} cannot be resolved")
    end
  end

  def elementqualified(part)
    if mapped = basetype_mapped_class(part.type)
      false
    elsif definedtype = @simpletypes[part.type]
      false
    elsif definedtype = @elements[part.element]
      definedtype.elementform == 'qualified'
    elsif definedtype = @complextypes[part.type]
      false
    else
      raise RuntimeError.new("part: #{part.name} cannot be resolved")
    end
  end

  def param_set(io_type, name, type, ele = nil)
    [io_type, name, type, ele]
  end

  def collect_type(type)
    # ignore inline type definition.
    return if type.nil?
    return if @types.include?(type)
    @types << type
    return unless @complextypes[type]
    @complextypes[type].each_element do |element|
      collect_type(element.type)
    end
  end

  def param2str(params)
    params.collect { |param|
      io, name, type, ele = param
      unless ele.nil?
        "[#{dq(io)}, #{dq(name)}, #{type2str(type)}, #{ele2str(ele)}]"
      else
        "[#{dq(io)}, #{dq(name)}, #{type2str(type)}]"
      end
    }.join(",\n")
  end

  def type2str(type)
    if type.size == 1
      "[#{dq(type[0])}]" 
    else
      "[#{dq(type[0])}, #{ndq(type[1])}, #{dq(type[2])}]" 
    end
  end

  def ele2str(ele)
    qualified = ele
    if qualified
      "true"
    else
      "false"
    end
  end

  def cdr(ary)
    result = ary.dup
    result.shift
    result
  end
end


end
end
