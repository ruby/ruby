=begin
SOAP4R - CGI stub library
Copyright (C) 2001, 2003  NAKAMURA, Hiroshi.

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
      @charset = nil
      @soapaction = ENV['HTTP_SOAPAction']
      @source = stream
      @body = nil
    end

    def init
      validate
      @charset = StreamHandler.parse_media_type(@contenttype)
      @body = @source.read(@size)
      self
    end

    def dump
      @body.dup
    end

    def soapaction
      @soapaction
    end

    def charset
      @charset
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
    self.level = INFO
    @default_namespace = default_namespace
    @router = SOAP::RPC::Router.new(appname)
    @remote_user = ENV['REMOTE_USER'] || 'anonymous'
    @remote_host = ENV['REMOTE_HOST'] || ENV['REMOTE_ADDR'] || 'unknown'
    @request = nil
    @response = nil
    @mediatype = MediaType
    on_init
  end
  
  def add_servant(obj, namespace = @default_namespace, soapaction = nil)
    RPC.defined_methods(obj).each do |name|
      qname = XSD::QName.new(namespace, name)
      param_size = obj.method(name).arity.abs
      params = (1..param_size).collect { |i| "p#{ i }" }
      param_def = SOAP::RPC::SOAPMethod.create_param_def(params)
      @router.add_method(obj, qname, soapaction, name, param_def)
    end
  end

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

  def route(request_string, charset)
    @router.route(request_string, charset)
  end

  def create_fault_response(e)
    @router.create_fault_response(e)
  end

private
  
  def run
    prologue

    httpversion = WEBrick::HTTPVersion.new('1.0')
    @response = WEBrick::HTTPResponse.new({:HTTPVersion => httpversion})
    begin
      log(INFO) { "Received a request from '#{ @remote_user }@#{ @remote_host }'." }
      # SOAP request parsing.
      @request = SOAPRequest.new.init
      req_charset = @request.charset
      req_string = @request.dump
      log(DEBUG) { "XML Request: #{req_string}" }
      res_string, is_fault = route(req_string, req_charset)
      log(DEBUG) { "XML Response: #{res_string}" }

      @response['Cache-Control'] = 'private'
      if req_charset
	@response['content-type'] = "#{@mediatype}; charset=\"#{req_charset}\""
      else
	@response['content-type'] = @mediatype
      end
      if is_fault
	@response.status = WEBrick::HTTPStatus::RC_INTERNAL_SERVER_ERROR
      end
      @response.body = res_string
    rescue Exception
      res_string = create_fault_response($!)
      @response['Cache-Control'] = 'private'
      @response['content-type'] = @mediatype
      @response.status = WEBrick::HTTPStatus::RC_INTERNAL_SERVER_ERROR
    ensure
      buf = ''
      @response.send_response(buf)
      buf.sub!(/^[^\r]+\r\n/, '')       # Trim status line.
      log(DEBUG) { "SOAP CGI Response:\n#{ buf }" }
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
