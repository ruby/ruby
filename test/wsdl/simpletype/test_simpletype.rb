require 'test/unit'
require 'soap/rpc/standaloneServer'
require 'soap/wsdlDriver'


module WSDL
module SimpleType


class TestSimpleType < Test::Unit::TestCase
  class Server < ::SOAP::RPC::StandaloneServer
    def on_init
      add_document_method(self, 'urn:example.com:simpletype:ping', 'ping',
        XSD::QName.new('urn:example.com:simpletype', 'ruby'),
        XSD::QName.new('http://www.w3.org/2001/XMLSchema', 'string'))
      add_document_method(self, 'urn:example.com:simpletype:ping_id', 'ping_id',
        XSD::QName.new('urn:example.com:simpletype', 'myid'),
        XSD::QName.new('urn:example.com:simpletype', 'myid'))
    end
  
    def ping(ruby)
      version = ruby["myversion"]
      date = ruby["date"]
      "#{version} (#{date})"
    end

    def ping_id(id)
      id
    end
  end

  DIR = File.dirname(File.expand_path(__FILE__))

  Port = 17171

  def setup
    setup_server
    setup_client
  end

  def setup_server
    @server = Server.new('Test', "urn:example.com:simpletype", '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @server_thread = start_server_thread(@server)
  end

  def setup_client
    wsdl = File.join(DIR, 'simpletype.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.generate_explicit_type = false
    @client.wiredump_dev = STDOUT if $DEBUG
  end

  def teardown
    teardown_server
    teardown_client
  end

  def teardown_server
    @server.shutdown
    @server_thread.kill
    @server_thread.join
  end

  def teardown_client
    @client.reset_stream
  end

  def start_server_thread(server)
    t = Thread.new {
      Thread.current.abort_on_exception = true
      server.start
    }
    t
  end

  def test_ping
    ret = @client.ping({:myversion => "1.9", :date => "2004-01-01T00:00:00Z"})
    assert_equal("1.9 (2004-01-01T00:00:00Z)", ret)
  end

  def test_ping_id
    ret = @client.ping_id("012345678901234567")
    assert_equal("012345678901234567", ret)
    # length
    assert_raise(XSD::ValueSpaceError) do
      @client.ping_id("0123456789012345678")
    end
    # pattern
    assert_raise(XSD::ValueSpaceError) do
      @client.ping_id("01234567890123456;")
    end
  end
end


end
end
