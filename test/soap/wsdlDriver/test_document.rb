require 'test/unit'
require 'soap/rpc/standaloneServer'
require 'soap/wsdlDriver'


module SOAP


class TestDocument < Test::Unit::TestCase
  Namespace = 'urn:example.com:document'

  class Server < ::SOAP::RPC::StandaloneServer
    def on_init
      add_document_method(self, 'urn:example.com:document#submit', 'submit', XSD::QName.new(Namespace, 'ruby'), XSD::QName.new(Namespace, 'ruby'))
    end

    def submit(ruby)
      ruby
    end
  end

  DIR = File.dirname(File.expand_path(__FILE__))

  Port = 17171

  def setup
    setup_server
    setup_client
  end

  def setup_server
    @server = Server.new('Test', Namespace, '0.0.0.0', Port)
    @server.level = Logger::Severity::ERROR
    @server_thread = start_server_thread(@server)
  end

  def setup_client
    wsdl = File.join(DIR, 'document.wsdl')
    @client = ::SOAP::WSDLDriverFactory.new(wsdl).create_rpc_driver
    @client.endpoint_url = "http://localhost:#{Port}/"
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

  def test_document
    msg = {'myversion' => "1.9", 'date' => "2004-01-01T00:00:00Z"}
    reply_msg = @client.submit(msg)
    assert_equal('1.9', reply_msg.myversion)
    assert_equal('1.9', reply_msg['myversion'])
    assert_equal('2004-01-01T00:00:00Z', reply_msg.date)
    assert_equal('2004-01-01T00:00:00Z', reply_msg['date'])
  end
end


end
