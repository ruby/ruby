require 'test/unit'
require 'soap/rpc/driver'
require 'soap/rpc/standaloneServer'
require 'soap/header/simplehandler'
require 'logger'
require 'webrick'
require 'rbconfig'


module SOAP
module Header


class TestAuthHeaderCGI < Test::Unit::TestCase
  # This test shuld be run after installing ruby.
  RUBYBIN = File.join(
    Config::CONFIG["bindir"],
    Config::CONFIG["ruby_install_name"] + Config::CONFIG["EXEEXT"]
  )
  RUBYBIN << " -d" if $DEBUG
  
  Port = 17171
  PortName = 'http://tempuri.org/authHeaderPort'
  SupportPortName = 'http://tempuri.org/authHeaderSupportPort'
  MyHeaderName = XSD::QName.new("http://tempuri.org/authHeader", "auth")

  class ClientAuthHeaderHandler < SOAP::Header::SimpleHandler
    def initialize(userid, passwd)
      super(MyHeaderName)
      @sessionid = nil
      @userid = userid
      @passwd = passwd
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

  def setup
    @endpoint = "http://localhost:#{Port}/"
    setup_server
    setup_client
  end

  def setup_server
    @endpoint = "http://localhost:#{Port}/server.cgi"
    logger = Logger.new(STDERR)
    logger.level = Logger::Severity::ERROR
    @server = WEBrick::HTTPServer.new(
      :BindAddress => "0.0.0.0",
      :Logger => logger,
      :Port => Port,
      :AccessLog => [],
      :DocumentRoot => File.dirname(File.expand_path(__FILE__)),
      :CGIPathEnv => ENV['PATH'],
      :CGIInterpreter => RUBYBIN
    )
    @t = Thread.new {
      Thread.current.abort_on_exception = true
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
    @supportclient = SOAP::RPC::Driver.new(@endpoint, SupportPortName)
    @supportclient.add_method('delete_sessiondb')
  end

  def teardown
    @supportclient.delete_sessiondb
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
    @supportclient.reset_stream
  end

  def test_success
    h = ClientAuthHeaderHandler.new('NaHi', 'passwd')
    @client.headerhandler << h
    assert_equal("deposit 150 OK", @client.deposit(150))
    assert_equal("withdrawal 120 OK", @client.withdrawal(120))
  end

  def test_authfailure
    h = ClientAuthHeaderHandler.new('NaHi', 'pa')
    @client.headerhandler << h
    assert_raises(RuntimeError) do
      @client.deposit(150)
    end
  end
end


end
end
