require 'test/unit'
require 'soap/rpc/standaloneServer'
require 'soap/wsdlDriver'


module WSDL
module SOAP


class TestSOAPBodyParts < Test::Unit::TestCase
  class Server < ::SOAP::RPC::StandaloneServer
    def on_init
      add_method(self, 'foo', 'p1', 'p2', 'p3')
      add_method(self, 'bar', 'p1', 'p2', 'p3')
      add_method(self, 'baz', 'p1', 'p2', 'p3')
    end

    def foo(p1, p2, p3)
      [p1, p2, p3]
    end

    alias bar foo

    def baz(p1, p2, p3)
      [p3, p2, p1]
    end
  end

  DIR = File.dirname(File.expand_path(__FILE__))

  Port = 17171

  def setup
    setup_server
    setup_client
  end

  def setup_server
    @server = Server.new('Test', "urn:www.example.com:soapbodyparts:v1", '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @t = Thread.new {
      Thread.current.abort_on_exception = true
      @server.start
    }
  end

  def setup_client
    wsdl = File.join(DIR, 'soapbodyparts.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.wiredump_dev = STDERR if $DEBUG
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

  def test_soapbodyparts
    assert_equal(["1", "2", "3"], @client.foo("1", "2", "3"))
    assert_equal(["3", "2", "1"], @client.foo("3", "2", "1"))
    assert_equal(["1", "2", "3"], @client.bar("1", "2", "3"))
    assert_equal(["3", "2", "1"], @client.baz("1", "2", "3"))
  end
end


end
end
