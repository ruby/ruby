require 'test/unit'
require 'soap/rpc/httpserver'
require 'soap/wsdlDriver'


module WSDL


class TestMap < Test::Unit::TestCase
  Port = 17171
  DIR = File.dirname(File.expand_path(__FILE__))

  class Server < ::SOAP::RPC::HTTPServer
    def on_init
      add_method(self, 'map')
      add_method(self, 'map2', 'arg')
    end

    def map
      {1 => "a", 2 => "b"}
    end

    def map2(arg)
      arg
    end
  end

  def setup
    setup_server
    setup_client
  end

  def setup_server
    @server = Server.new(
      :BindAddress => "0.0.0.0",
      :Port => Port,
      :AccessLog => [],
      :SOAPDefaultNamespace => "urn:map"
    )
    @server.level = Logger::Severity::ERROR
    @t = Thread.new {
      Thread.current.abort_on_exception = true
      @server.start
    }
  end

  def setup_client
    wsdl = File.join(DIR, 'map.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
    @client.generate_explicit_type = true
    @client.wiredump_dev = STDOUT if $DEBUG
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

  def test_by_wsdl
    dir = File.dirname(File.expand_path(__FILE__))
    wsdlfile = File.join(dir, 'map.wsdl')
    xml = File.open(File.join(dir, 'map.xml')) { |f| f.read }
    wsdl = WSDL::Importer.import(wsdlfile)
    service = wsdl.services[0]
    port = service.ports[0]
    wsdl_types = wsdl.collect_complextypes
    rpc_decode_typemap = wsdl_types + wsdl.soap_rpc_complextypes(port.find_binding)
    opt = {}
    opt[:default_encodingstyle] = ::SOAP::EncodingNamespace
    opt[:decode_typemap] = rpc_decode_typemap
    header, body = ::SOAP::Processor.unmarshal(xml, opt)
    map = ::SOAP::Mapping.soap2obj(body.response)
    assert_equal(["a1"], map["a"]["a1"])
    assert_equal(["a2"], map["a"]["a2"])
    assert_equal(["b1"], map["b"]["b1"])
    assert_equal(["b2"], map["b"]["b2"])
  end

  def test_wsdldriver
    assert_equal({1 => "a", 2 => "b"}, @client.map)
    assert_equal({1 => 2}, @client.map2({1 => 2}))
    assert_equal({1 => {2 => 3}}, @client.map2({1 => {2 => 3}}))
    assert_equal({["a", 2] => {2 => 3}}, @client.map2({["a", 2] => {2 => 3}}))
  end
end


end
