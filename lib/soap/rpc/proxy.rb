# SOAP4R - RPC Proxy library.
# Copyright (C) 2000, 2003, 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

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


module SOAP
module RPC


class Proxy
  include SOAP

public

  attr_accessor :soapaction
  attr_accessor :mandatorycharset
  attr_accessor :allow_unqualified_element
  attr_accessor :default_encodingstyle
  attr_accessor :generate_explicit_type
  attr_reader :headerhandler
  attr_reader :streamhandler

  attr_accessor :mapping_registry
  attr_accessor :literal_mapping_registry

  attr_reader :operation

  def initialize(endpoint_url, soapaction, options)
    @endpoint_url = endpoint_url
    @soapaction = soapaction
    @options = options
    @streamhandler = HTTPStreamHandler.new(
      @options["protocol.http"] ||= ::SOAP::Property.new)
    @operation = {}
    @mandatorycharset = nil
    @allow_unqualified_element = true
    @default_encodingstyle = nil
    @generate_explicit_type = true
    @headerhandler = Header::HandlerSet.new
    @mapping_registry = nil
    @literal_mapping_registry = ::SOAP::Mapping::WSDLLiteralRegistry.new
  end

  def inspect
    "#<#{self.class}:#{@endpoint_url}>"
  end

  def endpoint_url
    @endpoint_url
  end

  def endpoint_url=(endpoint_url)
    @endpoint_url = endpoint_url
    reset_stream
  end

  def reset_stream
    @streamhandler.reset(@endpoint_url)
  end

  def set_wiredump_file_base(wiredump_file_base)
    @streamhandler.wiredump_file_base = wiredump_file_base
  end

  def test_loopback_response
    @streamhandler.test_loopback_response
  end

  def add_rpc_method(qname, soapaction, name, param_def, opt = {})
    opt[:request_style] ||= :rpc
    opt[:response_style] ||= :rpc
    opt[:request_use] ||= :encoded
    opt[:response_use] ||= :encoded
    @operation[name] = Operation.new(qname, soapaction, name, param_def, opt)
  end

  def add_document_method(qname, soapaction, name, param_def, opt = {})
    opt[:request_style] ||= :document
    opt[:response_style] ||= :document
    opt[:request_use] ||= :literal
    opt[:response_use] ||= :literal
    @operation[name] = Operation.new(qname, soapaction, name, param_def, opt)
  end

  # add_method is for shortcut of typical rpc/encoded method definition.
  alias add_method add_rpc_method

  def invoke(req_header, req_body, opt = create_options)
    req_env = SOAPEnvelope.new(req_header, req_body)
    opt[:external_content] = nil
    conn_data = marshal(req_env, opt)
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
    conn_data = @streamhandler.send(@endpoint_url, conn_data, opt[:soapaction])
    if conn_data.receive_string.empty?
      return nil
    end
    unmarshal(conn_data, opt)
  end

  def call(name, *params)
    unless op_info = @operation[name]
      raise MethodDefinitionError, "Method: #{name} not defined."
    end
    req_header = create_request_header
    req_body = op_info.create_request_body(params, @mapping_registry,
      @literal_mapping_registry)
    opt = create_options({
      :soapaction => op_info.soapaction || @soapaction,
      :default_encodingstyle => op_info.response_default_encodingstyle})
    env = invoke(req_header, req_body, opt)
    receive_headers(env.header)
    raise EmptyResponseError.new("Empty response.") unless env
    begin
      check_fault(env.body)
    rescue ::SOAP::FaultError => e
      Mapping.fault2exception(e)
    end
    op_info.create_response_obj(env, @mapping_registry,
      @literal_mapping_registry)
  end

  def check_fault(body)
    if body.fault
      raise SOAP::FaultError.new(body.fault)
    end
  end

private

  def create_request_header
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

  def marshal(env, opt)
    send_string = Processor.marshal(env, opt)
    StreamHandler::ConnectionData.new(send_string)
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

  def create_header(headers)
    header = SOAPHeader.new()
    headers.each do |content, mustunderstand, encodingstyle|
      header.add(SOAPHeaderItem.new(content, mustunderstand, encodingstyle))
    end
    header
  end

  def create_options(hash = nil)
    opt = {}
    opt[:default_encodingstyle] = @default_encodingstyle
    opt[:allow_unqualified_element] = @allow_unqualified_element
    opt[:generate_explicit_type] = @generate_explicit_type
    opt.update(hash) if hash
    opt
  end

  class Operation
    attr_reader :soapaction
    attr_reader :request_style
    attr_reader :response_style
    attr_reader :request_use
    attr_reader :response_use

    def initialize(qname, soapaction, name, param_def, opt)
      @soapaction = soapaction
      @request_style = opt[:request_style]
      @response_style = opt[:response_style]
      @request_use = opt[:request_use]
      @response_use = opt[:response_use]
      @rpc_method_factory = @document_method_name = nil
      check_style(@request_style)
      check_style(@response_style)
      if @request_style == :rpc
        @rpc_method_factory = SOAPMethodRequest.new(qname, param_def,
          @soapaction)
      else
        @document_method_name = {}
        param_def.each do |inout, paramname, typeinfo|
          klass, namespace, name = typeinfo
          case inout.to_s
          when "input"
            @document_method_name[:input] = ::XSD::QName.new(namespace, name)
          when "output"
            @document_method_name[:output] = ::XSD::QName.new(namespace, name)
          else
            raise MethodDefinitionError, "unknown type: " + inout
          end
        end
      end
    end

    def request_default_encodingstyle
      (@request_style == :rpc) ? EncodingNamespace : LiteralNamespace
    end

    def response_default_encodingstyle
      (@response_style == :rpc) ? EncodingNamespace : LiteralNamespace
    end

    # for rpc
    def each_param_name(*target)
      if @request_style == :rpc
        @rpc_method_factory.each_param_name(*target) do |name|
          yield(name)
        end
      else
        yield(@document_method_name[:input].name)
      end
    end

    def create_request_body(values, mapping_registry, literal_mapping_registry)
      if @request_style == :rpc
        values = Mapping.obj2soap(values, mapping_registry).to_a
        method = @rpc_method_factory.dup
        params = {}
        idx = 0
        method.each_param_name(::SOAP::RPC::SOAPMethod::IN,
            ::SOAP::RPC::SOAPMethod::INOUT) do |name|
          params[name] = values[idx] || SOAPNil.new
          idx += 1
        end
        method.set_param(params)
        SOAPBody.new(method)
      else
        name = @document_method_name[:input]
        document = literal_mapping_registry.obj2soap(values[0], name)
        SOAPBody.new(document)
      end
    end

    def create_response_obj(env, mapping_registry, literal_mapping_registry)
      if @response_style == :rpc
        ret = env.body.response ?
          Mapping.soap2obj(env.body.response, mapping_registry) : nil
        if env.body.outparams
          outparams = env.body.outparams.collect { |outparam|
            Mapping.soap2obj(outparam)
          }
          [ret].concat(outparams)
        else
          ret
        end
      else
        Mapping.soap2obj(env.body.root_node, literal_mapping_registry)
      end
    end

  private

    ALLOWED_STYLE = [:rpc, :document]
    def check_style(style)
      unless ALLOWED_STYLE.include?(style)
        raise MethodDefinitionError, "unknown style: " + style
      end
    end
  end
end


end
end
