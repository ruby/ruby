# SOAP4R - SOAP handler servlet for WEBrick
# Copyright (C) 2001, 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

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
  end

  # Add servant klass whose object has request scope.  A servant object is
  # instanciated for each request.
  #
  # Bare in mind that servant klasses are distinguished by HTTP SOAPAction
  # header in request.  Client which calls request-scoped servant must have a
  # SOAPAction header which is a namespace of the servant klass.
  # I mean, use Driver#add_method_with_soapaction instead of Driver#add_method
  # at client side.
  #
  def add_rpc_request_servant(klass, namespace, mapping_registry = nil)
    router = RequestRouter.new(klass, namespace, mapping_registry)
    add_router(namespace, router)
  end

  # Add servant object which has application scope.
  def add_rpc_servant(obj, namespace)
    router = @app_scope_router
    SOAPlet.add_servant_to_router(router, obj, namespace)
    add_router(namespace, router)
  end
  alias add_servant add_rpc_servant


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

    is_fault = false

    charset = ::SOAP::StreamHandler.parse_media_type(req['content-type'])
    begin
      response_stream, is_fault = router.route(req.body, charset)
    rescue Exception => e
      response_stream = router.create_fault_response(e)
      is_fault = true
    end

    res.body = response_stream
    res['content-type'] = "text/xml; charset=\"#{charset}\""
    if response_stream.is_a?(IO)
      res.chunked = true
    end

    if is_fault
      res.status = WEBrick::HTTPStatus::RC_INTERNAL_SERVER_ERROR
    end
  end

private

  class RequestRouter < ::SOAP::RPC::Router
    def initialize(klass, namespace, mapping_registry = nil)
      super(namespace)
      if mapping_registry
	self.mapping_registry = mapping_registry
      end
      @klass = klass
      @namespace = namespace
    end

    def route(soap_string)
      obj = @klass.new
      namespace = self.actor
      router = ::SOAP::RPC::Router.new(@namespace)
      SOAPlet.add_servant_to_router(router, obj, namespace)
      router.route(soap_string)
    end
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

  class << self
  public
    def add_servant_to_router(router, obj, namespace)
      ::SOAP::RPC.defined_methods(obj).each do |name|
	add_servant_method_to_router(router, obj, namespace, name)
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
