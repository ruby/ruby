# SOAP4R - SOAP RPC driver
# Copyright (C) 2000, 2001, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/soap'
require 'soap/mapping'
require 'soap/rpc/rpc'
require 'soap/rpc/proxy'
require 'soap/rpc/element'
require 'soap/streamHandler'


module SOAP
module RPC


class Driver
public
  class EmptyResponseError < Error; end

  attr_accessor :mapping_registry
  attr_accessor :soapaction
  attr_reader :wiredump_dev
  attr_reader :wiredump_file_base
  attr_reader :streamhandler

  def initialize(endpoint_url, namespace, soapaction = nil)
    @namespace = namespace
    @mapping_registry = nil      # for unmarshal
    @soapaction = soapaction
    @wiredump_dev = nil
    @wiredump_file_base = nil
    name = 'http_proxy'
    @httpproxy = ENV[name] || ENV[name.upcase]
    @streamhandler = HTTPPostStreamHandler.new(endpoint_url, @httpproxy,
      XSD::Charset.encoding_label)
    @proxy = Proxy.new(@streamhandler, @soapaction)
    @proxy.allow_unqualified_element = true
  end

  def inspect
    "#<#{self.class}:#{@streamhandler.inspect}>"
  end

  def endpoint_url
    @streamhandler.endpoint_url
  end

  def endpoint_url=(endpoint_url)
    @streamhandler.endpoint_url = endpoint_url
    @streamhandler.reset
  end

  def wiredump_dev=(dev)
    @wiredump_dev = dev
    @streamhandler.wiredump_dev = @wiredump_dev
    @streamhandler.reset
  end

  def wiredump_file_base=(base)
    @wiredump_file_base = base
  end

  def httpproxy
    @httpproxy
  end

  def httpproxy=(httpproxy)
    @httpproxy = httpproxy
    @streamhandler.proxy = @httpproxy
    @streamhandler.reset
  end

  def mandatorycharset
    @proxy.mandatorycharset
  end

  def mandatorycharset=(mandatorycharset)
    @proxy.mandatorycharset = mandatorycharset
  end

  def default_encodingstyle
    @proxy.default_encodingstyle
  end

  def default_encodingstyle=(encodingstyle)
    @proxy.default_encodingstyle = encodingstyle
  end


  ###
  ## Method definition interfaces.
  #
  # params: [[param_def...]] or [paramname, paramname, ...]
  # param_def: See proxy.rb.  Sorry.

  def add_method(name, *params)
    add_method_with_soapaction_as(name, name, @soapaction, *params)
  end

  def add_method_as(name, name_as, *params)
    add_method_with_soapaction_as(name, name_as, @soapaction, *params)
  end

  def add_method_with_soapaction(name, soapaction, *params)
    add_method_with_soapaction_as(name, name, soapaction, *params)
  end

  def add_method_with_soapaction_as(name, name_as, soapaction, *params)
    param_def = if params.size == 1 and params[0].is_a?(Array)
        params[0]
      else
        SOAPMethod.create_param_def(params)
      end
    qname = XSD::QName.new(@namespace, name_as)
    @proxy.add_method(qname, soapaction, name, param_def)
    add_rpc_method_interface(name, param_def)
  end


  ###
  ## Driving interface.
  #
  def invoke(headers, body)
    if @wiredump_file_base
      @streamhandler.wiredump_file_base =
	@wiredump_file_base + '_' << body.elename.name
    end
    @proxy.invoke(headers, body)
  end

  def call(name, *params)
    # Convert parameters: params array => SOAPArray => members array
    params = Mapping.obj2soap(params, @mapping_registry).to_a
    if @wiredump_file_base
      @streamhandler.wiredump_file_base = @wiredump_file_base + '_' << name
    end

    # Then, call @proxy.call like the following.
    header, body = @proxy.call(nil, name, *params)
    unless body
      raise EmptyResponseError.new("Empty response.")
    end

    begin
      @proxy.check_fault(body)
    rescue SOAP::FaultError => e
      Mapping.fault2exception(e)
    end

    ret = body.response ? Mapping.soap2obj(body.response, @mapping_registry) : nil
    if body.outparams
      outparams = body.outparams.collect { |outparam| Mapping.soap2obj(outparam) }
      return [ret].concat(outparams)
    else
      return ret
    end
  end

  def reset_stream
    @streamhandler.reset
  end

private

  def add_rpc_method_interface(name, param_def)
    param_names = []
    i = 0
    @proxy.method[name].each_param_name(RPC::SOAPMethod::IN,
	RPC::SOAPMethod::INOUT) do |param_name|
      i += 1
      param_names << "arg#{ i }"
    end

    callparam = (param_names.collect { |pname| ", " + pname }).join
    self.instance_eval <<-EOS
      def #{ name }(#{ param_names.join(", ") })
        call("#{ name }"#{ callparam })
      end
    EOS
  end
end


end
end
