require 'pstore'
require 'soap/rpc/cgistub'
require 'soap/header/simplehandler'


class AuthHeaderPortServer < SOAP::RPC::CGIStub
  PortName = 'http://tempuri.org/authHeaderPort'
  SupportPortName = 'http://tempuri.org/authHeaderSupportPort'
  MyHeaderName = XSD::QName.new("http://tempuri.org/authHeader", "auth")
  SessionDB = File.join(File.expand_path(File.dirname(__FILE__)), 'session.pstoredb')

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

  class AuthHeaderSupportService
    def delete_sessiondb
      File.unlink(SessionDB) if File.file?(SessionDB)
      backup = SessionDB + "~"
      File.unlink(backup) if File.file?(backup)
    end
  end

  def initialize(*arg)
    super
    add_rpc_servant(AuthHeaderService.new, PortName)
    add_rpc_servant(AuthHeaderSupportService.new, SupportPortName)
    add_rpc_headerhandler(ServerAuthHeaderHandler.new)
  end

  class ServerAuthHeaderHandler < SOAP::Header::SimpleHandler
    Users = {
      'NaHi' => 'passwd',
      'HiNa' => 'wspass'
    }

    def initialize
      super(MyHeaderName)
      @db = PStore.new(SessionDB)
      @db.transaction do
	@db["root"] = {} unless @db.root?("root")
      end
      @userid = @sessionid = nil
    end

    def login(userid, passwd)
      userid and passwd and Users[userid] == passwd
    end

    def auth(sessionid)
      in_sessiondb do |root|
	root[sessionid][0]
      end
    end

    def create_session(userid)
      in_sessiondb do |root|
	while true
  	  key = create_sessionkey
  	  break unless root[key]
   	end
    	root[key] = [userid]
     	key
      end
    end

    def destroy_session(sessionkey)
      in_sessiondb do |root|
	root.delete(sessionkey)
      end
    end

    def on_simple_outbound
      { "sessionid" => @sessionid }
    end

    def on_simple_inbound(my_header, mu)
      auth = false
      userid = my_header["userid"]
      passwd = my_header["passwd"]
      if login(userid, passwd)
	auth = true
      elsif sessionid = my_header["sessionid"]
	if userid = auth(sessionid)
	  destroy_session(sessionid)
	  auth = true
	end
      end
      raise RuntimeError.new("authentication failed") unless auth
      @userid = userid
      @sessionid = create_session(userid)
    end

  private

    def create_sessionkey
      Time.now.usec.to_s
    end

    def in_sessiondb
      @db.transaction do
	yield(@db["root"])
      end
    end
  end
end


status = AuthHeaderPortServer.new('AuthHeaderPortServer', nil).start
