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
require 'soap/mapping/wsdlRegistry'
require 'soap/rpc/rpc'
require 'soap/rpc/element'
require 'soap/processor'
require 'soap/header/handlerset'
require 'logger'


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
  __attr_proxy :headerhandler
  __attr_proxy :test_loopback_response
  __attr_proxy :endpoint_url, true
  __attr_proxy :mapping_registry, true		# for RPC unmarshal
  __attr_proxy :wsdl_mapping_registry, true	# for RPC marshal
  __attr_proxy :default_encodingstyle, true
  __attr_proxy :allow_unqualified_element, true
  __attr_proxy :generate_explicit_type, true

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
    @servant.streamhandler.reset
  end

  # Backward compatibility.
  alias generateEncodeType= generate_explicit_type=

  class Servant__
    include Logger::Severity
    include SOAP

    attr_reader :options
    attr_reader :streamhandler
    attr_reader :headerhandler
    attr_reader :port

    attr_accessor :mapping_registry
    attr_accessor :wsdl_mapping_registry
    attr_accessor :default_encodingstyle
    attr_accessor :allow_unqualified_element
    attr_accessor :generate_explicit_type

    def initialize(host, wsdl, port, logdev)
      @host = host
      @wsdl = wsdl
      @port = port
      @logdev = logdev

      @options = setup_options
      @mapping_registry = nil		# for rpc unmarshal
      @wsdl_mapping_registry = nil	# for rpc marshal
      @default_encodingstyle = EncodingNamespace
      @allow_unqualified_element = true
      @generate_explicit_type = false
      @wiredump_file_base = nil
      @mandatorycharset = nil

      @wsdl_elements = @wsdl.collect_elements
      @wsdl_types = @wsdl.collect_complextypes + @wsdl.collect_simpletypes
      @rpc_decode_typemap = @wsdl_types +
	@wsdl.soap_rpc_complextypes(port.find_binding)
      @wsdl_mapping_registry = Mapping::WSDLRegistry.new(@rpc_decode_typemap)
      @doc_mapper = Mapper.new(@wsdl_elements, @wsdl_types)
      endpoint_url = @port.soap_address.location
      @streamhandler = HTTPPostStreamHandler.new(endpoint_url,
	@options["protocol.http"] ||= Property.new)
      @headerhandler = Header::HandlerSet.new
      # Convert a map which key is QName, to a Hash which key is String.
      @operations = {}
      @port.inputoperation_map.each do |op_name, op_info|
	@operations[op_name.name] = op_info
	add_method_interface(op_info)
      end
    end

    def endpoint_url
      @streamhandler.endpoint_url
    end

    def endpoint_url=(endpoint_url)
      @streamhandler.endpoint_url = endpoint_url
      @streamhandler.reset
    end

    def test_loopback_response
      @streamhandler.test_loopback_response
    end

    def rpc_send(method_name, *params)
      log(INFO) { "call: calling method '#{ method_name }'." }
      log(DEBUG) { "call: parameters '#{ params.inspect }'." }

      op_info = @operations[method_name]
      method = create_method_struct(op_info, params)
      req_header = call_headers
      req_body = SOAPBody.new(method)
      req_env = SOAPEnvelope.new(req_header, req_body)

      if @wiredump_file_base
	@streamhandler.wiredump_file_base =
	  @wiredump_file_base + '_' << method_name
      end

      begin
	opt = create_options
	opt[:decode_typemap] = @rpc_decode_typemap
	res_env = invoke(req_env, op_info, opt)
	receive_headers(res_env.header)
	if res_env.body.fault
	  raise ::SOAP::FaultError.new(res_env.body.fault)
	end
      rescue ::SOAP::FaultError => e
	Mapping.fault2exception(e)
      end

      ret = res_env.body.response ?
	Mapping.soap2obj(res_env.body.response, @mapping_registry) : nil

      if res_env.body.outparams
	outparams = res_env.body.outparams.collect { |outparam|
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
      req_env = SOAPEnvelope.new(req_header, req_body)
      opt = create_options
      res_env = invoke(req_env, op_info, opt)
      if res_env.body.fault
	raise ::SOAP::FaultError.new(res_env.body.fault)
      end
      res_body_obj = res_env.body.response ?
	Mapping.soap2obj(res_env.body.response, @mapping_registry) : nil
      return res_env.header, res_body_obj
    end

  private

    def call_headers
      headers = @headerhandler.on_outbound
      if headers.empty?
	nil
      else
	h = ::SOAP::SOAPHeader.new
	headers.each do |header|
	  h.add(header.elename.name, header)
	end
	h
      end
    end

    def receive_headers(headers)
      @headerhandler.on_inbound(headers) if headers
    end

    def create_method_struct(op_info, params)
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
	o.instance_eval("@#{ names[idx] } = params[idx]")
      end
      o
    end

    def invoke(req_env, op_info, opt)
      opt[:external_content] = nil
      send_string = Processor.marshal(req_env, opt)
      log(DEBUG) { "invoke: sending string #{ send_string }" }
      conn_data = StreamHandler::ConnectionData.new(send_string)
      if ext = opt[:external_content]
       	mime = MIMEMessage.new
	ext.each do |k, v|
	  mime.add_attachment(v.data)
	end
	mime.add_part(conn_data.send_string + "\r\n")
	mime.close
	conn_data.send_string = mime.content_str
	conn_data.send_contenttype = mime.headers['content-type'].str
      end
      conn_data = @streamhandler.send(conn_data, op_info.soapaction)
      log(DEBUG) { "invoke: received string #{ conn_data.receive_string }" }
      if conn_data.receive_string.empty?
	return nil, nil
      end
      unmarshal(conn_data, opt)
    end

    def unmarshal(conn_data, opt)
      contenttype = conn_data.receive_contenttype
      if /#{MIMEMessage::MultipartContentType}/i =~ contenttype
	opt[:external_content] = {}
	mime = MIMEMessage.parse("Content-Type: " + contenttype,
	  conn_data.receive_string)
	mime.parts.each do |part|
	  value = Attachment.new(part.content)
	  value.contentid = part.contentid
	  obj = SOAPAttachment.new(value)
	  opt[:external_content][value.contentid] = obj if value.contentid
	end
	opt[:charset] = @mandatorycharset ||
	  StreamHandler.parse_media_type(mime.root.headers['content-type'].str)
	env = Processor.unmarshal(mime.root.content, opt)
      else
	opt[:charset] = @mandatorycharset ||
	::SOAP::StreamHandler.parse_media_type(contenttype)
	env = Processor.unmarshal(conn_data.receive_string, opt)
      end
      env
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
	  child = Mapper.find_attribute(obj, part.name)
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
	  child = Mapper.find_attribute(obj, part.name)
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
      callparam = (param_names.collect { |pname| ", " + pname }).join
      @host.instance_eval <<-EOS
	def #{ name }(#{ param_names.join(", ") })
	  @servant.rpc_send(#{ name.dump }#{ callparam })
	end
      EOS
    end

    def create_options
      opt = {}
      opt[:default_encodingstyle] = @default_encodingstyle
      opt[:allow_unqualified_element] = @allow_unqualified_element
      opt[:generate_explicit_type] = @generate_explicit_type
      opt
    end

    def log(sev)
      @logdev.add(sev, nil, self.class) { yield } if @logdev
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

    class MappingError < StandardError; end
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
	  raise MappingError.new("Cannot find name #{name} in schema.")
	end
      end

      def ele2obj(ele, *arg)
	raise NotImplementedError.new
      end

      def Mapper.find_attribute(obj, attr_name)
	if obj.respond_to?(attr_name)
	  obj.__send__(attr_name)
	elsif obj.is_a?(Hash)
	  obj[attr_name] || obj[attr_name.intern]
	else
	  obj.instance_eval("@#{ attr_name }")
	end
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
	    raise MappingError.new("Cannot find type #{ele.type}.")
	  end
	  o.elename = ele.name
	elsif ele.local_complextype
	  o = SOAPElement.new(ele.name)
	  ele.local_complextype.each_element do |child_ele|
            o.add(_obj2ele(Mapper.find_attribute(obj, child_ele.name.name),
              child_ele))
	  end
	else
	  raise MappingError.new("Illegal schema?")
	end
	o
      end

      def obj2type(obj, type)
        if type.is_a?(::WSDL::XMLSchema::SimpleType)
          simple2soap(obj, type)
        else
          complex2soap(obj, type)
        end
      end

      def simple2soap(obj, type)
        o = base2soap(obj, TypeMap[type.base])
        if type.restriction.enumeration.empty?
          STDERR.puts("#{type.name}: simpleType which is not enum type not supported.")
          return o
        end
        if type.restriction.enumeration.include?(o)
	  raise MappingError.new("#{o} is not allowed for #{type.name}")
        end
        o
      end

      def complex2soap(obj, type)
        o = SOAPElement.new(type.name)
        type.each_element do |child_ele|
          o.add(_obj2ele(Mapper.find_attribute(obj, child_ele.name.name),
            child_ele))
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
	    XSD::Charset.encoding_conv(obj, $KCODE, XSD::Charset.encoding) :
	    obj)
	else
	  soap_obj = type.new(obj)
	end
	soap_obj
      end
    end
  end
end


end


