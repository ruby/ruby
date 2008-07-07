# SOAP4R - SOAP handler servlet for WEBrick
# Copyright (C) 2001-2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'webrick/httpservlet/abstract'
require 'webrick/httpstatus'
require 'soap/rpc/router'
require 'soap/streamHandler'
begin
  require 'stringio'
  require 'zlib'
rescue LoadError
  warn("Loading stringio or zlib failed.  No gzipped response supported.") if $DEBUG
end


warn("Overriding WEBrick::Log#debug") if $DEBUG
require 'webrick/log'
module WEBrick
  class Log < BasicLog
    alias __debug debug
    def debug(msg = nil)
      if block_given? and msg.nil?
        __debug(yield)
      else
        __debug(msg)
      end
    end
  end
end


module SOAP
module RPC


class SOAPlet < WEBrick::HTTPServlet::AbstractServlet
public
  attr_reader :options

  def initialize(router = nil)
    @router = router || ::SOAP::RPC::Router.new(self.class.name)
    @options = {}
    @config = {}
  end

  # for backward compatibility
  def app_scope_router
    @router
  end

  # for backward compatibility
  def add_servant(obj, namespace)
    @router.add_rpc_servant(obj, namespace)
  end

  def allow_content_encoding_gzip=(allow)
    @options[:allow_content_encoding_gzip] = allow
  end

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
    raise WEBrick::HTTPStatus::MethodNotAllowed, "GET request not allowed"
  end

  def do_POST(req, res)
    logger.debug { "SOAP request: " + req.body } if logger
    begin
      conn_data = ::SOAP::StreamHandler::ConnectionData.new
      setup_req(conn_data, req)
      @router.external_ces = @options[:external_ces]
      conn_data = @router.route(conn_data)
      setup_res(conn_data, req, res)
    rescue Exception => e
      conn_data = @router.create_fault_response(e)
      res.status = WEBrick::HTTPStatus::RC_INTERNAL_SERVER_ERROR
      res.body = conn_data.send_string
      res['content-type'] = conn_data.send_contenttype || "text/xml"
    end
    if res.body.is_a?(IO)
      res.chunked = true
      logger.debug { "SOAP response: (chunked response not logged)" } if logger
    else
      logger.debug { "SOAP response: " + res.body } if logger
    end
  end

private

  def logger
    @config[:Logger]
  end

  def setup_req(conn_data, req)
    conn_data.receive_string = req.body
    conn_data.receive_contenttype = req['content-type']
    conn_data.soapaction = parse_soapaction(req.meta_vars['HTTP_SOAPACTION'])
  end

  def setup_res(conn_data, req, res)
    res['content-type'] = conn_data.send_contenttype
    if conn_data.is_fault
      res.status = WEBrick::HTTPStatus::RC_INTERNAL_SERVER_ERROR
    end
    if outstring = encode_gzip(req, conn_data.send_string)
      res['content-encoding'] = 'gzip'
      res['content-length'] = outstring.size
      res.body = outstring
    else
      res.body = conn_data.send_string
    end
  end

  def parse_soapaction(soapaction)
    if !soapaction.nil? and !soapaction.empty?
      if /^"(.+)"$/ =~ soapaction
        return $1
      end
    end
    nil
  end

  def encode_gzip(req, outstring)
    unless encode_gzip?(req)
      return nil
    end
    begin
      ostream = StringIO.new
      gz = Zlib::GzipWriter.new(ostream)
      gz.write(outstring)
      ostream.string
    ensure
      gz.close
    end
  end

  def encode_gzip?(req)
    @options[:allow_content_encoding_gzip] and defined?(::Zlib) and
      req['accept-encoding'] and
      req['accept-encoding'].split(/,\s*/).include?('gzip')
  end
end


end
end
