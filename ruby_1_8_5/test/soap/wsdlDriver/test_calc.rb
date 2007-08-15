require 'test/unit'
require 'soap/rpc/httpserver'
require 'soap/wsdlDriver'


module SOAP


class TestCalc < Test::Unit::TestCase
  class Server < ::SOAP::RPC::HTTPServer
    def on_init
      add_method(self, 'add', 'x', 'y')
    end
  
    def add(x, y)
      x.to_f + y.to_f
    end
  end

  DIR = File.dirname(File.expand_path(__FILE__))
  Port = 17171

  def setup
    setup_server
    setup_client
  end

  def setup_server
    @server = Server.new(
      :BindAddress => "0.0.0.0",
      :Port => Port,
      :AccessLog => [],
      :SOAPDefaultNamespace => 'http://www.fred.com'
    )
    @server.level = Logger::Severity::ERROR
    @server_thread = start_server_thread(@server)
  end

  def setup_client
    @wsdl = File.join(DIR, 'calc.wsdl')
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
    @client.reset_stream if @client
  end

  def start_server_thread(server)
    t = Thread.new {
      Thread.current.abort_on_exception = true
      server.start
    }
    t
  end

  def test_rpc_driver
    @client = ::SOAP::WSDLDriverFactory.new(@wsdl).create_rpc_driver
    @client.wiredump_dev = STDOUT if $DEBUG
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.generate_explicit_type = true
    assert_equal(0.3, @client.add(0.1, 0.2))
    @client.generate_explicit_type = false
    assert_equal(0.3, @client.add(0.1, 0.2))
  end

  def test_old_driver
    silent do
      @client = ::SOAP::WSDLDriverFactory.new(@wsdl).create_driver
    end
    @client.wiredump_dev = STDOUT if $DEBUG
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.generate_explicit_type = true
    assert_equal(0.3, @client.add(0.1, 0.2))
    @client.generate_explicit_type = false
    assert_equal(0.3, @client.add(0.1, 0.2))
  end

  def silent
    back = $VERBOSE
    $VERBOSE = nil
    begin
      yield
    ensure
      $VERBOSE = back
    end
  end
end


end
