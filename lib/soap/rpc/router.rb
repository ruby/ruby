# SOAP4R - RPC Routing library
# Copyright (C) 2001, 2002  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/soap'
require 'soap/processor'
require 'soap/mapping'
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
  attr_reader :headerhandler

  def initialize(actor)
    @actor = actor
    @receiver = {}
    @method_name = {}
    @method = {}
    @allow_unqualified_element = false
    @default_encodingstyle = nil
    @mapping_registry = nil
    @headerhandler = Header::HandlerSet.new
  end

  def add_method(receiver, qname, soapaction, name, param_def)
    fqname = fqname(qname)
    @receiver[fqname] = receiver
    @method_name[fqname] = name
    @method[fqname] = RPC::SOAPMethodRequest.new(qname, param_def, soapaction)
  end

  def route(conn_data)
    soap_response = nil
    begin
      env = unmarshal(conn_data)
      if env.nil?
	raise ArgumentError.new("Illegal SOAP marshal format.")
      end
      receive_headers(env.header)
      soap_request = env.body.request
      unless soap_request.is_a?(SOAPStruct)
	raise RPCRoutingError.new("Not an RPC style.")
      end
      soap_response = dispatch(soap_request)
    rescue Exception
      soap_response = fault($!)
      conn_data.is_fault = true
    end

    opt = options
    opt[:external_content] = nil
    header = call_headers
    body = SOAPBody.new(soap_response)
    env = SOAPEnvelope.new(header, body)
    response_string = Processor.marshal(env, opt)
    conn_data.send_string = response_string
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

  # Create new response.
  def create_response(qname, result)
    name = fqname(qname)
    if (@method.key?(name))
      method = @method[name]
    else
      raise RPCRoutingError.new("Method: #{ name } not defined.")
    end

    soap_response = method.create_method_response
    if soap_response.have_outparam?
      unless result.is_a?(Array)
	raise RPCRoutingError.new("Out parameter was not returned.")
      end
      outparams = {}
      i = 1
      soap_response.each_param_name('out', 'inout') do |outparam|
	outparams[outparam] = Mapping.obj2soap(result[i], @mapping_registry)
	i += 1
      end
      soap_response.set_outparam(outparams)
      soap_response.retval = Mapping.obj2soap(result[0], @mapping_registry)
    else
      soap_response.retval = Mapping.obj2soap(result, @mapping_registry)
    end
    soap_response
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

  # Dispatch to defined method.
  def dispatch(soap_method)
    request_struct = Mapping.soap2obj(soap_method, @mapping_registry)
    values = soap_method.collect { |key, value| request_struct[key] }
    method = lookup(soap_method.elename, values)
    unless method
      raise RPCRoutingError.new(
	"Method: #{ soap_method.elename } not supported.")
    end

    result = method.call(*values)
    create_response(soap_method.elename, result)
  end

  # Method lookup
  def lookup(qname, values)
    name = fqname(qname)
    # It may be necessary to check all part of method signature...
    if @method.member?(name)
      @receiver[name].method(@method_name[name].intern)
    else
      nil
    end
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
end


end
end
