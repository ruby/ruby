require 'test/unit'
require 'soap/rpc/standaloneServer'
require 'soap/wsdlDriver'


module WSDL
module SimpleType


class TestSimpleType < Test::Unit::TestCase
  class Server < ::SOAP::RPC::StandaloneServer
    def on_init
      add_method(self, 'ruby', 'version', 'date')
    end
  
    def ruby(version, date)
      "#{version} (#{date})"
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
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.generate_explicit_type = false
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
    while server.status != :Running
      sleep 0.1
      unless t.alive?
	t.join
	raise
      end
    end
    t
  end

  def test_ping
    header, body = @client.ping(nil, {:version => "1.9", :date => "2004-01-01T00:00:00Z"})
    assert_equal("1.9 (2004-01-01T00:00:00Z)", body)
  end
end


end
end
