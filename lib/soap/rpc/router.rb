# SOAP4R - RPC Routing library
# Copyright (C) 2001, 2002, 2004, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

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
  attr_accessor :mapping_registry
  attr_accessor :literal_mapping_registry
  attr_accessor :generate_explicit_type
  attr_accessor :external_ces

  def initialize(actor)
    @actor = actor
    @mapping_registry = nil
    @headerhandler = Header::HandlerSet.new
    @literal_mapping_registry = ::SOAP::Mapping::WSDLLiteralRegistry.new
    @generate_explicit_type = true
    @external_ces = nil
    @operation_by_soapaction = {}
    @operation_by_qname = {}
    @headerhandlerfactory = []
  end

  ###
  ## header handler interface
  #
  def add_request_headerhandler(factory)
    unless factory.respond_to?(:create)
      raise TypeError.new("factory must respond to 'create'")
    end
    @headerhandlerfactory << factory
  end

  def add_headerhandler(handler)
    @headerhandler.add(handler)
  end

  ###
  ## servant definition interface
  #
  def add_rpc_request_servant(factory, namespace)
    unless factory.respond_to?(:create)
      raise TypeError.new("factory must respond to 'create'")
    end
    obj = factory.create        # a dummy instance for introspection
    ::SOAP::RPC.defined_methods(obj).each do |name|
      begin
        qname = XSD::QName.new(namespace, name)
        param_def = ::SOAP::RPC::SOAPMethod.derive_rpc_param_def(obj, name)
        opt = create_styleuse_option(:rpc, :encoded)
        add_rpc_request_operation(factory, qname, nil, name, param_def, opt)
      rescue SOAP::RPC::MethodDefinitionError => e
        p e if $DEBUG
      end
    end
  end

  def add_rpc_servant(obj, namespace)
    ::SOAP::RPC.defined_methods(obj).each do |name|
      begin
        qname = XSD::QName.new(namespace, name)
        param_def = ::SOAP::RPC::SOAPMethod.derive_rpc_param_def(obj, name)
        opt = create_styleuse_option(:rpc, :encoded)
        add_rpc_operation(obj, qname, nil, name, param_def, opt)
      rescue SOAP::RPC::MethodDefinitionError => e
        p e if $DEBUG
      end
    end
  end
  alias add_servant add_rpc_servant

  ###
  ## operation definition interface
  #
  def add_rpc_operation(receiver, qname, soapaction, name, param_def, opt = {})
    ensure_styleuse_option(opt, :rpc, :encoded)
    opt[:request_qname] = qname
    op = ApplicationScopeOperation.new(soapaction, receiver, name, param_def,
      opt)
    if opt[:request_style] != :rpc
      raise RPCRoutingError.new("illegal request_style given")
    end
    assign_operation(soapaction, qname, op)
  end
  alias add_method add_rpc_operation
  alias add_rpc_method add_rpc_operation

  def add_rpc_request_operation(factory, qname, soapaction, name, param_def, opt = {})
    ensure_styleuse_option(opt, :rpc, :encoded)
    opt[:request_qname] = qname
    op = RequestScopeOperation.new(soapaction, factory, name, param_def, opt)
    if opt[:request_style] != :rpc
      raise RPCRoutingError.new("illegal request_style given")
    end
    assign_operation(soapaction, qname, op)
  end

  def add_document_operation(receiver, soapaction, name, param_def, opt = {})
    #
    # adopt workaround for doc/lit wrapper method
    # (you should consider to simply use rpc/lit service)
    #
    #unless soapaction
    #  raise RPCRoutingError.new("soapaction is a must for document method")
    #end
    ensure_styleuse_option(opt, :document, :literal)
    op = ApplicationScopeOperation.new(soapaction, receiver, name, param_def,
      opt)
    if opt[:request_style] != :document
      raise RPCRoutingError.new("illegal request_style given")
    end
    assign_operation(soapaction, first_input_part_qname(param_def), op)
  end
  alias add_document_method add_document_operation

  def add_document_request_operation(factory, soapaction, name, param_def, opt = {})
    #
    # adopt workaround for doc/lit wrapper method
    # (you should consider to simply use rpc/lit service)
    #
    #unless soapaction
    #  raise RPCRoutingError.new("soapaction is a must for document method")
    #end
    ensure_styleuse_option(opt, :document, :literal)
    op = RequestScopeOperation.new(soapaction, receiver, name, param_def, opt)
    if opt[:request_style] != :document
      raise RPCRoutingError.new("illegal request_style given")
    end
    assign_operation(soapaction, first_input_part_qname(param_def), op)
  end

  def route(conn_data)
    # we cannot set request_default_encodingsyle before parsing the content.
    env = unmarshal(conn_data)
    if env.nil?
      raise ArgumentError.new("illegal SOAP marshal format")
    end
    op = lookup_operation(conn_data.soapaction, env.body)
    headerhandler = @headerhandler.dup
    @headerhandlerfactory.each do |f|
      headerhandler.add(f.create)
    end
    receive_headers(headerhandler, env.header)
    soap_response = default_encodingstyle = nil
    begin
      soap_response =
        op.call(env.body, @mapping_registry, @literal_mapping_registry,
          create_mapping_opt)
      default_encodingstyle = op.response_default_encodingstyle
    rescue Exception
      soap_response = fault($!)
      default_encodingstyle = nil
    end
    conn_data.is_fault = true if soap_response.is_a?(SOAPFault)
    header = call_headers(headerhandler)
    body = SOAPBody.new(soap_response)
    env = SOAPEnvelope.new(header, body)
    marshal(conn_data, env, default_encodingstyle)
  end

  # Create fault response string.
  def create_fault_response(e)
    env = SOAPEnvelope.new(SOAPHeader.new, SOAPBody.new(fault(e)))
    opt = {}
    opt[:external_content] = nil
    response_string = Processor.marshal(env, opt)
    conn_data = StreamHandler::ConnectionData.new(response_string)
    conn_data.is_fault = true
    if ext = opt[:external_content]
      mimeize(conn_data, ext)
    end
    conn_data
  end

private

  def first_input_part_qname(param_def)
    param_def.each do |inout, paramname, typeinfo|
      if inout == SOAPMethod::IN
        klass, nsdef, namedef = typeinfo
        return XSD::QName.new(nsdef, namedef)
      end
    end
    nil
  end

  def create_styleuse_option(style, use)
    opt = {}
    opt[:request_style] = opt[:response_style] = style
    opt[:request_use] = opt[:response_use] = use
    opt
  end

  def ensure_styleuse_option(opt, style, use)
    opt[:request_style] ||= style
    opt[:response_style] ||= style
    opt[:request_use] ||= use
    opt[:response_use] ||= use
  end

  def assign_operation(soapaction, qname, op)
    assigned = false
    if soapaction and !soapaction.empty?
      @operation_by_soapaction[soapaction] = op
      assigned = true
    end
    if qname
      @operation_by_qname[qname] = op
      assigned = true
    end
    unless assigned
      raise RPCRoutingError.new("cannot assign operation")
    end
  end

  def lookup_operation(soapaction, body)
    if op = @operation_by_soapaction[soapaction]
      return op
    end
    qname = body.root_node.elename
    if op = @operation_by_qname[qname]
      return op
    end
    if soapaction
      raise RPCRoutingError.new(
        "operation: #{soapaction} #{qname} not supported")
    else
      raise RPCRoutingError.new("operation: #{qname} not supported")
    end
  end

  def call_headers(headerhandler)
    headers = headerhandler.on_outbound
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

  def receive_headers(headerhandler, headers)
    headerhandler.on_inbound(headers) if headers
  end

  def unmarshal(conn_data)
    opt = {}
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

  def marshal(conn_data, env, default_encodingstyle = nil)
    opt = {}
    opt[:external_content] = nil
    opt[:default_encodingstyle] = default_encodingstyle
    opt[:generate_explicit_type] = @generate_explicit_type
    response_string = Processor.marshal(env, opt)
    conn_data.send_string = response_string
    if ext = opt[:external_content]
      mimeize(conn_data, ext)
    end
    conn_data
  end

  def mimeize(conn_data, ext)
    mime = MIMEMessage.new
    ext.each do |k, v|
      mime.add_attachment(v.data)
    end
    mime.add_part(conn_data.send_string + "\r\n")
    mime.close
    conn_data.send_string = mime.content_str
    conn_data.send_contenttype = mime.headers['content-type'].str
    conn_data
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

  def create_mapping_opt
    { :external_ces => @external_ces }
  end

  class Operation
    attr_reader :name
    attr_reader :soapaction
    attr_reader :request_style
    attr_reader :response_style
    attr_reader :request_use
    attr_reader :response_use

    def initialize(soapaction, name, param_def, opt)
      @soapaction = soapaction
      @name = name
      @request_style = opt[:request_style]
      @response_style = opt[:response_style]
      @request_use = opt[:request_use]
      @response_use = opt[:response_use]
      check_style(@request_style)
      check_style(@response_style)
      check_use(@request_use)
      check_use(@response_use)
      if @response_style == :rpc
        request_qname = opt[:request_qname] or raise
        @rpc_method_factory =
          RPC::SOAPMethodRequest.new(request_qname, param_def, @soapaction)
        @rpc_response_qname = opt[:response_qname]
      else
        @doc_request_qnames = []
        @doc_request_qualified = []
        @doc_response_qnames = []
        @doc_response_qualified = []
        param_def.each do |inout, paramname, typeinfo, eleinfo|
          klass, nsdef, namedef = typeinfo
          qualified = eleinfo
          case inout
          when SOAPMethod::IN
            @doc_request_qnames << XSD::QName.new(nsdef, namedef)
            @doc_request_qualified << qualified
          when SOAPMethod::OUT
            @doc_response_qnames << XSD::QName.new(nsdef, namedef)
            @doc_response_qualified << qualified
          else
            raise ArgumentError.new(
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

    def call(body, mapping_registry, literal_mapping_registry, opt)
      if @request_style == :rpc
        values = request_rpc(body, mapping_registry, literal_mapping_registry,
          opt)
      else
        values = request_document(body, mapping_registry,
          literal_mapping_registry, opt)
      end
      result = receiver.method(@name.intern).call(*values)
      return result if result.is_a?(SOAPFault)
      if @response_style == :rpc
        response_rpc(result, mapping_registry, literal_mapping_registry, opt)
      else
        response_doc(result, mapping_registry, literal_mapping_registry, opt)
      end
    end

  private

    def receiver
      raise NotImplementedError.new('must be defined in derived class')
    end

    def request_rpc(body, mapping_registry, literal_mapping_registry, opt)
      request = body.request
      unless request.is_a?(SOAPStruct)
        raise RPCRoutingError.new("not an RPC style")
      end
      if @request_use == :encoded
        request_rpc_enc(request, mapping_registry, opt)
      else
        request_rpc_lit(request, literal_mapping_registry, opt)
      end
    end

    def request_document(body, mapping_registry, literal_mapping_registry, opt)
      # ToDo: compare names with @doc_request_qnames
      if @request_use == :encoded
        request_doc_enc(body, mapping_registry, opt)
      else
        request_doc_lit(body, literal_mapping_registry, opt)
      end
    end

    def request_rpc_enc(request, mapping_registry, opt)
      param = Mapping.soap2obj(request, mapping_registry, nil, opt)
      request.collect { |key, value|
        param[key]
      }
    end

    def request_rpc_lit(request, mapping_registry, opt)
      request.collect { |key, value|
        Mapping.soap2obj(value, mapping_registry, nil, opt)
      }
    end

    def request_doc_enc(body, mapping_registry, opt)
      body.collect { |key, value|
        Mapping.soap2obj(value, mapping_registry, nil, opt)
      }
    end

    def request_doc_lit(body, mapping_registry, opt)
      body.collect { |key, value|
        Mapping.soap2obj(value, mapping_registry, nil, opt)
      }
    end

    def response_rpc(result, mapping_registry, literal_mapping_registry, opt)
      if @response_use == :encoded
        response_rpc_enc(result, mapping_registry, opt)
      else
        response_rpc_lit(result, literal_mapping_registry, opt)
      end
    end

    def response_doc(result, mapping_registry, literal_mapping_registry, opt)
      if @doc_response_qnames.size == 1 and !result.is_a?(Array)
        result = [result]
      end
      if result.size != @doc_response_qnames.size
        raise "required #{@doc_response_qnames.size} responses " +
          "but #{result.size} given"
      end
      if @response_use == :encoded
        response_doc_enc(result, mapping_registry, opt)
      else
        response_doc_lit(result, literal_mapping_registry, opt)
      end
    end

    def response_rpc_enc(result, mapping_registry, opt)
      soap_response =
        @rpc_method_factory.create_method_response(@rpc_response_qname)
      if soap_response.have_outparam?
        unless result.is_a?(Array)
          raise RPCRoutingError.new("out parameter was not returned")
        end
        outparams = {}
        i = 1
        soap_response.output_params.each do |outparam|
          outparams[outparam] = Mapping.obj2soap(result[i], mapping_registry,
            nil, opt)
          i += 1
        end
        soap_response.set_outparam(outparams)
        soap_response.retval = Mapping.obj2soap(result[0], mapping_registry,
          nil, opt)
      else
        soap_response.retval = Mapping.obj2soap(result, mapping_registry, nil,
          opt)
      end
      soap_response
    end

    def response_rpc_lit(result, mapping_registry, opt)
      soap_response =
        @rpc_method_factory.create_method_response(@rpc_response_qname)
      if soap_response.have_outparam?
        unless result.is_a?(Array)
          raise RPCRoutingError.new("out parameter was not returned")
        end
        outparams = {}
        i = 1
        soap_response.output_params.each do |outparam|
          outparams[outparam] = Mapping.obj2soap(result[i], mapping_registry,
            XSD::QName.new(nil, outparam), opt)
          i += 1
        end
        soap_response.set_outparam(outparams)
        soap_response.retval = Mapping.obj2soap(result[0], mapping_registry,
          XSD::QName.new(nil, soap_response.elename), opt)
      else
        soap_response.retval = Mapping.obj2soap(result, mapping_registry,
          XSD::QName.new(nil, soap_response.elename), opt)
      end
      soap_response
    end

    def response_doc_enc(result, mapping_registry, opt)
      (0...result.size).collect { |idx|
        ele = Mapping.obj2soap(result[idx], mapping_registry, nil, opt)
        ele.elename = @doc_response_qnames[idx]
        ele
      }
    end

    def response_doc_lit(result, mapping_registry, opt)
      (0...result.size).collect { |idx|
        ele = Mapping.obj2soap(result[idx], mapping_registry,
          @doc_response_qnames[idx])
        ele.encodingstyle = LiteralNamespace
        if ele.respond_to?(:qualified)
          ele.qualified = @doc_response_qualified[idx]
        end
        ele
      }
    end

    def check_style(style)
      unless [:rpc, :document].include?(style)
        raise ArgumentError.new("unknown style: #{style}")
      end
    end

    def check_use(use)
      unless [:encoded, :literal].include?(use)
        raise ArgumentError.new("unknown use: #{use}")
      end
    end
  end

  class ApplicationScopeOperation < Operation
    def initialize(soapaction, receiver, name, param_def, opt)
      super(soapaction, name, param_def, opt)
      @receiver = receiver
    end

  private

    def receiver
      @receiver
    end
  end

  class RequestScopeOperation < Operation
    def initialize(soapaction, receiver_factory, name, param_def, opt)
      super(soapaction, name, param_def, opt)
      unless receiver_factory.respond_to?(:create)
        raise TypeError.new("factory must respond to 'create'")
      end
      @receiver_factory = receiver_factory
    end

  private

    def receiver
      @receiver_factory.create
    end
  end
end


end
end
