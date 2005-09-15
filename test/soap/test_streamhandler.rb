require 'test/unit'
require 'soap/rpc/driver'
require 'webrick'
require 'webrick/httpproxy'
require 'logger'


module SOAP


class TestStreamHandler < Test::Unit::TestCase
  Port = 17171
  ProxyPort = 17172

  def setup
    @logger = Logger.new(STDERR)
    @logger.level = Logger::Severity::ERROR
    @url = "http://localhost:#{Port}/"
    @proxyurl = "http://localhost:#{ProxyPort}/"
    @server = @proxyserver = @client = nil
    @server_thread = @proxyserver_thread = nil
    setup_server
    setup_client
  end

  def teardown
    teardown_client
    teardown_proxyserver if @proxyserver
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

  def setup_proxyserver
    @proxyserver = WEBrick::HTTPProxyServer.new(
      :BindAddress => "0.0.0.0",
      :Logger => @logger,
      :Port => ProxyPort,
      :AccessLog => []
    )
    @proxyserver_thread = start_server_thread(@proxyserver)
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

  def teardown_proxyserver
    @proxyserver.shutdown
    @proxyserver_thread.kill
    @proxyserver_thread.join
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
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:env="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <env:Body>
    <n1:do_server_proc xmlns:n1="urn:foo" env:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
      <return xsi:nil="true"/>
    </n1:do_server_proc>
  </env:Body>
</env:Envelope>
__EOX__
  end

  def parse_req_header(str)
    if ::SOAP::HTTPStreamHandler::Client.to_s == 'SOAP::NetHttpClient'
      str = eval(str.split(/\r?\n/)[4][3..-1])
    end
    parse_req_header_http_access2(str)
  end

  def parse_req_header_http_access2(str)
    headerp = false
    headers = {}
    req = nil
    str.split(/(?:\r?\n)/).each do |line|
      if headerp and /^$/ =~line
	headerp = false
	break
      end
      if headerp
	k, v = line.scan(/^([^:]+):\s*(.*)$/)[0]
	headers[k.downcase] = v
      end
      if /^POST/ =~ line
	req = line
	headerp = true
      end
    end
    return req, headers
  end

  def test_normal
    str = ""
    @client.wiredump_dev = str
    assert_nil(@client.do_server_proc)
    r, h = parse_req_header(str)
    assert_match(%r"POST / HTTP/1.", r)
    assert(/^text\/xml;/ =~ h["content-type"])
  end

  def test_uri
    # initialize client with URI object
    @client = SOAP::RPC::Driver.new(URI.parse(@url), '')
    @client.add_method("do_server_proc")
    # same as test_normal
    str = ""
    @client.wiredump_dev = str
    assert_nil(@client.do_server_proc)
    r, h = parse_req_header(str)
    assert_match(%r"POST / HTTP/1.", r)
    assert(/^text\/xml;/ =~ h["content-type"])
  end

  def test_basic_auth
    unless Object.const_defined?('HTTPAccess2')
      # soap4r + net/http + basic_auth is not supported.
      # use http-access2 instead.
      assert(true)
      return
    end
    str = ""
    @client.wiredump_dev = str
    @client.options["protocol.http.basic_auth"] << [@url, "foo", "bar"]
    assert_nil(@client.do_server_proc)
    r, h = parse_req_header(str)
    assert_equal("Basic Zm9vOmJhcg==", h["authorization"])
  end

  def test_proxy
    if Object.const_defined?('HTTPAccess2')
      backup = HTTPAccess2::Client::NO_PROXY_HOSTS.dup
      HTTPAccess2::Client::NO_PROXY_HOSTS.clear
    else
      backup = SOAP::NetHttpClient::NO_PROXY_HOSTS.dup
      SOAP::NetHttpClient::NO_PROXY_HOSTS.clear
    end
    setup_proxyserver
    str = ""
    @client.wiredump_dev = str
    @client.options["protocol.http.proxy"] = @proxyurl
    assert_nil(@client.do_server_proc)
    r, h = parse_req_header(str)
    assert_match(%r"POST http://localhost:17171/ HTTP/1.", r)
    # illegal proxy uri
    assert_raise(ArgumentError) do
      @client.options["protocol.http.proxy"] = 'ftp://foo:8080'
    end
  ensure
    if Object.const_defined?('HTTPAccess2')
      HTTPAccess2::Client::NO_PROXY_HOSTS.replace(backup)
    else
      SOAP::NetHttpClient::NO_PROXY_HOSTS.replace(backup)
    end
  end

  def test_charset
    str = ""
    @client.wiredump_dev = str
    @client.options["protocol.http.charset"] = "iso-8859-8"
    assert_nil(@client.do_server_proc)
    r, h = parse_req_header(str)
    assert_equal("text/xml; charset=iso-8859-8", h["content-type"])
    #
    str.replace("")
    @client.options["protocol.http.charset"] = "iso-8859-3"
    assert_nil(@client.do_server_proc)
    r, h = parse_req_header(str)
    assert_equal("text/xml; charset=iso-8859-3", h["content-type"])
  end
end


end
