#!/usr/bin/env ruby

require 'soap/rpc/standaloneServer'
require 'soap/header/simplehandler'
require 'authmgr'

class AuthHeaderPortServer < SOAP::RPC::StandaloneServer
  class AuthHeaderService
    def self.create
      new
    end

    def initialize(authmgr)
      @authmgr = authmgr
    end

    def login(userid, passwd)
      if @authmgr.login(userid, passwd)
        @authmgr.create_session(userid)
      else
        raise RuntimeError.new("authentication failed")
      end
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
    ServerAuthHeaderHandler.init
    add_rpc_request_headerhandler(ServerAuthHeaderHandler)
  end

  class ServerAuthHeaderHandler < SOAP::Header::SimpleHandler
    MyHeaderName = XSD::QName.new("http://tempuri.org/authHeader", "auth")

    def self.create
      new(@authmgr)
    end

    def initialize(authmgr)
      super(MyHeaderName)
      @authmgr = authmgr
      @sessionid = nil
    end

    def on_simple_outbound
      if @sessionid
        { "sessionid" => @sessionid }
      end
    end

    def on_simple_inbound(my_header, mu)
      auth = false
      if sessionid = my_header["sessionid"]
	if userid = @authmgr.auth(sessionid)
	  @authmgr.destroy_session(sessionid)
          @session_id = @authmgr.create_session(userid)
	  auth = true
	end
      end
      raise RuntimeError.new("authentication failed") unless auth
    end
  end
end

if $0 == __FILE__
  status = AuthHeaderPortServer.new('AuthHeaderPortServer', nil, '0.0.0.0', 7000).start
end
