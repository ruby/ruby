#!/usr/bin/env ruby

require 'soap/rpc/standaloneServer'
require 'soap/header/simplehandler'
require 'authmgr'

class AuthHeaderPortServer < SOAP::RPC::StandaloneServer
  class AuthHeaderService
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
    authmgr = Authmgr.new
    add_rpc_servant(AuthHeaderService.new(authmgr), Name)
    ServerAuthHeaderHandler.init(authmgr)
    # header handler must be a per request handler.
    add_rpc_request_headerhandler(ServerAuthHeaderHandler)
  end

  class ServerAuthHeaderHandler < SOAP::Header::SimpleHandler
    MyHeaderName = XSD::QName.new("http://tempuri.org/authHeader", "auth")

    def self.init(authmgr)
      @authmgr = authmgr
    end

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
          @sessionid = @authmgr.create_session(userid)
	  auth = true
	end
      end
      raise RuntimeError.new("authentication failed") unless auth
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
