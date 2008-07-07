# SOAP4R - RPC Proxy library.
# Copyright (C) 2000, 2003-2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

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

  def add_rpc_operation(qname, soapaction, name, param_def, opt = {})
    opt[:request_qname] = qname
    opt[:request_style] ||= :rpc
    opt[:response_style] ||= :rpc
    opt[:request_use] ||= :encoded
    opt[:response_use] ||= :encoded
    @operation[name] = Operation.new(soapaction, param_def, opt)
  end

  def add_document_operation(soapaction, name, param_def, opt = {})
    opt[:request_style] ||= :document
    opt[:response_style] ||= :document
    opt[:request_use] ||= :literal
    opt[:response_use] ||= :literal
    # default values of these values are unqualified in XML Schema.
    # set true for backward compatibility.
    unless opt.key?(:elementformdefault)
      opt[:elementformdefault] = true
    end
    unless opt.key?(:attributeformdefault)
      opt[:attributeformdefault] = true
    end
    @operation[name] = Operation.new(soapaction, param_def, opt)
  end

  # add_method is for shortcut of typical rpc/encoded method definition.
  alias add_method add_rpc_operation
  alias add_rpc_method add_rpc_operation
  alias add_document_method add_document_operation

  def invoke(req_header, req_body, opt = nil)
    opt ||= create_encoding_opt
    route(req_header, req_body, opt, opt)
  end

  def call(name, *params)
    unless op_info = @operation[name]
      raise MethodDefinitionError, "method: #{name} not defined"
    end
    mapping_opt = create_mapping_opt
    req_header = create_request_header
    req_body = SOAPBody.new(
      op_info.request_body(params, @mapping_registry,
        @literal_mapping_registry, mapping_opt)
    )
    reqopt = create_encoding_opt(
      :soapaction => op_info.soapaction || @soapaction,
      :envelopenamespace => @options["soap.envelope.requestnamespace"],
      :default_encodingstyle =>
        @default_encodingstyle || op_info.request_default_encodingstyle,
      :elementformdefault => op_info.elementformdefault,
      :attributeformdefault => op_info.attributeformdefault
    )
    resopt = create_encoding_opt(
      :envelopenamespace => @options["soap.envelope.responsenamespace"],
      :default_encodingstyle =>
        @default_encodingstyle || op_info.response_default_encodingstyle,
      :elementformdefault => op_info.elementformdefault,
      :attributeformdefault => op_info.attributeformdefault
    )
    env = route(req_header, req_body, reqopt, resopt)
    raise EmptyResponseError unless env
    receive_headers(env.header)
    begin
      check_fault(env.body)
    rescue ::SOAP::FaultError => e
      op_info.raise_fault(e, @mapping_registry, @literal_mapping_registry)
    end
    op_info.response_obj(env.body, @mapping_registry,
      @literal_mapping_registry, mapping_opt)
  end

  def route(req_header, req_body, reqopt, resopt)
    req_env = ::SOAP::SOAPEnvelope.new(req_header, req_body)
    unless reqopt[:envelopenamespace].nil?
      set_envelopenamespace(req_env, reqopt[:envelopenamespace])
    end
    reqopt[:external_content] = nil
    conn_data = marshal(req_env, reqopt)
    if ext = reqopt[:external_content]
      mime = MIMEMessage.new
      ext.each do |k, v|
      	mime.add_attachment(v.data)
      end
      mime.add_part(conn_data.send_string + "\r\n")
      mime.close
      conn_data.send_string = mime.content_str
      conn_data.send_contenttype = mime.headers['content-type'].str
    end
    conn_data = @streamhandler.send(@endpoint_url, conn_data,
      reqopt[:soapaction])
    if conn_data.receive_string.empty?
      return nil
    end
    unmarshal(conn_data, resopt)
  end

  def check_fault(body)
    if body.fault
      raise SOAP::FaultError.new(body.fault)
    end
  end

private

  def set_envelopenamespace(env, namespace)
    env.elename = XSD::QName.new(namespace, env.elename.name)
    if env.header
      env.header.elename = XSD::QName.new(namespace, env.header.elename.name)
    end
    if env.body
      env.body.elename = XSD::QName.new(namespace, env.body.elename.name)
    end
  end

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
    unless env.is_a?(::SOAP::SOAPEnvelope)
      raise ResponseFormatError.new(
        "response is not a SOAP envelope: #{conn_data.receive_string}")
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

  def create_encoding_opt(hash = nil)
    opt = {}
    opt[:default_encodingstyle] = @default_encodingstyle
    opt[:allow_unqualified_element] = @allow_unqualified_element
    opt[:generate_explicit_type] = @generate_explicit_type
    opt[:no_indent] = @options["soap.envelope.no_indent"]
    opt[:use_numeric_character_reference] =
      @options["soap.envelope.use_numeric_character_reference"]
    opt.update(hash) if hash
    opt
  end

  def create_mapping_opt(hash = nil)
    opt = {
      :external_ces => @options["soap.mapping.external_ces"]
    }
    opt.update(hash) if hash
    opt
  end

  class Operation
    attr_reader :soapaction
    attr_reader :request_style
    attr_reader :response_style
    attr_reader :request_use
    attr_reader :response_use
    attr_reader :elementformdefault
    attr_reader :attributeformdefault

    def initialize(soapaction, param_def, opt)
      @soapaction = soapaction
      @request_style = opt[:request_style]
      @response_style = opt[:response_style]
      @request_use = opt[:request_use]
      @response_use = opt[:response_use]
      # set nil(unqualified) by default
      @elementformdefault = opt[:elementformdefault]
      @attributeformdefault = opt[:attributeformdefault]
      check_style(@request_style)
      check_style(@response_style)
      check_use(@request_use)
      check_use(@response_use)
      if @request_style == :rpc
        @rpc_request_qname = opt[:request_qname]
        if @rpc_request_qname.nil?
          raise MethodDefinitionError.new("rpc_request_qname must be given")
        end
        @rpc_method_factory =
          RPC::SOAPMethodRequest.new(@rpc_request_qname, param_def, @soapaction)
      else
        @doc_request_qnames = []
        @doc_request_qualified = []
        @doc_response_qnames = []
        @doc_response_qualified = []
        param_def.each do |inout, paramname, typeinfo, eleinfo|
          klass_not_used, nsdef, namedef = typeinfo
          qualified = eleinfo
          if namedef.nil?
            raise MethodDefinitionError.new("qname must be given")
          end
          case inout
          when SOAPMethod::IN
            @doc_request_qnames << XSD::QName.new(nsdef, namedef)
            @doc_request_qualified << qualified
          when SOAPMethod::OUT
            @doc_response_qnames << XSD::QName.new(nsdef, namedef)
            @doc_response_qualified << qualified
          else
            raise MethodDefinitionError.new(
              "illegal inout definition for document style: #{inout}")
          end
        end
      end
    end

    def request_default_encodingstyle
      (@request_use == :encoded) ? EncodingNamespace : LiteralNamespace
    end

    def response_default_encodingstyle
      (@response_use == :encoded) ? EncodingNamespace : LiteralNamespace
    end

    def request_body(values, mapping_registry, literal_mapping_registry, opt)
      if @request_style == :rpc
        request_rpc(values, mapping_registry, literal_mapping_registry, opt)
      else
        request_doc(values, mapping_registry, literal_mapping_registry, opt)
      end
    end

    def response_obj(body, mapping_registry, literal_mapping_registry, opt)
      if @response_style == :rpc
        response_rpc(body, mapping_registry, literal_mapping_registry, opt)
      else
        response_doc(body, mapping_registry, literal_mapping_registry, opt)
      end
    end

    def raise_fault(e, mapping_registry, literal_mapping_registry)
      if @response_style == :rpc
        Mapping.fault2exception(e, mapping_registry)
      else
        Mapping.fault2exception(e, literal_mapping_registry)
      end
    end

  private

    def check_style(style)
      unless [:rpc, :document].include?(style)
        raise MethodDefinitionError.new("unknown style: #{style}")
      end
    end

    def check_use(use)
      unless [:encoded, :literal].include?(use)
        raise MethodDefinitionError.new("unknown use: #{use}")
      end
    end

    def request_rpc(values, mapping_registry, literal_mapping_registry, opt)
      if @request_use == :encoded
        request_rpc_enc(values, mapping_registry, opt)
      else
        request_rpc_lit(values, literal_mapping_registry, opt)
      end
    end

    def request_doc(values, mapping_registry, literal_mapping_registry, opt)
      if @request_use == :encoded
        request_doc_enc(values, mapping_registry, opt)
      else
        request_doc_lit(values, literal_mapping_registry, opt)
      end
    end

    def request_rpc_enc(values, mapping_registry, opt)
      method = @rpc_method_factory.dup
      names = method.input_params
      obj = create_request_obj(names, values)
      soap = Mapping.obj2soap(obj, mapping_registry, @rpc_request_qname, opt)
      method.set_param(soap)
      method
    end

    def request_rpc_lit(values, mapping_registry, opt)
      method = @rpc_method_factory.dup
      params = {}
      idx = 0
      method.input_params.each do |name|
        params[name] = Mapping.obj2soap(values[idx], mapping_registry, 
          XSD::QName.new(nil, name), opt)
        idx += 1
      end
      method.set_param(params)
      method
    end

    def request_doc_enc(values, mapping_registry, opt)
      (0...values.size).collect { |idx|
        ele = Mapping.obj2soap(values[idx], mapping_registry, nil, opt)
        ele.elename = @doc_request_qnames[idx]
        ele
      }
    end

    def request_doc_lit(values, mapping_registry, opt)
      (0...values.size).collect { |idx|
        ele = Mapping.obj2soap(values[idx], mapping_registry,
          @doc_request_qnames[idx], opt)
        ele.encodingstyle = LiteralNamespace
        if ele.respond_to?(:qualified)
          ele.qualified = @doc_request_qualified[idx]
        end
        ele
      }
    end

    def response_rpc(body, mapping_registry, literal_mapping_registry, opt)
      if @response_use == :encoded
        response_rpc_enc(body, mapping_registry, opt)
      else
        response_rpc_lit(body, literal_mapping_registry, opt)
      end
    end

    def response_doc(body, mapping_registry, literal_mapping_registry, opt)
      if @response_use == :encoded
        return *response_doc_enc(body, mapping_registry, opt)
      else
        return *response_doc_lit(body, literal_mapping_registry, opt)
      end
    end

    def response_rpc_enc(body, mapping_registry, opt)
      ret = nil
      if body.response
        ret = Mapping.soap2obj(body.response, mapping_registry,
          @rpc_method_factory.retval_class_name, opt)
      end
      if body.outparams
        outparams = body.outparams.collect { |outparam|
          Mapping.soap2obj(outparam, mapping_registry, nil, opt)
        }
        [ret].concat(outparams)
      else
        ret
      end
    end

    def response_rpc_lit(body, mapping_registry, opt)
      body.root_node.collect { |key, value|
        Mapping.soap2obj(value, mapping_registry,
          @rpc_method_factory.retval_class_name, opt)
      }
    end

    def response_doc_enc(body, mapping_registry, opt)
      body.collect { |key, value|
        Mapping.soap2obj(value, mapping_registry, nil, opt)
      }
    end

    def response_doc_lit(body, mapping_registry, opt)
      body.collect { |key, value|
        Mapping.soap2obj(value, mapping_registry)
      }
    end

    def create_request_obj(names, params)
      o = Object.new
      idx = 0
      while idx < params.length
        o.instance_variable_set('@' + names[idx], params[idx])
        idx += 1
      end
      o
    end
  end
end


end
end
