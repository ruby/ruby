# SOAP4R - WEBrick Server
# Copyright (C) 2003 by NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'logger'
require 'soap/rpc/soaplet'
require 'soap/streamHandler'

# require 'webrick'
require 'webrick/compat.rb'
require 'webrick/version.rb'
require 'webrick/config.rb'
require 'webrick/log.rb'
require 'webrick/server.rb'
require 'webrick/utils.rb'
require 'webrick/accesslog'
# require 'webrick/htmlutils.rb'
require 'webrick/httputils.rb'
# require 'webrick/cookie.rb'
require 'webrick/httpversion.rb'
require 'webrick/httpstatus.rb'
require 'webrick/httprequest.rb'
require 'webrick/httpresponse.rb'
require 'webrick/httpserver.rb'
# require 'webrick/httpservlet.rb'
# require 'webrick/httpauth.rb'


module SOAP
module RPC


class StandaloneServer < Logger::Application
  attr_reader :server

  def initialize(app_name, namespace, host = "0.0.0.0", port = 8080)
    super(app_name)
    self.level = Logger::Severity::INFO
    @namespace = namespace
    @host = host
    @port = port
    @server = nil
    @soaplet = ::SOAP::RPC::SOAPlet.new
    on_init
  end

  def on_init
    # define extra methods in derived class.
  end

  def status
    if @server
      @server.status
    else
      nil
    end
  end

  def shutdown
    @server.shutdown
  end
  
  def add_rpc_request_servant(klass, namespace = @namespace, mapping_registry = nil)
    @soaplet.add_rpc_request_servant(klass, namespace, mapping_registry)
  end

  def add_rpc_servant(obj, namespace = @namespace)
    @soaplet.add_rpc_servant(obj, namespace)
  end
  alias add_servant add_rpc_servant

  def mapping_registry
    @soaplet.app_scope_router.mapping_registry
  end

  def mapping_registry=(mapping_registry)
    @soaplet.app_scope_router.mapping_registry = mapping_registry
  end

  def add_method(obj, name, *param)
    add_method_as(obj, name, name, *param)
  end

  def add_method_as(obj, name, name_as, *param)
    qname = XSD::QName.new(@namespace, name_as)
    soapaction = nil
    method = obj.method(name)
    param_def = if param.size == 1 and param[0].is_a?(Array)
        param[0]
      elsif param.empty?
	::SOAP::RPC::SOAPMethod.create_param_def(
	  (1..method.arity.abs).collect { |i| "p#{ i }" })
      else
        SOAP::RPC::SOAPMethod.create_param_def(param)
      end
    @soaplet.app_scope_router.add_method(obj, qname, soapaction, name, param_def)
  end

private

  def run
    @server = WEBrick::HTTPServer.new(
      :BindAddress => @host,
      :Logger => @log,
      :AccessLog => [],
      :Port => @port
    )
    @server.mount('/', @soaplet)
    @server.start
  end
end


end
end
