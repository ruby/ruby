# SOAP4R - CGI stub library
# Copyright (C) 2001, 2003, 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/streamHandler'
require 'webrick/httpresponse'
require 'webrick/httpstatus'
require 'logger'
require 'soap/rpc/router'


module SOAP
module RPC


###
# SYNOPSIS
#   CGIStub.new
#
# DESCRIPTION
#   To be written...
#
class CGIStub < Logger::Application
  include SOAP

  # There is a client which does not accept the media-type which is defined in
  # SOAP spec.
  attr_accessor :mediatype

  class CGIError < Error; end

  class SOAPRequest
    ALLOWED_LENGTH = 1024 * 1024

    def initialize(stream = $stdin)
      @method = ENV['REQUEST_METHOD']
      @size = ENV['CONTENT_LENGTH'].to_i || 0
      @contenttype = ENV['CONTENT_TYPE']
      @soapaction = ENV['HTTP_SOAPAction']
      @source = stream
      @body = nil
    end

    def init
      validate
      @body = @source.read(@size)
      self
    end

    def dump
      @body.dup
    end

    def soapaction
      @soapaction
    end

    def contenttype
      @contenttype
    end

    def to_s
      "method: #{ @method }, size: #{ @size }"
    end

  private

    def validate # raise CGIError
      if @method != 'POST'
	raise CGIError.new("Method '#{ @method }' not allowed.")
      end

      if @size > ALLOWED_LENGTH
        raise CGIError.new("Content-length too long.")
      end
    end
  end

  def initialize(appname, default_namespace)
    super(appname)
    set_log(STDERR)
    self.level = ERROR
    @default_namespace = default_namespace
    @router = SOAP::RPC::Router.new(appname)
    @remote_user = ENV['REMOTE_USER'] || 'anonymous'
    @remote_host = ENV['REMOTE_HOST'] || ENV['REMOTE_ADDR'] || 'unknown'
    @request = nil
    @response = nil
    @mediatype = MediaType
    on_init
  end
  
  def add_rpc_servant(obj, namespace = @default_namespace, soapaction = nil)
    RPC.defined_methods(obj).each do |name|
      qname = XSD::QName.new(namespace, name)
      param_size = obj.method(name).arity.abs
      params = (1..param_size).collect { |i| "p#{i}" }
      param_def = SOAP::RPC::SOAPMethod.create_param_def(params)
      @router.add_method(obj, qname, soapaction, name, param_def)
    end
  end
  alias add_servant add_rpc_servant

  def add_rpc_headerhandler(obj)
    @router.headerhandler << obj
  end
  alias add_headerhandler add_rpc_headerhandler

  def on_init
    # Override this method in derived class to call 'add_method' to add methods.
  end

  def mapping_registry
    @router.mapping_registry
  end

  def mapping_registry=(value)
    @router.mapping_registry = value
  end

  def add_method(receiver, name, *param)
    add_method_with_namespace_as(@default_namespace, receiver,
      name, name, *param)
  end

  def add_method_as(receiver, name, name_as, *param)
    add_method_with_namespace_as(@default_namespace, receiver,
      name, name_as, *param)
  end

  def add_method_with_namespace(namespace, receiver, name, *param)
    add_method_with_namespace_as(namespace, receiver, name, name, *param)
  end

  def add_method_with_namespace_as(namespace, receiver, name, name_as, *param)
    param_def = if param.size == 1 and param[0].is_a?(Array)
        param[0]
      else
        SOAP::RPC::SOAPMethod.create_param_def(param)
      end
    qname = XSD::QName.new(namespace, name_as)
    @router.add_method(receiver, qname, nil, name, param_def)
  end

  def route(conn_data)
    @router.route(conn_data)
  end

  def create_fault_response(e)
    @router.create_fault_response(e)
  end

private
  
  def run
    prologue

    httpversion = WEBrick::HTTPVersion.new('1.0')
    @response = WEBrick::HTTPResponse.new({:HTTPVersion => httpversion})
    conn_data = nil
    begin
      @log.info { "Received a request from '#{ @remote_user }@#{ @remote_host }'." }
      # SOAP request parsing.
      @request = SOAPRequest.new.init
      @response['Status'] = 200
      conn_data = ::SOAP::StreamHandler::ConnectionData.new
      conn_data.receive_string = @request.dump
      conn_data.receive_contenttype = @request.contenttype
      @log.debug { "XML Request: #{conn_data.receive_string}" }
      conn_data = route(conn_data)
      @log.debug { "XML Response: #{conn_data.send_string}" }
      if conn_data.is_fault
	@response['Status'] = 500
      end
      @response['Cache-Control'] = 'private'
      @response.body = conn_data.send_string
      @response['content-type'] = conn_data.send_contenttype
    rescue Exception
      conn_data = create_fault_response($!)
      @response['Cache-Control'] = 'private'
      @response['Status'] = 500
      @response.body = conn_data.send_string
      @response['content-type'] = conn_data.send_contenttype || @mediatype
    ensure
      buf = ''
      @response.send_response(buf)
      buf.sub!(/^[^\r]+\r\n/, '')       # Trim status line.
      @log.debug { "SOAP CGI Response:\n#{ buf }" }
      print buf
      epilogue
    end

    0
  end

  def prologue; end
  def epilogue; end
end


end
end
