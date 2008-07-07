# SOAP4R - WEBrick Server
# Copyright (C) 2003 by NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/rpc/httpserver'


module SOAP
module RPC


class StandaloneServer < HTTPServer
  def initialize(appname, default_namespace, host = "0.0.0.0", port = 8080)
    @appname = appname
    @default_namespace = default_namespace
    @host = host
    @port = port
    super(create_config)
  end

  alias add_servant add_rpc_servant
  alias add_headerhandler add_rpc_headerhandler

private

  def create_config
    {
      :BindAddress => @host,
      :Port => @port,
      :AccessLog => [],
      :SOAPDefaultNamespace => @default_namespace,
      :SOAPHTTPServerApplicationName => @appname,
    }
  end
end


end
end
