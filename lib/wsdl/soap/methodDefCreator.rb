# WSDL4R - Creating driver code from WSDL.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/soap/classDefCreatorSupport'


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
    @types = nil
  end

  def dump(porttype)
    @types = []
    result = ""
    operations = @definitions.porttype(porttype).operations
    binding = @definitions.porttype_binding(porttype)
    operations.each do |operation|
      op_bind = binding.operations[operation.name]
      result << ",\n" unless result.empty?
      result << dump_method(operation, op_bind).chomp
    end
    return result, @types
  end

private

  def dump_method(operation, binding)
    name = safemethodname(operation.name.name)
    name_as = operation.name.name
    stylestr = binding.soapoperation.operation_style.id2name
    if binding.soapoperation.operation_style == :rpc
      soapaction = binding.soapoperation.soapaction
      namespace = binding.input.soapbody.namespace
      params = collect_rpcparameter(operation)
    else
      soapaction = namespace = nil
      params = collect_documentparameter(operation)
    end
    paramstr = param2str(params)
    if paramstr.empty?
      paramstr = '[]'
    else
      paramstr = "[\n" << paramstr.gsub(/^/, '    ') << "\n  ]"
    end
    return <<__EOD__
[#{ dq(name_as) }, #{ dq(name) },
  #{ paramstr },
  #{ ndq(soapaction) }, #{ ndq(namespace) }, #{ sym(stylestr) }
]
__EOD__
  end

  def collect_rpcparameter(operation)
    result = operation.inputparts.collect { |part|
      collect_type(part.type)
      param_set('in', rpcdefinedtype(part), part.name)
    }
    outparts = operation.outputparts
    if outparts.size > 0
      retval = outparts[0]
      collect_type(retval.type)
      result << param_set('retval', rpcdefinedtype(retval), retval.name)
      cdr(outparts).each { |part|
	collect_type(part.type)
	result << param_set('out', rpcdefinedtype(part), part.name)
      }
    end
    result
  end

  def collect_documentparameter(operation)
    input = operation.inputparts[0]
    output = operation.outputparts[0]
    [
      param_set('input', documentdefinedtype(input), input.name),
      param_set('output', documentdefinedtype(output), output.name)
    ]
  end

  def rpcdefinedtype(part)
    if mapped = basetype_mapped_class(part.type)
      ['::' + mapped.name]
    elsif definedtype = @simpletypes[part.type]
      ['::' + basetype_mapped_class(definedtype.base).name]
    elsif definedtype = @elements[part.element]
      ['::SOAP::SOAPStruct', part.element.namespace, part.element.name]
    elsif definedtype = @complextypes[part.type]
      case definedtype.compoundtype
      when :TYPE_STRUCT
	['::SOAP::SOAPStruct', part.type.namespace, part.type.name]
      when :TYPE_ARRAY
	arytype = definedtype.find_arytype || XSD::AnyTypeName
	ns = arytype.namespace
	name = arytype.name.sub(/\[(?:,)*\]$/, '')
	['::SOAP::SOAPArray', ns, name]
      else
	raise NotImplementedError.new("Must not reach here.")
      end
    else
      raise RuntimeError.new("Part: #{part.name} cannot be resolved.")
    end
  end

  def documentdefinedtype(part)
    if definedtype = @simpletypes[part.type]
      ['::' + basetype_mapped_class(definedtype.base).name, nil, part.name]
    elsif definedtype = @elements[part.element]
      ['::SOAP::SOAPElement', part.element.namespace, part.element.name]
    elsif definedtype = @complextypes[part.type]
      ['::SOAP::SOAPElement', part.type.namespace, part.type.name]
    else
      raise RuntimeError.new("Part: #{part.name} cannot be resolved.")
    end
  end

  def param_set(io_type, type, name)
    [io_type, type, name]
  end

  def collect_type(type)
    # ignore inline type definition.
    return if type.nil?
    @types << type
    return unless @complextypes[type]
    @complextypes[type].each_element do |element|
      collect_type(element.type)
    end
  end

  def param2str(params)
    params.collect { |param|
      "[#{ dq(param[0]) }, #{ dq(param[2]) }, #{ type2str(param[1]) }]"
    }.join(",\n")
  end

  def type2str(type)
    if type.size == 1
      "[#{ type[0] }]" 
    else
      "[#{ type[0] }, #{ ndq(type[1]) }, #{ dq(type[2]) }]" 
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
