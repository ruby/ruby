# SOAP4R - SOAP RPC driver
# Copyright (C) 2000, 2001, 2003, 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/soap'
require 'soap/mapping'
require 'soap/mapping/wsdlliteralregistry'
require 'soap/rpc/rpc'
require 'soap/rpc/proxy'
require 'soap/rpc/element'
require 'soap/streamHandler'
require 'soap/property'
require 'soap/header/handlerset'


module SOAP
module RPC


class Driver
  class EmptyResponseError < Error; end

  class << self
    def __attr_proxy(symbol, assignable = false)
      name = symbol.to_s
      self.__send__(:define_method, name, proc {
        @servant.__send__(name)
      })
      if assignable
        self.__send__(:define_method, name + '=', proc { |rhs|
          @servant.__send__(name + '=', rhs)
        })
      end
    end
  end

  __attr_proxy :options
  __attr_proxy :headerhandler
  __attr_proxy :streamhandler
  __attr_proxy :test_loopback_response
  __attr_proxy :endpoint_url, true
  __attr_proxy :mapping_registry, true
  __attr_proxy :soapaction, true
  __attr_proxy :default_encodingstyle, true
  __attr_proxy :generate_explicit_type, true
  __attr_proxy :allow_unqualified_element, true

  def httpproxy
    options["protocol.http.proxy"]
  end

  def httpproxy=(httpproxy)
    options["protocol.http.proxy"] = httpproxy
  end

  def wiredump_dev
    options["protocol.http.wiredump_dev"]
  end

  def wiredump_dev=(wiredump_dev)
    options["protocol.http.wiredump_dev"] = wiredump_dev
  end

  def mandatorycharset
    options["protocol.mandatorycharset"]
  end

  def mandatorycharset=(mandatorycharset)
    options["protocol.mandatorycharset"] = mandatorycharset
  end

  def wiredump_file_base
    options["protocol.wiredump_file_base"]
  end

  def wiredump_file_base=(wiredump_file_base)
    options["protocol.wiredump_file_base"] = wiredump_file_base
  end

  def initialize(endpoint_url, namespace, soapaction = nil)
    @servant = Servant__.new(self, endpoint_url, namespace)
    @servant.soapaction = soapaction
    @proxy = @servant.proxy
  end

  def loadproperty(propertyname)
    unless options.loadproperty(propertyname)
      raise LoadError.new("No such property to load -- #{propertyname}")
    end
  end

  def inspect
    "#<#{self.class}:#{@servant.inspect}>"
  end

  def add_rpc_method(name, *params)
    param_def = create_rpc_param_def(params)
    @servant.add_rpc_method(name, @servant.soapaction, name, param_def)
  end

  def add_rpc_method_as(name, name_as, *params)
    param_def = create_rpc_param_def(params)
    @servant.add_rpc_method(name_as, @servant.soapaction, name, param_def)
  end

  def add_rpc_method_with_soapaction(name, soapaction, *params)
    param_def = create_rpc_param_def(params)
    @servant.add_rpc_method(name, soapaction, name, param_def)
  end

  def add_rpc_method_with_soapaction_as(name, name_as, soapaction, *params)
    param_def = create_rpc_param_def(params)
    @servant.add_rpc_method(name_as, soapaction, name, param_def)
  end

  # add_method is for shortcut of typical rpc/encoded method definition.
  alias add_method add_rpc_method
  alias add_method_as add_rpc_method_as
  alias add_method_with_soapaction add_rpc_method_with_soapaction
  alias add_method_with_soapaction_as add_rpc_method_with_soapaction_as

  def add_document_method(name, req_qname, res_qname)
    param_def = create_document_param_def(name, req_qname, res_qname)
    @servant.add_document_method(name, @servant.soapaction, name, param_def)
  end

  def add_document_method_as(name, name_as, req_qname, res_qname)
    param_def = create_document_param_def(name, req_qname, res_qname)
    @servant.add_document_method(name_as, @servant.soapaction, name, param_def)
  end

  def add_document_method_with_soapaction(name, soapaction, req_qname,
      res_qname)
    param_def = create_document_param_def(name, req_qname, res_qname)
    @servant.add_document_method(name, soapaction, name, param_def)
  end

  def add_document_method_with_soapaction_as(name, name_as, soapaction,
      req_qname, res_qname)
    param_def = create_document_param_def(name, req_qname, res_qname)
    @servant.add_document_method(name_as, soapaction, name, param_def)
  end

  def reset_stream
    @servant.reset_stream
  end

  def invoke(headers, body)
    @servant.invoke(headers, body)
  end

  def call(name, *params)
    @servant.call(name, *params)
  end

private

  def create_rpc_param_def(params)
    if params.size == 1 and params[0].is_a?(Array)
      params[0]
    else
      SOAPMethod.create_param_def(params)
    end
  end

  def create_document_param_def(name, req_qname, res_qname)
    [
      ['input', name, [nil, req_qname.namespace, req_qname.name]],
      ['output', name, [nil, res_qname.namespace, res_qname.name]]
    ]
  end

  def add_rpc_method_interface(name, param_def)
    @servant.add_rpc_method_interface(name, param_def)
  end

  def add_document_method_interface(name, paramname)
    @servant.add_document_method_interface(name, paramname)
  end

  class Servant__
    attr_reader :proxy
    attr_reader :options
    attr_accessor :soapaction

    def initialize(host, endpoint_url, namespace)
      @host = host
      @namespace = namespace
      @soapaction = nil
      @options = setup_options
      @wiredump_file_base = nil
      @endpoint_url = endpoint_url
      @proxy = Proxy.new(endpoint_url, @soapaction, @options)
    end

    def inspect
      "#<#{self.class}:#{@proxy.inspect}>"
    end

    def endpoint_url
      @proxy.endpoint_url
    end

    def endpoint_url=(endpoint_url)
      @proxy.endpoint_url = endpoint_url
    end

    def mapping_registry
      @proxy.mapping_registry
    end

    def mapping_registry=(mapping_registry)
      @proxy.mapping_registry = mapping_registry
    end

    def default_encodingstyle
      @proxy.default_encodingstyle
    end

    def default_encodingstyle=(encodingstyle)
      @proxy.default_encodingstyle = encodingstyle
    end

    def generate_explicit_type
      @proxy.generate_explicit_type
    end

    def generate_explicit_type=(generate_explicit_type)
      @proxy.generate_explicit_type = generate_explicit_type
    end

    def allow_unqualified_element
      @proxy.allow_unqualified_element
    end

    def allow_unqualified_element=(allow_unqualified_element)
      @proxy.allow_unqualified_element = allow_unqualified_element
    end

    def headerhandler
      @proxy.headerhandler
    end

    def streamhandler
      @proxy.streamhandler
    end

    def test_loopback_response
      @proxy.test_loopback_response
    end

    def reset_stream
      @proxy.reset_stream
    end

    def invoke(headers, body)
      if headers and !headers.is_a?(SOAPHeader)
        headers = create_header(headers)
      end
      set_wiredump_file_base(body.elename.name)
      env = @proxy.invoke(headers, body)
      if env.nil?
	return nil, nil
      else
	return env.header, env.body
      end
    end

    def call(name, *params)
      set_wiredump_file_base(name)
      @proxy.call(name, *params)
    end

    def add_rpc_method(name_as, soapaction, name, param_def)
      qname = XSD::QName.new(@namespace, name_as)
      @proxy.add_rpc_method(qname, soapaction, name, param_def)
      add_rpc_method_interface(name, param_def)
    end

    def add_document_method(name_as, soapaction, name, param_def)
      qname = XSD::QName.new(@namespace, name_as)
      @proxy.add_document_method(qname, soapaction, name, param_def)
      add_document_method_interface(name, param_def)
    end

    def add_rpc_method_interface(name, param_def)
      param_count = 0
      @proxy.operation[name].each_param_name(RPC::SOAPMethod::IN,
  	  RPC::SOAPMethod::INOUT) do |param_name|
   	param_count += 1
      end
      sclass = class << @host; self; end
      sclass.__send__(:define_method, name, proc { |*arg|
        unless arg.size == param_count
          raise ArgumentError.new(
            "wrong number of arguments (#{arg.size} for #{param_count})")
        end
        @servant.call(name, *arg)
      })
      @host.method(name)
    end

    def add_document_method_interface(name, paramname)
      sclass = class << @host; self; end
      sclass.__send__(:define_method, name, proc { |param|
        @servant.call(name, param)
      })
      @host.method(name)
    end

  private

    def set_wiredump_file_base(name)
      if @wiredump_file_base
      	@proxy.set_wiredump_file_base(@wiredump_file_base + "_#{ name }")
      end
    end

    def create_header(headers)
      header = SOAPHeader.new()
      headers.each do |content, mustunderstand, encodingstyle|
        header.add(SOAPHeaderItem.new(content, mustunderstand, encodingstyle))
      end
      header
    end

    def setup_options
      if opt = Property.loadproperty(::SOAP::PropertyName)
        opt = opt["client"]
      end
      opt ||= Property.new
      opt.add_hook("protocol.mandatorycharset") do |key, value|
        @proxy.mandatorycharset = value
      end
      opt.add_hook("protocol.wiredump_file_base") do |key, value|
        @wiredump_file_base = value
      end
      opt["protocol.http.charset"] ||= XSD::Charset.encoding_label
      opt["protocol.http.proxy"] ||= Env::HTTP_PROXY
      opt["protocol.http.no_proxy"] ||= Env::NO_PROXY
      opt
    end
  end
end


end
end
