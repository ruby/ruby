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
      param_set(::SOAP::RPC::SOAPMethod::IN, rpcdefinedtype(part), part.name)
    }
    outparts = operation.outputparts
    if outparts.size > 0
      retval = outparts[0]
      collect_type(retval.type)
      result << param_set(::SOAP::RPC::SOAPMethod::RETVAL,
        rpcdefinedtype(retval), retval.name)
      cdr(outparts).each { |part|
	collect_type(part.type)
	result << param_set(::SOAP::RPC::SOAPMethod::OUT, rpcdefinedtype(part),
          part.name)
      }
    end
    result
  end

  def collect_documentparameter(operation)
    param = []
    operation.inputparts.each do |input|
      param << param_set(::SOAP::RPC::SOAPMethod::IN,
        documentdefinedtype(input), input.name)
    end
    operation.outputparts.each do |output|
      param << param_set(::SOAP::RPC::SOAPMethod::OUT,
        documentdefinedtype(output), output.name)
    end
    param
  end

private

  def dump_method(operation, binding)
    name = safemethodname(operation.name.name)
    name_as = operation.name.name
    style = binding.soapoperation_style
    namespace = binding.input.soapbody.namespace
    if style == :rpc
      paramstr = param2str(collect_rpcparameter(operation))
    else
      paramstr = param2str(collect_documentparameter(operation))
    end
    if paramstr.empty?
      paramstr = '[]'
    else
      paramstr = "[\n" << paramstr.gsub(/^/, '    ') << "\n  ]"
    end
    return <<__EOD__
[#{dq(name_as)}, #{dq(name)},
  #{paramstr},
  #{ndq(binding.soapaction)}, #{ndq(namespace)}, #{sym(style.id2name)}
]
__EOD__
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

  def param_set(io_type, type, name)
    [io_type, type, name]
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
      "[#{dq(param[0])}, #{dq(param[2])}, #{type2str(param[1])}]"
    }.join(",\n")
  end

  def type2str(type)
    if type.size == 1
      "[#{dq(type[0])}]" 
    else
      "[#{dq(type[0])}, #{ndq(type[1])}, #{dq(type[2])}]" 
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
