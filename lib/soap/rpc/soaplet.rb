# SOAP4R - SOAP handler servlet for WEBrick
# Copyright (C) 2001, 2002, 2003, 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'webrick/httpservlet/abstract'
require 'webrick/httpstatus'
require 'soap/rpc/router'
require 'soap/streamHandler'

module SOAP
module RPC


class SOAPlet < WEBrick::HTTPServlet::AbstractServlet
public
  attr_reader :app_scope_router

  def initialize
    @router_map = {}
    @app_scope_router = ::SOAP::RPC::Router.new(self.class.name)
    @headerhandlerfactory = []
    @app_scope_headerhandler = nil
  end

  # Add servant factory whose object has request scope.  A servant object is
  # instanciated for each request.
  #
  # Bear in mind that servant factories are distinguished by HTTP SOAPAction
  # header in request.  Client which calls request-scoped servant must have a
  # SOAPAction header which is a namespace of the servant factory.
  # I mean, use Driver#add_method_with_soapaction instead of Driver#add_method
  # at client side.
  #
  # A factory must respond to :create.
  #
  def add_rpc_request_servant(factory, namespace, mapping_registry = nil)
    unless factory.respond_to?(:create)
      raise TypeError.new("factory must respond to 'create'")
    end
    router = setup_request_router(namespace)
    router.factory = factory
    router.mapping_registry = mapping_registry
  end

  # Add servant object which has application scope.
  def add_rpc_servant(obj, namespace)
    router = @app_scope_router
    SOAPlet.add_servant_to_router(router, obj, namespace)
    add_router(namespace, router)
  end
  alias add_servant add_rpc_servant

  def add_rpc_request_headerhandler(factory)
    unless factory.respond_to?(:create)
      raise TypeError.new("factory must respond to 'create'")
    end
    @headerhandlerfactory << factory
  end

  def add_rpc_headerhandler(obj)
    @app_scope_headerhandler = obj
  end
  alias add_headerhandler add_rpc_headerhandler

  ###
  ## Servlet interfaces for WEBrick.
  #
  def get_instance(config, *options)
    @config = config
    self
  end

  def require_path_info?
    false
  end

  def do_GET(req, res)
    res.header['Allow'] = 'POST'
    raise WEBrick::HTTPStatus::MethodNotAllowed, "GET request not allowed."
  end

  def do_POST(req, res)
    namespace = parse_soapaction(req.meta_vars['HTTP_SOAPACTION'])
    router = lookup_router(namespace)
    with_headerhandler(router) do |router|
      begin
	conn_data = ::SOAP::StreamHandler::ConnectionData.new
	conn_data.receive_string = req.body
	conn_data.receive_contenttype = req['content-type']
	conn_data = router.route(conn_data)
	if conn_data.is_fault
	  res.status = WEBrick::HTTPStatus::RC_INTERNAL_SERVER_ERROR
	end
	res.body = conn_data.send_string
	res['content-type'] = conn_data.send_contenttype
      rescue Exception => e
	conn_data = router.create_fault_response(e)
	res.status = WEBrick::HTTPStatus::RC_INTERNAL_SERVER_ERROR
	res.body = conn_data.send_string
	res['content-type'] = conn_data.send_contenttype || "text/xml"
      end
    end

    if res.body.is_a?(IO)
      res.chunked = true
    end
  end

private

  class RequestRouter < ::SOAP::RPC::Router
    attr_accessor :factory

    def initialize(namespace = nil)
      super(namespace)
      @namespace = namespace
      @factory = nil
    end

    def route(soap_string)
      obj = @factory.create
      namespace = self.actor
      router = ::SOAP::RPC::Router.new(@namespace)
      SOAPlet.add_servant_to_router(router, obj, namespace)
      router.route(soap_string)
    end
  end

  def setup_request_router(namespace)
    router = @router_map[namespace] || RequestRouter.new(namespace)
    add_router(namespace, router)
    router
  end

  def add_router(namespace, router)
    @router_map[namespace] = router
  end

  def parse_soapaction(soapaction)
    if /^"(.*)"$/ =~ soapaction
      soapaction = $1
    end
    if soapaction.empty?
      return nil
    end
    soapaction
  end

  def lookup_router(namespace)
    if namespace
      @router_map[namespace] || @app_scope_router
    else
      @app_scope_router
    end
  end

  def with_headerhandler(router)
    if @app_scope_headerhandler and
	!router.headerhandler.include?(@app_scope_headerhandler)
      router.headerhandler.add(@app_scope_headerhandler)
    end
    handlers = @headerhandlerfactory.collect { |f| f.create }
    begin
      handlers.each { |h| router.headerhandler.add(h) }
      yield(router)
    ensure
      handlers.each { |h| router.headerhandler.delete(h) }
    end
  end

  class << self
  public
    def add_servant_to_router(router, obj, namespace)
      ::SOAP::RPC.defined_methods(obj).each do |name|
        begin
          add_servant_method_to_router(router, obj, namespace, name)
        rescue SOAP::RPC::MethodDefinitionError => e
          p e if $DEBUG
        end
      end
    end

    def add_servant_method_to_router(router, obj, namespace, name)
      qname = XSD::QName.new(namespace, name)
      soapaction = nil
      method = obj.method(name)
      param_def = ::SOAP::RPC::SOAPMethod.create_param_def(
	(1..method.arity.abs).collect { |i| "p#{ i }" })
      router.add_method(obj, qname, soapaction, name, param_def)
    end
  end
end


end
end
