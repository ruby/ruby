require 'test/unit'
require 'soap/rpc/driver'
require 'soap/rpc/standaloneServer'
require 'soap/header/simplehandler'


module SOAP
module Header


class TestAuthHeader < Test::Unit::TestCase
  Port = 17171
  PortName = 'http://tempuri.org/authHeaderPort'
  MyHeaderName = XSD::QName.new("http://tempuri.org/authHeader", "auth")
  DummyHeaderName = XSD::QName.new("http://tempuri.org/authHeader", "dummy")

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

    def initialize(*arg)
      super
      add_rpc_servant(AuthHeaderService.new, PortName)
      ServerAuthHeaderHandler.init
      add_rpc_request_headerhandler(ServerAuthHeaderHandler)
    end

    class ServerAuthHeaderHandler < SOAP::Header::SimpleHandler
      class << self
	def create
	  new
	end

	def init
	  @users = {
	    'NaHi' => 'passwd',
	    'HiNa' => 'wspass'
	  }
	  @sessions = {}
	end

	def login(userid, passwd)
	  userid and passwd and @users[userid] == passwd
	end

	def auth(sessionid)
	  @sessions[sessionid][0]
	end

	def create_session(userid)
	  while true
	    key = create_sessionkey
	    break unless @sessions[key]
	  end
	  @sessions[key] = [userid]
	  key
	end

	def destroy_session(sessionkey)
	  @sessions.delete(sessionkey)
	end

	def sessions
	  @sessions
	end

      private

	def create_sessionkey
	  Time.now.usec.to_s
	end
      end

      def initialize
	super(MyHeaderName)
	@userid = @sessionid = nil
      end

      def on_simple_outbound
	{ "sessionid" => @sessionid }
      end

      def on_simple_inbound(my_header, mu)
	auth = false
	userid = my_header["userid"]
	passwd = my_header["passwd"]
	if self.class.login(userid, passwd)
	  auth = true
	elsif sessionid = my_header["sessionid"]
	  if userid = self.class.auth(sessionid)
	    self.class.destroy_session(sessionid)
	    auth = true
	  end
	end
	raise RuntimeError.new("authentication failed") unless auth
	@userid = userid
	@sessionid = self.class.create_session(userid)
      end
    end
  end

  class ClientAuthHeaderHandler < SOAP::Header::SimpleHandler
    def initialize(userid, passwd, mustunderstand)
      super(MyHeaderName)
      @sessionid = nil
      @userid = userid
      @passwd = passwd
      @mustunderstand = mustunderstand
    end

    def on_simple_outbound
      if @sessionid
	{ "sessionid" => @sessionid }
      else
	{ "userid" => @userid, "passwd" => @passwd }
      end
    end

    def on_simple_inbound(my_header, mustunderstand)
      @sessionid = my_header["sessionid"]
    end

    def sessionid
      @sessionid
    end
  end

  class DummyHeaderHandler < SOAP::Header::SimpleHandler
    def initialize(mustunderstand)
      super(DummyHeaderName)
      @mustunderstand = mustunderstand
    end

    def on_simple_outbound
      { XSD::QName.new("foo", "bar") => nil }
    end

    def on_simple_inbound(my_header, mustunderstand)
    end
  end

  def setup
    @endpoint = "http://localhost:#{Port}/"
    setup_server
    setup_client
  end

  def setup_server
    @server = AuthHeaderPortServer.new(self.class.name, nil, '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @t = Thread.new {
      @server.start
    }
    while @server.status != :Running
      sleep 0.1
      unless @t.alive?
	@t.join
	raise
      end
    end
  end

  def setup_client
    @client = SOAP::RPC::Driver.new(@endpoint, PortName)
    @client.wiredump_dev = STDERR if $DEBUG
    @client.add_method('deposit', 'amt')
    @client.add_method('withdrawal', 'amt')
  end

  def teardown
    teardown_server
    teardown_client
  end

  def teardown_server
    @server.shutdown
    @t.kill
    @t.join
  end

  def teardown_client
    @client.reset_stream
  end

  def test_success_no_mu
    h = ClientAuthHeaderHandler.new('NaHi', 'passwd', false)
    @client.headerhandler << h
    do_transaction_check(h)
  end

  def test_success_mu
    h = ClientAuthHeaderHandler.new('NaHi', 'passwd', true)
    @client.headerhandler << h
    do_transaction_check(h)
  end

  def test_no_mu
    h = ClientAuthHeaderHandler.new('NaHi', 'passwd', true)
    @client.headerhandler << h
    @client.headerhandler << DummyHeaderHandler.new(false)
    do_transaction_check(h)
  end

  def test_mu
    h = ClientAuthHeaderHandler.new('NaHi', 'passwd', true)
    @client.headerhandler << h
    @client.headerhandler << (h2 = DummyHeaderHandler.new(true))
    assert_raise(SOAP::UnhandledMustUnderstandHeaderError) do
      assert_equal("deposit 150 OK", @client.deposit(150))
    end
    @client.headerhandler.delete(h2)
    @client.headerhandler << (h2 = DummyHeaderHandler.new(false))
    do_transaction_check(h)
  end

  def do_transaction_check(h)
    assert_equal("deposit 150 OK", @client.deposit(150))
    serversess = AuthHeaderPortServer::ServerAuthHeaderHandler.sessions[h.sessionid]
    assert_equal("NaHi", serversess[0])
    assert_equal("withdrawal 120 OK", @client.withdrawal(120))
    serversess = AuthHeaderPortServer::ServerAuthHeaderHandler.sessions[h.sessionid]
    assert_equal("NaHi", serversess[0])
  end

  def test_authfailure
    h = ClientAuthHeaderHandler.new('NaHi', 'pa', false)
    @client.headerhandler << h
    assert_raises(RuntimeError) do
      @client.deposit(150)
    end
  end
end


end
end
