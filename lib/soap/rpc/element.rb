# SOAP4R - RPC element definition.
# Copyright (C) 2000, 2001, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/baseData'


module SOAP

# Add method definitions for RPC to common definition in element.rb
class SOAPBody < SOAPStruct
  public

  def request
    root_node
  end

  def response
    if !@is_fault
      if void?
        nil
      else
        # Initial element is [retval].
        root_node[0]
      end
    else
      root_node
    end
  end

  def outparams
    if !@is_fault and !void?
      op = root_node[1..-1]
      op = nil if op && op.empty?
      op
    else
      nil
    end
  end

  def void?
    root_node.nil?
  end

  def fault
    if @is_fault
      self['fault']
    else
      nil
    end
  end

  def fault=(fault)
    @is_fault = true
    add_member('fault', fault)
  end
end


module RPC


class RPCError < Error; end
class MethodDefinitionError < RPCError; end
class ParameterError < RPCError; end

class SOAPMethod < SOAPStruct
  RETVAL = 'retval'
  IN = 'in'
  OUT = 'out'
  INOUT = 'inout'

  attr_reader :param_def
  attr_reader :inparam
  attr_reader :outparam

  def initialize(qname, param_def = nil)
    super(nil)
    @elename = qname
    @encodingstyle = nil

    @param_def = param_def

    @signature = []
    @inparam_names = []
    @inoutparam_names = []
    @outparam_names = []

    @inparam = {}
    @outparam = {}
    @retval_name = nil

    init_param(@param_def) if @param_def
  end

  def have_outparam?
    @outparam_names.size > 0
  end

  def each_param_name(*type)
    @signature.each do |io_type, name, param_type|
      if type.include?(io_type)
        yield(name)
      end
    end
  end

  def set_param(params)
    params.each do |param, data|
      @inparam[param] = data
      data.elename.name = param
      data.parent = self
    end
  end

  def set_outparam(params)
    params.each do |param, data|
      @outparam[param] = data
      data.elename.name = param
    end
  end

  def SOAPMethod.create_param_def(param_names)
    param_def = []
    param_names.each do |param_name|
      param_def.push([IN, param_name, nil])
    end
    param_def.push([RETVAL, 'return', nil])
    param_def
  end

private

  def init_param(param_def)
    param_def.each do |io_type, name, param_type|
      case io_type
      when IN
        @signature.push([IN, name, param_type])
        @inparam_names.push(name)
      when OUT
        @signature.push([OUT, name, param_type])
        @outparam_names.push(name)
      when INOUT
        @signature.push([INOUT, name, param_type])
        @inoutparam_names.push(name)
      when RETVAL
        if (@retval_name)
          raise MethodDefinitionError.new('Duplicated retval')
        end
        @retval_name = name
      else
        raise MethodDefinitionError.new("Unknown type: #{ io_type }")
      end
    end
  end
end


class SOAPMethodRequest < SOAPMethod
  attr_accessor :soapaction

  def SOAPMethodRequest.create_request(qname, *params)
    param_def = []
    param_value = []
    i = 0
    params.each do |param|
      param_name = "p#{ i }"
      i += 1
      param_def << [IN, param_name, nil]
      param_value << [param_name, param]
    end
    param_def << [RETVAL, 'return', nil]
    o = new(qname, param_def)
    o.set_param(param_value)
    o
  end

  def initialize(qname, param_def = nil, soapaction = nil)
    check_elename(qname)
    super(qname, param_def)
    @soapaction = soapaction
  end

  def each
    each_param_name(IN, INOUT) do |name|
      unless @inparam[name]
        raise ParameterError.new("Parameter: #{ name } was not given.")
      end
      yield(name, @inparam[name])
    end
  end

  def dup
    req = self.class.new(@elename.dup, @param_def, @soapaction)
    req.encodingstyle = @encodingstyle
    req
  end

  def create_method_response
    SOAPMethodResponse.new(
      XSD::QName.new(@elename.namespace, @elename.name + 'Response'),
      @param_def)
  end

private

  def check_elename(qname)
    # NCName & ruby's method name
    unless /\A[\w_][\w\d_\-]*\z/ =~ qname.name
      raise MethodDefinitionError.new("Element name '#{qname.name}' not allowed")
    end
  end
end


class SOAPMethodResponse < SOAPMethod

  def initialize(qname, param_def = nil)
    super(qname, param_def)
    @retval = nil
  end

  def retval=(retval)
    @retval = retval
    @retval.elename = @retval.elename.dup_name(@retval_name || 'return')
    retval.parent = self
    retval
  end

  def each
    if @retval_name and !@retval.is_a?(SOAPVoid)
      yield(@retval_name, @retval)
    end

    each_param_name(OUT, INOUT) do |param_name|
      unless @outparam[param_name]
        raise ParameterError.new("Parameter: #{ param_name } was not given.")
      end
      yield(param_name, @outparam[param_name])
    end
  end
end


# To return(?) void explicitly.
#  def foo(input_var)
#    ...
#    return SOAP::RPC::SOAPVoid.new
#  end
class SOAPVoid < XSD::XSDAnySimpleType
  include SOAPBasetype
  extend SOAPModuleUtils
  Name = XSD::QName.new(Mapping::RubyCustomTypeNamespace, nil)

public
  def initialize()
    @elename = Name
    @id = nil
    @precedents = []
    @parent = nil
  end
end


end
end
