=begin
SOAP4R - SOAP WSDL driver
Copyright (C) 2002, 2003  NAKAMURA, Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end


require 'wsdl/parser'
require 'wsdl/importer'
require 'xsd/qname'
require 'soap/element'
require 'soap/baseData'
require 'soap/streamHandler'
require 'soap/mapping'
require 'soap/mapping/wsdlRegistry'
require 'soap/rpc/rpc'
require 'soap/rpc/element'
require 'soap/processor'
require 'logger'


module SOAP


class WSDLDriverFactory
  class FactoryError < StandardError; end

  attr_reader :wsdl

  def initialize(wsdl, logdev = nil)
    @logdev = logdev
    @wsdl = import(wsdl)
  end

  def create_driver(servicename = nil, portname = nil, opt = {})
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
    WSDLDriver.new(@wsdl, port, @logdev, opt)
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

  __attr_proxy :opt
  __attr_proxy :logdev, true
  __attr_proxy :mapping_registry, true		# for RPC unmarshal
  __attr_proxy :wsdl_mapping_registry, true	# for RPC marshal
  __attr_proxy :endpoint_url, true
  __attr_proxy :wiredump_dev, true
  __attr_proxy :wiredump_file_base, true
  __attr_proxy :httpproxy, true

  __attr_proxy :default_encodingstyle, true
  __attr_proxy :allow_unqualified_element, true
  __attr_proxy :generate_explicit_type, true

  def reset_stream
    @servant.reset_stream
  end

  # Backward compatibility.
  alias generateEncodeType= generate_explicit_type=

  class Servant__
    include Logger::Severity
    include SOAP

    attr_reader :opt
    attr_accessor :logdev
    attr_accessor :mapping_registry
    attr_accessor :wsdl_mapping_registry
    attr_reader :endpoint_url
    attr_reader :wiredump_dev
    attr_reader :wiredump_file_base
    attr_reader :httpproxy

    attr_accessor :default_encodingstyle
    attr_accessor :allow_unqualified_element
    attr_accessor :generate_explicit_type

    class Mapper
      def initialize(elements, types)
	@elements = elements
	@types = types
      end

      def obj2ele(obj, name)
	if ele = @elements[name]
	  _obj2ele(obj, ele)
	elsif type = @types[name]
	  obj2type(obj, type)
	else
	  raise RuntimeError.new("Cannot find name #{name} in schema.")
	end
      end

      def ele2obj(ele, *arg)
	raise NotImplementedError.new
      end

    private

      def _obj2ele(obj, ele)
	o = nil
	if ele.type
	  if type = @types[ele.type]
	    o = obj2type(obj, type)
	  elsif type = TypeMap[ele.type]
	    o = base2soap(obj, type)
	  else
	    raise RuntimeError.new("Cannot find type #{ele.type}.")
	  end
	  o.elename = ele.name
	elsif ele.local_complextype
	  o = SOAPElement.new(ele.name)
	  ele.local_complextype.each_element do |child_name, child_ele|
	    o.add(_obj2ele(find_attribute(obj, child_name.name), child_ele))
	  end
	else
	  raise RuntimeError.new("Illegal schema?")
	end
	o
      end

      def obj2type(obj, type)
	o = SOAPElement.new(type.name)
	type.each_element do |child_name, child_ele|
	  o.add(_obj2ele(find_attribute(obj, child_name.name), child_ele))
	end
	o
      end

      def _ele2obj(ele)
	raise NotImplementedError.new
      end

      def base2soap(obj, type)
	soap_obj = nil
	if type <= XSD::XSDString
	  soap_obj = type.new(XSD::Charset.is_ces(obj, $KCODE) ?
	    XSD::Charset.encoding_conv(obj, $KCODE, XSD::Charset.encoding) : obj)
	else
	  soap_obj = type.new(obj)
	end
	soap_obj
      end

      def find_attribute(obj, attr_name)
	if obj.respond_to?(attr_name)
	  obj.__send__(attr_name)
	elsif obj.is_a?(Hash)
	  obj[attr_name] || obj[attr_name.intern]
	else
	  obj.instance_eval("@#{ attr_name }")
	end
      end
    end

    def initialize(host, wsdl, port, logdev, opt)
      @host = host
      @wsdl = wsdl
      @port = port
      @logdev = logdev
      @opt = opt.dup
      @mapping_registry = nil		# for rpc unmarshal
      @wsdl_mapping_registry = nil	# for rpc marshal
      @endpoint_url = nil
      @wiredump_dev = nil
      @wiredump_file_base = nil
      name = 'http_proxy'
      @httpproxy = ENV[name] || ENV[name.upcase]

      @wsdl_elements = @wsdl.collect_elements
      @wsdl_types = @wsdl.collect_complextypes
      @rpc_decode_typemap = @wsdl_types + @wsdl.soap_rpc_complextypes(port.find_binding)
      @wsdl_mapping_registry = Mapping::WSDLRegistry.new(@rpc_decode_typemap)
      @doc_mapper = Mapper.new(@wsdl_elements, @wsdl_types)
      @default_encodingstyle = EncodingNamespace
      @allow_unqualified_element = true
      @generate_explicit_type = false

      create_handler
      @operations = {}
      # Convert a map which key is QName, to a Hash which key is String.
      @port.inputoperation_map.each do |op_name, op_info|
	@operations[op_name.name] = op_info
	add_method_interface(op_info)
      end
    end

    def endpoint_url=(endpoint_url)
      @endpoint_url = endpoint_url
      if @handler
	@handler.endpoint_url = @endpoint_url
	@handler.reset
      end
      log(DEBUG) { "endpoint_url=: set endpoint_url #{ @endpoint_url }." }
    end

    def wiredump_dev=(dev)
      @wiredump_dev = dev
      if @handler
	@handler.wiredump_dev = @wiredump_dev
	@handler.reset
      end
    end

    def wiredump_file_base=(base)
      @wiredump_file_base = base
    end

    def httpproxy=(httpproxy)
      @httpproxy = httpproxy
      if @handler
	@handler.proxy = @httpproxy
	@handler.reset
      end
      log(DEBUG) { "httpproxy=: set httpproxy #{ @httpproxy }." }
    end

    def reset_stream
      @handler.reset
    end

    def rpc_send(method_name, *params)
      log(INFO) { "call: calling method '#{ method_name }'." }
      log(DEBUG) { "call: parameters '#{ params.inspect }'." }

      op_info = @operations[method_name]
      parts_names = op_info.bodyparts.collect { |part| part.name }
      obj = create_method_obj(parts_names, params)
      method = Mapping.obj2soap(obj, @wsdl_mapping_registry, op_info.optype_name)
      method.elename = op_info.op_name
      method.type = XSD::QName.new	# Request should not be typed.
      req_header = nil
      req_body = SOAPBody.new(method)

      if @wiredump_file_base
	@handler.wiredump_file_base = @wiredump_file_base + '_' << method_name
      end

      begin
	opt = create_options
	opt[:decode_typemap] = @rpc_decode_typemap
	res_header, res_body = invoke(req_header, req_body, op_info, opt)
	if res_body.fault
	  raise SOAP::FaultError.new(res_body.fault)
	end
      rescue SOAP::FaultError => e
	Mapping.fault2exception(e)
      end

      ret = res_body.response ?
	Mapping.soap2obj(res_body.response, @mapping_registry) : nil

      if res_body.outparams
	outparams = res_body.outparams.collect { |outparam|
  	  Mapping.soap2obj(outparam)
   	}
    	return [ret].concat(outparams)
      else
      	return ret
      end
    end

    # req_header: [[element, mustunderstand, encodingstyle(QName/String)], ...]
    # req_body: SOAPBasetype/SOAPCompoundtype
    def document_send(name, header_obj, body_obj)
      log(INFO) { "document_send: sending document '#{ name }'." }
      op_info = @operations[name]
      req_header = header_from_obj(header_obj, op_info)
      req_body = body_from_obj(body_obj, op_info)
      opt = create_options
      res_header, res_body = invoke(req_header, req_body, op_info, opt)
      if res_body.fault
	raise SOAP::FaultError.new(res_body.fault)
      end
      res_body_obj = res_body.response ?
	Mapping.soap2obj(res_body.response, @mapping_registry) : nil
      return res_header, res_body_obj
    end

  private

    def create_handler
      endpoint_url = @endpoint_url || @port.soap_address.location
      @handler = HTTPPostStreamHandler.new(endpoint_url, @httpproxy,
	XSD::Charset.encoding_label)
      @handler.wiredump_dev = @wiredump_dev
    end

    def create_method_obj(names, params)
      o = Object.new
      for idx in 0 ... params.length
	o.instance_eval("@#{ names[idx] } = params[idx]")
      end
      o
    end

    def invoke(req_header, req_body, op_info, opt)
      send_string = Processor.marshal(req_header, req_body, opt)
      log(DEBUG) { "invoke: sending string #{ send_string }" }
      data = @handler.send(send_string, op_info.soapaction)
      log(DEBUG) { "invoke: received string #{ data.receive_string }" }
      if data.receive_string.empty?
	return nil, nil
      end
      res_charset = StreamHandler.parse_media_type(data.receive_contenttype)
      opt[:charset] = res_charset
      res_header, res_body = Processor.unmarshal(data.receive_string, opt)
      return res_header, res_body
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
	  child = obj[part.elename.name]
	  ele = headeritem_from_obj(child, part.element || part.eletype)
	  header.add(ele)
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
	@doc_mapper.obj2ele(obj, name)
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
	  child = obj[part.elename.name]
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
	@doc_mapper.obj2ele(obj, name)
      end
    end

    def add_method_interface(op_info)
      case op_info.style
      when :document
	add_document_method_interface(op_info.op_name.name)
      when :rpc
	parts_names = op_info.bodyparts.collect { |part| part.name }
	add_rpc_method_interface(op_info.op_name.name, parts_names)
      else
	raise RuntimeError.new("Unknown style: #{op_info.style}")
      end
    end

    def add_document_method_interface(name)
      @host.instance_eval <<-EOS
	def #{ name }(headers, body)
	  @servant.document_send(#{ name.dump }, headers, body)
	end
      EOS
    end

    def add_rpc_method_interface(name, parts_names)
      i = 0
      param_names = parts_names.collect { |orgname| i += 1; "arg#{ i }" }
      callparam_str = (param_names.collect { |pname| ", " + pname }).join
      @host.instance_eval <<-EOS
	def #{ name }(#{ param_names.join(", ") })
	  @servant.rpc_send(#{ name.dump }#{ callparam_str })
	end
      EOS
    end

    def create_options
      opt = @opt.dup
      opt[:default_encodingstyle] = @default_encodingstyle
      opt[:allow_unqualified_element] = @allow_unqualified_element
      opt[:generate_explicit_type] = @generate_explicit_type
      opt
    end

    def log(sev)
      @logdev.add(sev, nil, self.class) { yield } if @logdev
    end
  end

  def initialize(wsdl, port, logdev, opt)
    @servant = Servant__.new(self, wsdl, port, logdev, opt)
  end
end


end


