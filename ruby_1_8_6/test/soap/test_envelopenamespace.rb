require 'test/unit'
require 'soap/rpc/driver'
require 'webrick'
require 'logger'


module SOAP


class TestEnvelopeNamespace < Test::Unit::TestCase
  Port = 17171
  TemporaryNamespace = 'urn:foo'

  def setup
    @logger = Logger.new(STDERR)
    @logger.level = Logger::Severity::ERROR
    @url = "http://localhost:#{Port}/"
    @server = @client = nil
    @server_thread = nil
    setup_server
    setup_client
  end

  def teardown
    teardown_client
    teardown_server
  end

  def setup_server
    @server = WEBrick::HTTPServer.new(
      :BindAddress => "0.0.0.0",
      :Logger => @logger,
      :Port => Port,
      :AccessLog => [],
      :DocumentRoot => File.dirname(File.expand_path(__FILE__))
    )
    @server.mount(
      '/',
      WEBrick::HTTPServlet::ProcHandler.new(method(:do_server_proc).to_proc)
    )
    @server_thread = start_server_thread(@server)
  end

  def setup_client
    @client = SOAP::RPC::Driver.new(@url, '')
    @client.add_method("do_server_proc")
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

  def do_server_proc(req, res)
    res['content-type'] = 'text/xml'
    res.body = <<__EOX__
<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:env="#{TemporaryNamespace}">
  <env:Body>
    <n1:do_server_proc xmlns:n1="urn:foo" env:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <return>hello world</return>
    </n1:do_server_proc>
  </env:Body>
</env:Envelope>
__EOX__
  end

  def test_normal
    assert_raise(SOAP::ResponseFormatError) do
      @client.do_server_proc
    end
    @client.options["soap.envelope.requestnamespace"] = TemporaryNamespace
    @client.options["soap.envelope.responsenamespace"] = TemporaryNamespace
    assert_equal('hello world', @client.do_server_proc)
  end
end


end
