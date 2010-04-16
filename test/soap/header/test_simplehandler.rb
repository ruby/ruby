require 'test/unit'
require 'soap/rpc/driver'
require 'soap/rpc/standaloneServer'
require 'soap/header/simplehandler'


module SOAP
module Header


class TestSimpleHandler < Test::Unit::TestCase
  Port = 17171
  PortName = 'http://tempuri.org/authHeaderPort'

  class PingPortServer < SOAP::RPC::StandaloneServer
    class PingService
      def self.create
	new
      end

      def ping
        Thread.current[:pingheader]
      end
    end

    def initialize(*arg)
      super
      add_rpc_servant(PingService.new, PortName)
      add_request_headerhandler(PingServerHeaderHandler)
    end

    class PingServerHeaderHandler < SOAP::Header::SimpleHandler
      MyHeaderName = XSD::QName.new("http://xmlsoap.org/Ping", "PingHeader")

      def self.create
        new
      end

      def initialize()
        super(MyHeaderName)
      end

      def on_simple_outbound
        "dummy"
      end

      def on_simple_inbound(my_header, mu)
        Thread.current[:pingheader] = my_header
      end
    end
  end

  class PingClientHeaderHandler < SOAP::Header::SimpleHandler
    MyHeaderName = XSD::QName.new("http://xmlsoap.org/Ping", "PingHeader")

    def initialize(pingHeader)
      super(MyHeaderName)
      @pingHeader = pingHeader
      @mustunderstand = false
    end

    def on_simple_outbound
      @pingHeader # --- note, not a Hash
    end

    def on_simple_inbound(my_header, mustunderstand)
      Thread.current[:pingheader] = my_header
    end
  end

  def setup
    @endpoint = "http://localhost:#{Port}/"
    setup_server
    setup_client
  end

  def setup_server
    @server = PingPortServer.new(self.class.name, nil, '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @t = Thread.new {
      @server.start
    }
  end

  def setup_client
    @client = SOAP::RPC::Driver.new(@endpoint, PortName)
    @client.wiredump_dev = STDERR if $DEBUG
    @client.add_method('ping')
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

  def test_string
    h = PingClientHeaderHandler.new('pingheader')
    @client.headerhandler << h
    assert_equal("pingheader", @client.ping)
    assert_equal("dummy", Thread.current[:pingheader])
  end
end


end
end
