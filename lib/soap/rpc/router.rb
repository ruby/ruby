# SOAP4R - RPC Routing library
# Copyright (C) 2001, 2002  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/soap'
require 'soap/processor'
require 'soap/mapping'
require 'soap/mapping/wsdlliteralregistry'
require 'soap/rpc/rpc'
require 'soap/rpc/element'
require 'soap/streamHandler'
require 'soap/mimemessage'
require 'soap/header/handlerset'


module SOAP
module RPC


class Router
  include SOAP

  attr_reader :actor
  attr_accessor :allow_unqualified_element
  attr_accessor :default_encodingstyle
  attr_accessor :mapping_registry
  attr_accessor :literal_mapping_registry
  attr_reader :headerhandler

  def initialize(actor)
    @actor = actor
    @allow_unqualified_element = false
    @default_encodingstyle = nil
    @mapping_registry = nil
    @headerhandler = Header::HandlerSet.new
    @literal_mapping_registry = ::SOAP::Mapping::WSDLLiteralRegistry.new
    @operation = {}
  end

  def add_rpc_method(receiver, qname, soapaction, name, param_def, opt = {})
    opt[:request_style] ||= :rpc
    opt[:response_style] ||= :rpc
    opt[:request_use] ||= :encoded
    opt[:response_use] ||= :encoded
    add_operation(qname, soapaction, receiver, name, param_def, opt)
  end

  def add_document_method(receiver, qname, soapaction, name, param_def, opt = {})
    opt[:request_style] ||= :document
    opt[:response_style] ||= :document
    opt[:request_use] ||= :encoded
    opt[:response_use] ||= :encoded
    if opt[:request_style] == :document
      inputdef = param_def.find { |inout, paramname, typeinfo| inout == "input" }
      klass, nsdef, namedef = inputdef[2]
      qname = ::XSD::QName.new(nsdef, namedef)
    end
    add_operation(qname, soapaction, receiver, name, param_def, opt)
  end

  def add_operation(qname, soapaction, receiver, name, param_def, opt)
    @operation[fqname(qname)] = Operation.new(qname, soapaction, receiver,
      name, param_def, opt)
  end

  # add_method is for shortcut of typical use="encoded" method definition.
  alias add_method add_rpc_method

  def route(conn_data)
    soap_response = nil
    begin
      env = unmarshal(conn_data)
      if env.nil?
	raise ArgumentError.new("Illegal SOAP marshal format.")
      end
      receive_headers(env.header)
      request = env.body.request
      op = @operation[fqname(request.elename)]
      unless op
        raise RPCRoutingError.new("Method: #{request.elename} not supported.")
      end
      soap_response = op.call(request, @mapping_registry, @literal_mapping_registry)
    rescue Exception
      soap_response = fault($!)
      conn_data.is_fault = true
    end
    marshal(conn_data, op, soap_response)
    conn_data
  end

  # Create fault response string.
  def create_fault_response(e, charset = nil)
    header = SOAPHeader.new
    body = SOAPBody.new(fault(e))
    env = SOAPEnvelope.new(header, body)
    opt = options
    opt[:external_content] = nil
    opt[:charset] = charset
    response_string = Processor.marshal(env, opt)
    conn_data = StreamHandler::ConnectionData.new(response_string)
    conn_data.is_fault = true
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
    conn_data
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

  def unmarshal(conn_data)
    opt = options
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
      opt[:charset] =
	StreamHandler.parse_media_type(mime.root.headers['content-type'].str)
      env = Processor.unmarshal(mime.root.content, opt)
    else
      opt[:charset] = ::SOAP::StreamHandler.parse_media_type(contenttype)
      env = Processor.unmarshal(conn_data.receive_string, opt)
    end
    charset = opt[:charset]
    conn_data.send_contenttype = "text/xml; charset=\"#{charset}\""
    env
  end

  def marshal(conn_data, op, soap_response)
    response_opt = options
    response_opt[:external_content] = nil
    if op and !conn_data.is_fault and op.response_use == :document
      response_opt[:default_encodingstyle] =
        ::SOAP::EncodingStyle::ASPDotNetHandler::Namespace
    end
    header = call_headers
    body = SOAPBody.new(soap_response)
    env = SOAPEnvelope.new(header, body)
    response_string = Processor.marshal(env, response_opt)
    conn_data.send_string = response_string
    if ext = response_opt[:external_content]
      mime = MIMEMessage.new
      ext.each do |k, v|
      	mime.add_attachment(v.data)
      end
      mime.add_part(conn_data.send_string + "\r\n")
      mime.close
      conn_data.send_string = mime.content_str
      conn_data.send_contenttype = mime.headers['content-type'].str
    end
  end

  # Create fault response.
  def fault(e)
    detail = Mapping::SOAPException.new(e)
    SOAPFault.new(
      SOAPString.new('Server'),
      SOAPString.new(e.to_s),
      SOAPString.new(@actor),
      Mapping.obj2soap(detail, @mapping_registry))
  end

  def fqname(qname)
    "#{ qname.namespace }:#{ qname.name }"
  end

  def options
    opt = {}
    opt[:default_encodingstyle] = @default_encodingstyle
    if @allow_unqualified_element
      opt[:allow_unqualified_element] = true
    end
    opt
  end

  class Operation
    attr_reader :receiver
    attr_reader :name
    attr_reader :soapaction
    attr_reader :request_style
    attr_reader :response_style
    attr_reader :request_use
    attr_reader :response_use
    
    def initialize(qname, soapaction, receiver, name, param_def, opt)
      @soapaction = soapaction
      @receiver = receiver
      @name = name
      @request_style = opt[:request_style]
      @response_style = opt[:response_style]
      @request_use = opt[:request_use]
      @response_use = opt[:response_use]
      if @response_style == :rpc
        @rpc_response_factory =
          RPC::SOAPMethodRequest.new(qname, param_def, @soapaction)
      else
        outputdef = param_def.find { |inout, paramname, typeinfo| inout == "output" }
        klass, nsdef, namedef = outputdef[2]
        @document_response_qname = ::XSD::QName.new(nsdef, namedef)
      end
    end

    def call(request, mapping_registry, literal_mapping_registry)
      if @request_style == :rpc
        param = Mapping.soap2obj(request, mapping_registry)
        result = rpc_call(request, param)
      else
        param = Mapping.soap2obj(request, literal_mapping_registry)
        result = document_call(request, param)
      end
      if @response_style == :rpc
        rpc_response(result, mapping_registry)
      else
        document_response(result, literal_mapping_registry)
      end
    end

  private

    def rpc_call(request, param)
      unless request.is_a?(SOAPStruct)
        raise RPCRoutingError.new("Not an RPC style.")
      end
      values = request.collect { |key, value| param[key] }
      @receiver.method(@name.intern).call(*values)
    end

    def document_call(request, param)
      @receiver.method(@name.intern).call(param)
    end

    def rpc_response(result, mapping_registry)
      soap_response = @rpc_response_factory.create_method_response
      if soap_response.have_outparam?
        unless result.is_a?(Array)
          raise RPCRoutingError.new("Out parameter was not returned.")
        end
        outparams = {}
        i = 1
        soap_response.each_param_name('out', 'inout') do |outparam|
          outparams[outparam] = Mapping.obj2soap(result[i], mapping_registry)
          i += 1
        end
        soap_response.set_outparam(outparams)
        soap_response.retval = Mapping.obj2soap(result[0], mapping_registry)
      else
        soap_response.retval = Mapping.obj2soap(result, mapping_registry)
      end
      soap_response
    end

    def document_response(result, literal_mapping_registry)
      literal_mapping_registry.obj2soap(result, @document_response_qname)
    end
  end
end


end
end
