#!/usr/bin/env ruby

require 'soap/rpc/standaloneServer'
require 'soap/header/simplehandler'
require 'authmgr'

class AuthHeaderPortServer < SOAP::RPC::StandaloneServer
  class AuthHeaderService
    def self.create
      new
    end

    def deposit(amt)
      "deposit #{amt} OK"
    end

    def withdrawal(amt)
      "withdrawal #{amt} OK"
    end
  end

  Name = 'http://tempuri.org/authHeaderPort'
  def initialize(*arg)
    super
    add_rpc_servant(AuthHeaderService.new, Name)
    # header handler must be a per request handler.
    add_rpc_request_headerhandler(ServerAuthHeaderHandler)
  end

  class ServerAuthHeaderHandler < SOAP::Header::SimpleHandler
    MyHeaderName = XSD::QName.new("http://tempuri.org/authHeader", "auth")

    @authmgr = Authmgr.new
    def self.create
      new(@authmgr)
    end

    def initialize(authmgr)
      super(MyHeaderName)
      @authmgr = authmgr
      @userid = @sessionid = nil
    end

    def on_simple_outbound
      { "sessionid" => @sessionid }
    end

    def on_simple_inbound(my_header, mu)
      auth = false
      userid = my_header["userid"]
      passwd = my_header["passwd"]
      if @authmgr.login(userid, passwd)
	auth = true
      elsif sessionid = my_header["sessionid"]
	if userid = @authmgr.auth(sessionid)
	  @authmgr.destroy_session(sessionid)
	  auth = true
	end
      end
      raise RuntimeError.new("authentication failed") unless auth
      @userid = userid
      @sessionid = @authmgr.create_session(userid)
    end
  end
end

if $0 == __FILE__
  svr = AuthHeaderPortServer.new('AuthHeaderPortServer', nil, '0.0.0.0', 7000)
  trap(:INT) do
    svr.shutdown
  end
  status = svr.start
end
