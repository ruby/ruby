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
require 'soap/property'


module SOAP
module RPC


class Driver
  class EmptyResponseError < Error; end

  class << self
    def __attr_proxy(symbol, assignable = false)
      name = symbol.to_s
      module_eval <<-EOD
    	def #{name}
  	  @servant.#{name}
   	end
      EOD
      if assignable
	module_eval <<-EOD
  	  def #{name}=(rhs)
  	    @servant.#{name} = rhs
  	  end
	EOD
      end
    end
  end

  __attr_proxy :options
  __attr_proxy :endpoint_url, true
  __attr_proxy :mapping_registry, true
  __attr_proxy :soapaction, true
  __attr_proxy :default_encodingstyle, true

  def httpproxy
    @servant.options["protocol.http.proxy"]
  end

  def httpproxy=(httpproxy)
    @servant.options["protocol.http.proxy"] = httpproxy
  end

  def wiredump_dev
    @servant.options["protocol.http.wiredump_dev"]
  end

  def wiredump_dev=(wiredump_dev)
    @servant.options["protocol.http.wiredump_dev"] = wiredump_dev
  end

  def mandatorycharset
    @servant.options["protocol.mandatorycharset"]
  end

  def mandatorycharset=(mandatorycharset)
    @servant.options["protocol.mandatorycharset"] = mandatorycharset
  end

  def wiredump_file_base
    @servant.options["protocol.wiredump_file_base"]
  end

  def wiredump_file_base=(wiredump_file_base)
    @servant.options["protocol.wiredump_file_base"] = wiredump_file_base
  end

  def initialize(endpoint_url, namespace, soapaction = nil)
    @servant = Servant__.new(self, endpoint_url, namespace)
    @servant.soapaction = soapaction
    @proxy = @servant.proxy
    if env_httpproxy = ::SOAP::Env::HTTP_PROXY
      @servant.options["protocol.http.proxy"] = env_httpproxy
    end
    if env_no_proxy = ::SOAP::Env::NO_PROXY
      @servant.options["protocol.http.no_proxy"] = env_no_proxy
    end
  end

  def inspect
    "#<#{self.class}:#{@servant.streamhandler.inspect}>"
  end

  def add_method(name, *params)
    add_method_with_soapaction_as(name, name, @servant.soapaction, *params)
  end

  def add_method_as(name, name_as, *params)
    add_method_with_soapaction_as(name, name_as, @servant.soapaction, *params)
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
    @servant.add_method(name_as, soapaction, name, param_def)
  end

  def reset_stream
    @servant.streamhandler.reset
  end

  def invoke(headers, body)
    @servant.invoke(headers, body)
  end

  def call(name, *params)
    @servant.call(name, *params)
  end

private

  def add_rpc_method_interface(name, param_def)
    @servant.add_rpc_method_interface(name, param_def)
  end

  class Servant__
    attr_reader :options
    attr_reader :streamhandler
    attr_reader :proxy

    def initialize(host, endpoint_url, namespace)
      @host = host
      @namespace = namespace
      @mapping_registry = nil
      @soapaction = nil
      @wiredump_file_base = nil
      @options = ::SOAP::Property.new
      set_options
      @streamhandler = HTTPPostStreamHandler.new(endpoint_url,
	@options["protocol.http"] ||= ::SOAP::Property.new)
      @proxy = Proxy.new(@streamhandler, @soapaction)
      @proxy.allow_unqualified_element = true
    end

    def endpoint_url
      @streamhandler.endpoint_url
    end

    def endpoint_url=(endpoint_url)
      @streamhandler.endpoint_url = endpoint_url
      @streamhandler.reset
    end

    def mapping_registry
      @mapping_registry
    end

    def mapping_registry=(mapping_registry)
      @mapping_registry = mapping_registry
    end

    def soapaction
      @soapaction
    end

    def soapaction=(soapaction)
      @soapaction = soapaction
    end

    def default_encodingstyle
      @proxy.default_encodingstyle
    end

    def default_encodingstyle=(encodingstyle)
      @proxy.default_encodingstyle = encodingstyle
    end

    def invoke(headers, body)
      set_wiredump_file_base(body.elename.name)
      @proxy.invoke(headers, body)
    end

    def call(name, *params)
      set_wiredump_file_base(name)
      # Convert parameters: params array => SOAPArray => members array
      params = Mapping.obj2soap(params, @mapping_registry).to_a
      header, body = @proxy.call(nil, name, *params)
      raise EmptyResponseError.new("Empty response.") unless body
      begin
	@proxy.check_fault(body)
      rescue SOAP::FaultError => e
	Mapping.fault2exception(e)
      end

      ret = body.response ?
	Mapping.soap2obj(body.response, @mapping_registry) : nil
      if body.outparams
	outparams = body.outparams.collect { |outparam|
	  Mapping.soap2obj(outparam)
	}
	return [ret].concat(outparams)
      else
	return ret
      end
    end

    def add_method(name_as, soapaction, name, param_def)
      qname = XSD::QName.new(@namespace, name_as)
      @proxy.add_method(qname, soapaction, name, param_def)
      add_rpc_method_interface(name, param_def)
    end

    def add_rpc_method_interface(name, param_def)
      param_names = []
      i = 0
      @proxy.method[name].each_param_name(RPC::SOAPMethod::IN,
  	  RPC::SOAPMethod::INOUT) do |param_name|
   	i += 1
    	param_names << "arg#{ i }"
      end
      callparam = (param_names.collect { |pname| ", " + pname }).join
      @host.instance_eval <<-EOS
     	def #{ name }(#{ param_names.join(", ") })
      	  @servant.call(#{ name.dump }#{ callparam })
       	end
      EOS
    end

  private

    def set_wiredump_file_base(name)
      if @wiredump_file_base
      	@streamhandler.wiredump_file_base = @wiredump_file_base + "_#{ name }"
      end
    end

    def set_options
      @options.add_hook("protocol.mandatorycharset") do |key, value|
	@proxy.mandatorycharset = value
      end
      @options.add_hook("protocol.wiredump_file_base") do |key, value|
	@wiredump_file_base = value
      end
      @options["protocol.http.charset"] = XSD::Charset.encoding_label
    end
  end
end


end
end
