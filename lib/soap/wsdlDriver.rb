# SOAP4R - SOAP WSDL driver
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/parser'
require 'wsdl/importer'
require 'xsd/qname'
require 'soap/element'
require 'soap/baseData'
require 'soap/streamHandler'
require 'soap/mimemessage'
require 'soap/mapping'
require 'soap/mapping/wsdlencodedregistry'
require 'soap/mapping/wsdlliteralregistry'
require 'soap/rpc/rpc'
require 'soap/rpc/element'
require 'soap/rpc/proxy'
require 'soap/processor'
require 'soap/header/handlerset'
require 'xsd/codegen/gensupport'


module SOAP


class WSDLDriverFactory
  class FactoryError < StandardError; end

  attr_reader :wsdl

  def initialize(wsdl, logdev = nil)
    @logdev = logdev
    @wsdl = import(wsdl)
  end
  
  def inspect
    "#<#{self.class}:#{@wsdl.name}>"
  end

  def create_driver(servicename = nil, portname = nil)
    service = if servicename
	@wsdl.service(XSD::QName.new(@wsdl.targetnamespace, servicename))
      else
	@wsdl.services[0]
      end
    if service.nil?
      raise FactoryError.new("Service #{ servicename } not found in WSDL.")
    end
    port = if portname
	service.ports[XSD::QName.new(@wsdl.targetnamespace, portname)]
      else
	service.ports[0]
      end
    if port.nil?
      raise FactoryError.new("Port #{ portname } not found in WSDL.")
    end
    if port.soap_address.nil?
      raise FactoryError.new("soap:address element not found in WSDL.")
    end
    WSDLDriver.new(@wsdl, port, @logdev)
  end

  # Backward compatibility.
  alias createDriver create_driver

private
  
  def import(location)
    WSDL::Importer.import(location)
  end
end


class WSDLDriver
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
  __attr_proxy :mapping_registry, true		# for RPC unmarshal
  __attr_proxy :wsdl_mapping_registry, true	# for RPC marshal
  __attr_proxy :default_encodingstyle, true
  __attr_proxy :generate_explicit_type, true
  __attr_proxy :allow_unqualified_element, true

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

  def initialize(wsdl, port, logdev)
    @servant = Servant__.new(self, wsdl, port, logdev)
  end

  def inspect
    "#<#{self.class}:#{@servant.port.name}>"
  end

  def reset_stream
    @servant.reset_stream
  end

  # Backward compatibility.
  alias generateEncodeType= generate_explicit_type=

  class Servant__
    include SOAP

    attr_reader :options
    attr_reader :port

    attr_accessor :soapaction
    attr_accessor :default_encodingstyle
    attr_accessor :allow_unqualified_element
    attr_accessor :generate_explicit_type
    attr_accessor :mapping_registry
    attr_accessor :wsdl_mapping_registry

    def initialize(host, wsdl, port, logdev)
      @host = host
      @wsdl = wsdl
      @port = port
      @logdev = logdev
      @soapaction = nil
      @options = setup_options
      @default_encodingstyle = nil
      @allow_unqualified_element = nil
      @generate_explicit_type = false
      @mapping_registry = nil		# for rpc unmarshal
      @wsdl_mapping_registry = nil	# for rpc marshal
      @wiredump_file_base = nil
      @mandatorycharset = nil
      @wsdl_elements = @wsdl.collect_elements
      @wsdl_types = @wsdl.collect_complextypes + @wsdl.collect_simpletypes
      @rpc_decode_typemap = @wsdl_types +
	@wsdl.soap_rpc_complextypes(port.find_binding)
      @wsdl_mapping_registry = Mapping::WSDLEncodedRegistry.new(@rpc_decode_typemap)
      @doc_mapper = Mapping::WSDLLiteralRegistry.new(@wsdl_elements, @wsdl_types)
      endpoint_url = @port.soap_address.location
      # Convert a map which key is QName, to a Hash which key is String.
      @operation = {}
      @port.inputoperation_map.each do |op_name, op_info|
	@operation[op_name.name] = op_info
	add_method_interface(op_info)
      end
      @proxy = ::SOAP::RPC::Proxy.new(endpoint_url, @soapaction, @options)
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

    def rpc_call(name, *values)
      set_wiredump_file_base(name)
      unless op_info = @operation[name]
        raise MethodDefinitionError, "Method: #{name} not defined."
      end
      req_header = create_request_header
      req_body = create_request_body(op_info, *values)
      opt = create_options({
        :soapaction => op_info.soapaction || @soapaction,
        :decode_typemap => @rpc_decode_typemap})
      env = @proxy.invoke(req_header, req_body, opt)
      raise EmptyResponseError.new("Empty response.") unless env
      receive_headers(env.header)
      begin
        @proxy.check_fault(env.body)
      rescue ::SOAP::FaultError => e
	Mapping.fault2exception(e)
      end
      ret = env.body.response ?
	Mapping.soap2obj(env.body.response, @mapping_registry) : nil
      if env.body.outparams
	outparams = env.body.outparams.collect { |outparam|
  	  Mapping.soap2obj(outparam)
   	}
    	return [ret].concat(outparams)
      else
      	return ret
      end
    end

    def document_call(name, param)
      set_wiredump_file_base(name)
      op_info = @operation[name]
      req_header = header_from_obj(header_obj, op_info)
      req_body = body_from_obj(body_obj, op_info)
      env = @proxy.invoke(req_header, req_body, op_info.soapaction || @soapaction, @wsdl_types)
      raise EmptyResponseError.new("Empty response.") unless env
      if env.body.fault
	raise ::SOAP::FaultError.new(env.body.fault)
      end
      res_body_obj = env.body.response ?
	Mapping.soap2obj(env.body.response, @mapping_registry) : nil
      return env.header, res_body_obj
    end

    # req_header: [[element, mustunderstand, encodingstyle(QName/String)], ...]
    # req_body: SOAPBasetype/SOAPCompoundtype
    def document_send(name, header_obj, body_obj)
      set_wiredump_file_base(name)
      op_info = @operation[name]
      req_header = header_from_obj(header_obj, op_info)
      req_body = body_from_obj(body_obj, op_info)
      opt = create_options({
        :soapaction => op_info.soapaction || @soapaction,
        :decode_typemap => @wsdl_types})
      env = @proxy.invoke(req_header, req_body, opt)
      raise EmptyResponseError.new("Empty response.") unless env
      if env.body.fault
	raise ::SOAP::FaultError.new(env.body.fault)
      end
      res_body_obj = env.body.response ?
	Mapping.soap2obj(env.body.response, @mapping_registry) : nil
      return env.header, res_body_obj
    end

  private

    def create_options(hash = nil)
      opt = {}
      opt[:default_encodingstyle] = @default_encodingstyle
      opt[:allow_unqualified_element] = @allow_unqualified_element
      opt[:generate_explicit_type] = @generate_explicit_type
      opt.update(hash) if hash
      opt
    end

    def set_wiredump_file_base(name)
      if @wiredump_file_base
      	@proxy.set_wiredump_file_base(@wiredump_file_base + "_#{ name }")
      end
    end

    def create_request_header
      headers = @proxy.headerhandler.on_outbound
      if headers.empty?
	nil
      else
	h = SOAPHeader.new
	headers.each do |header|
	  h.add(header.elename.name, header)
	end
	h
      end
    end

    def receive_headers(headers)
      @proxy.headerhandler.on_inbound(headers) if headers
    end

    def create_request_body(op_info, *values)
      method = create_method_struct(op_info, *values)
      SOAPBody.new(method)
    end

    def create_method_struct(op_info, *params)
      parts_names = op_info.bodyparts.collect { |part| part.name }
      obj = create_method_obj(parts_names, params)
      method = Mapping.obj2soap(obj, @wsdl_mapping_registry, op_info.optype_name)
      if method.members.size != parts_names.size
	new_method = SOAPStruct.new
	method.each do |key, value|
	  if parts_names.include?(key)
	    new_method.add(key, value)
	  end
	end
	method = new_method
      end
      method.elename = op_info.op_name
      method.type = XSD::QName.new	# Request should not be typed.
      method
    end

    def create_method_obj(names, params)
      o = Object.new
      for idx in 0 ... params.length
        o.instance_variable_set('@' + names[idx], params[idx])
      end
      o
    end

    def header_from_obj(obj, op_info)
      if obj.is_a?(SOAPHeader)
	obj
      elsif op_info.headerparts.empty?
	if obj.nil?
	  nil
	else
	  raise RuntimeError.new("No header definition in schema.")
	end
      elsif op_info.headerparts.size == 1
       	part = op_info.headerparts[0]
	header = SOAPHeader.new()
	header.add(headeritem_from_obj(obj, part.element || part.eletype))
	header
      else
	header = SOAPHeader.new()
	op_info.headerparts.each do |part|
	  child = Mapping.find_attribute(obj, part.name)
	  ele = headeritem_from_obj(child, part.element || part.eletype)
	  header.add(part.name, ele)
	end
	header
      end
    end

    def headeritem_from_obj(obj, name)
      if obj.nil?
	SOAPElement.new(name)
      elsif obj.is_a?(SOAPHeaderItem)
	obj
      else
	@doc_mapper.obj2soap(obj, name)
      end
    end

    def body_from_obj(obj, op_info)
      if obj.is_a?(SOAPBody)
	obj
      elsif op_info.bodyparts.empty?
	if obj.nil?
	  nil
	else
	  raise RuntimeError.new("No body found in schema.")
	end
      elsif op_info.bodyparts.size == 1
       	part = op_info.bodyparts[0]
	ele = bodyitem_from_obj(obj, part.element || part.type)
	SOAPBody.new(ele)
      else
	body = SOAPBody.new
	op_info.bodyparts.each do |part|
	  child = Mapping.find_attribute(obj, part.name)
	  ele = bodyitem_from_obj(child, part.element || part.type)
	  body.add(ele.elename.name, ele)
	end
	body
      end
    end

    def bodyitem_from_obj(obj, name)
      if obj.nil?
	SOAPElement.new(name)
      elsif obj.is_a?(SOAPElement)
	obj
      else
	@doc_mapper.obj2soap(obj, name)
      end
    end

    def add_method_interface(op_info)
      name = ::XSD::CodeGen::GenSupport.safemethodname(op_info.op_name.name)
      case op_info.style
      when :document
	add_document_method_interface(name)
      when :rpc
	parts_names = op_info.bodyparts.collect { |part| part.name }
	add_rpc_method_interface(name, parts_names)
      else
	raise RuntimeError.new("Unknown style: #{op_info.style}")
      end
    end

    def add_rpc_method_interface(name, parts_names)
      sclass = class << @host; self; end
      sclass.__send__(:define_method, name, proc { |*arg|
        unless arg.size == parts_names.size
          raise ArgumentError.new(
            "wrong number of arguments (#{arg.size} for #{parts_names.size})")
        end
        @servant.rpc_call(name, *arg)
      })
      @host.method(name)
    end

    def add_document_method_interface(name)
      sclass = class << @host; self; end
      sclass.__send__(:define_method, name, proc { |h, b|
        @servant.document_send(name, h, b)
      })
      @host.method(name)
    end

    def setup_options
      if opt = Property.loadproperty(::SOAP::PropertyName)
	opt = opt["client"]
      end
      opt ||= Property.new
      opt.add_hook("protocol.mandatorycharset") do |key, value|
	@mandatorycharset = value
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


