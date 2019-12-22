# coding: US-ASCII
# frozen_string_literal: false
require 'test/unit'
require 'net/http'
require 'stringio'
require_relative 'utils'

class TestNetHTTP < Test::Unit::TestCase

  def test_class_Proxy
    no_proxy_class = Net::HTTP.Proxy nil

    assert_equal Net::HTTP, no_proxy_class

    proxy_class = Net::HTTP.Proxy 'proxy.example', 8000, 'user', 'pass'

    assert_not_equal Net::HTTP, proxy_class

    assert_operator proxy_class, :<, Net::HTTP

    assert_equal 'proxy.example', proxy_class.proxy_address
    assert_equal 8000,            proxy_class.proxy_port
    assert_equal 'user',          proxy_class.proxy_user
    assert_equal 'pass',          proxy_class.proxy_pass

    http = proxy_class.new 'hostname.example'

    assert_not_predicate http, :proxy_from_env?


    proxy_class = Net::HTTP.Proxy 'proxy.example'
    assert_equal 'proxy.example', proxy_class.proxy_address
    assert_equal 80,              proxy_class.proxy_port
  end

  def test_class_Proxy_from_ENV
    TestNetHTTPUtils.clean_http_proxy_env do
      ENV['http_proxy']      = 'http://proxy.example:8000'

      # These are ignored on purpose.  See Bug 4388 and Feature 6546
      ENV['http_proxy_user'] = 'user'
      ENV['http_proxy_pass'] = 'pass'

      proxy_class = Net::HTTP.Proxy :ENV

      assert_not_equal Net::HTTP, proxy_class

      assert_operator proxy_class, :<, Net::HTTP

      assert_nil proxy_class.proxy_address
      assert_nil proxy_class.proxy_user
      assert_nil proxy_class.proxy_pass

      assert_not_equal 8000, proxy_class.proxy_port

      http = proxy_class.new 'hostname.example'

      assert http.proxy_from_env?
    end
  end

  def test_addr_port
    http = Net::HTTP.new 'hostname.example', nil, nil
    addr_port = http.__send__ :addr_port
    assert_equal 'hostname.example', addr_port

    http.use_ssl = true
    addr_port = http.__send__ :addr_port
    assert_equal 'hostname.example:80', addr_port

    http = Net::HTTP.new '203.0.113.1', nil, nil
    addr_port = http.__send__ :addr_port
    assert_equal '203.0.113.1', addr_port

    http.use_ssl = true
    addr_port = http.__send__ :addr_port
    assert_equal '203.0.113.1:80', addr_port

    http = Net::HTTP.new '2001:db8::1', nil, nil
    addr_port = http.__send__ :addr_port
    assert_equal '[2001:db8::1]', addr_port

    http.use_ssl = true
    addr_port = http.__send__ :addr_port
    assert_equal '[2001:db8::1]:80', addr_port

  end

  def test_edit_path
    http = Net::HTTP.new 'hostname.example', nil, nil

    edited = http.send :edit_path, '/path'

    assert_equal '/path', edited

    http.use_ssl = true

    edited = http.send :edit_path, '/path'

    assert_equal '/path', edited
  end

  def test_edit_path_proxy
    http = Net::HTTP.new 'hostname.example', nil, 'proxy.example'

    edited = http.send :edit_path, '/path'

    assert_equal 'http://hostname.example/path', edited

    http.use_ssl = true

    edited = http.send :edit_path, '/path'

    assert_equal '/path', edited
  end

  def test_proxy_address
    TestNetHTTPUtils.clean_http_proxy_env do
      http = Net::HTTP.new 'hostname.example', nil, 'proxy.example'
      assert_equal 'proxy.example', http.proxy_address

      http = Net::HTTP.new 'hostname.example', nil
      assert_equal nil, http.proxy_address
    end
  end

  def test_proxy_address_no_proxy
    TestNetHTTPUtils.clean_http_proxy_env do
      http = Net::HTTP.new 'hostname.example', nil, 'proxy.example', nil, nil, nil, 'example'
      assert_nil http.proxy_address

      http = Net::HTTP.new '10.224.1.1', nil, 'proxy.example', nil, nil, nil, 'example,10.224.0.0/22'
      assert_nil http.proxy_address
    end
  end

  def test_proxy_from_env_ENV
    TestNetHTTPUtils.clean_http_proxy_env do
      ENV['http_proxy'] = 'http://proxy.example:8000'

      assert_equal false, Net::HTTP.proxy_class?
      http = Net::HTTP.new 'hostname.example'

      assert_equal true, http.proxy_from_env?
    end
  end

  def test_proxy_address_ENV
    TestNetHTTPUtils.clean_http_proxy_env do
      ENV['http_proxy'] = 'http://proxy.example:8000'

      http = Net::HTTP.new 'hostname.example'

      assert_equal 'proxy.example', http.proxy_address
    end
  end

  def test_proxy_eh_no_proxy
    TestNetHTTPUtils.clean_http_proxy_env do
      assert_equal false, Net::HTTP.new('hostname.example', nil, nil).proxy?
    end
  end

  def test_proxy_eh_ENV
    TestNetHTTPUtils.clean_http_proxy_env do
      ENV['http_proxy'] = 'http://proxy.example:8000'

      http = Net::HTTP.new 'hostname.example'

      assert_equal true, http.proxy?
    end
  end

  def test_proxy_eh_ENV_with_user
    TestNetHTTPUtils.clean_http_proxy_env do
      ENV['http_proxy'] = 'http://foo:bar@proxy.example:8000'

      http = Net::HTTP.new 'hostname.example'

      assert_equal true, http.proxy?
      if Net::HTTP::ENVIRONMENT_VARIABLE_IS_MULTIUSER_SAFE
        assert_equal 'foo', http.proxy_user
        assert_equal 'bar', http.proxy_pass
      else
        assert_nil http.proxy_user
        assert_nil http.proxy_pass
      end
    end
  end

  def test_proxy_eh_ENV_none_set
    TestNetHTTPUtils.clean_http_proxy_env do
      assert_equal false, Net::HTTP.new('hostname.example').proxy?
    end
  end

  def test_proxy_eh_ENV_no_proxy
    TestNetHTTPUtils.clean_http_proxy_env do
      ENV['http_proxy'] = 'http://proxy.example:8000'
      ENV['no_proxy']   = 'hostname.example'

      assert_equal false, Net::HTTP.new('hostname.example').proxy?
    end
  end

  def test_proxy_port
    TestNetHTTPUtils.clean_http_proxy_env do
      http = Net::HTTP.new 'example', nil, 'proxy.example'
      assert_equal 'proxy.example', http.proxy_address
      assert_equal 80, http.proxy_port
      http = Net::HTTP.new 'example', nil, 'proxy.example', 8000
      assert_equal 8000, http.proxy_port
      http = Net::HTTP.new 'example', nil
      assert_equal nil, http.proxy_port
    end
  end

  def test_proxy_port_ENV
    TestNetHTTPUtils.clean_http_proxy_env do
      ENV['http_proxy'] = 'http://proxy.example:8000'

      http = Net::HTTP.new 'hostname.example'

      assert_equal 8000, http.proxy_port
    end
  end

  def test_newobj
    TestNetHTTPUtils.clean_http_proxy_env do
      ENV['http_proxy'] = 'http://proxy.example:8000'

      http = Net::HTTP.newobj 'hostname.example'

      assert_equal false, http.proxy?
    end
  end

  def test_failure_message_includes_failed_domain_and_port
    # hostname to be included in the error message
    host = Struct.new(:to_s).new("<example>")
    port = 2119
    # hack to let TCPSocket.open fail
    def host.to_str; raise SocketError, "open failure"; end
    uri = Struct.new(:scheme, :hostname, :port).new("http", host, port)
    assert_raise_with_message(SocketError, /#{host}:#{port}/) do
      TestNetHTTPUtils.clean_http_proxy_env{ Net::HTTP.get(uri) }
    end
  end

end

module TestNetHTTP_version_1_1_methods

  def test_s_start
    begin
      h = Net::HTTP.start(config('host'), config('port'))
    ensure
      h&.finish
    end
    assert_equal config('host'), h.address
    assert_equal config('port'), h.port
    assert_equal true, h.instance_variable_get(:@proxy_from_env)

    begin
      h = Net::HTTP.start(config('host'), config('port'), :ENV)
    ensure
      h&.finish
    end
    assert_equal config('host'), h.address
    assert_equal config('port'), h.port
    assert_equal true, h.instance_variable_get(:@proxy_from_env)

    begin
      h = Net::HTTP.start(config('host'), config('port'), nil)
    ensure
      h&.finish
    end
    assert_equal config('host'), h.address
    assert_equal config('port'), h.port
    assert_equal false, h.instance_variable_get(:@proxy_from_env)
  end

  def test_s_get
    assert_equal $test_net_http_data,
        Net::HTTP.get(config('host'), '/', config('port'))
  end

  def test_head
    start {|http|
      res = http.head('/')
      assert_kind_of Net::HTTPResponse, res
      assert_equal $test_net_http_data_type, res['Content-Type']
      unless self.is_a?(TestNetHTTP_v1_2_chunked)
        assert_equal $test_net_http_data.size, res['Content-Length'].to_i
      end
    }
  end

  def test_get
    start {|http|
      _test_get__get http
      _test_get__iter http
      _test_get__chunked http
    }
  end

  def _test_get__get(http)
    res = http.get('/')
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    unless self.is_a?(TestNetHTTP_v1_2_chunked)
      assert_not_nil res['content-length']
      assert_equal $test_net_http_data.size, res['content-length'].to_i
    end
    assert_equal $test_net_http_data_type, res['Content-Type']
    assert_equal $test_net_http_data.size, res.body.size
    assert_equal $test_net_http_data, res.body

    assert_nothing_raised {
      http.get('/', { 'User-Agent' => 'test' }.freeze)
    }

    assert res.decode_content, '[Bug #7924]' if Net::HTTP::HAVE_ZLIB
  end

  def _test_get__iter(http)
    buf = ''
    res = http.get('/') {|s| buf << s }
    assert_kind_of Net::HTTPResponse, res
    # assert_kind_of String, res.body
    unless self.is_a?(TestNetHTTP_v1_2_chunked)
      assert_not_nil res['content-length']
      assert_equal $test_net_http_data.size, res['content-length'].to_i
    end
    assert_equal $test_net_http_data_type, res['Content-Type']
    assert_equal $test_net_http_data.size, buf.size
    assert_equal $test_net_http_data, buf
    # assert_equal $test_net_http_data.size, res.body.size
    # assert_equal $test_net_http_data, res.body
  end

  def _test_get__chunked(http)
    buf = ''
    res = http.get('/') {|s| buf << s }
    assert_kind_of Net::HTTPResponse, res
    # assert_kind_of String, res.body
    unless self.is_a?(TestNetHTTP_v1_2_chunked)
      assert_not_nil res['content-length']
      assert_equal $test_net_http_data.size, res['content-length'].to_i
    end
    assert_equal $test_net_http_data_type, res['Content-Type']
    assert_equal $test_net_http_data.size, buf.size
    assert_equal $test_net_http_data, buf
    # assert_equal $test_net_http_data.size, res.body.size
    # assert_equal $test_net_http_data, res.body
  end

  def test_get__break
    i = 0
    start {|http|
      http.get('/') do |str|
        i += 1
        break
      end
    }
    assert_equal 1, i
    @log_tester = nil # server may encount ECONNRESET
  end

  def test_get__implicit_start
    res = new().get('/')
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    unless self.is_a?(TestNetHTTP_v1_2_chunked)
      assert_not_nil res['content-length']
    end
    assert_equal $test_net_http_data_type, res['Content-Type']
    assert_equal $test_net_http_data.size, res.body.size
    assert_equal $test_net_http_data, res.body
  end

  def test_get__crlf
    start {|http|
      assert_raise(ArgumentError) do
        http.get("\r")
      end
      assert_raise(ArgumentError) do
        http.get("\n")
      end
    }
  end

  def test_get2
    start {|http|
      http.get2('/') {|res|
        EnvUtil.suppress_warning do
          assert_kind_of Net::HTTPResponse, res
          assert_kind_of Net::HTTPResponse, res.header
        end

        unless self.is_a?(TestNetHTTP_v1_2_chunked)
          assert_not_nil res['content-length']
        end
        assert_equal $test_net_http_data_type, res['Content-Type']
        assert_kind_of String, res.body
        assert_kind_of String, res.entity
        assert_equal $test_net_http_data.size, res.body.size
        assert_equal $test_net_http_data, res.body
        assert_equal $test_net_http_data, res.entity
      }
    }
  end

  def test_post
    start {|http|
      _test_post__base http
      _test_post__file http
      _test_post__no_data http
    }
  end

  def _test_post__base(http)
    uheader = {}
    uheader['Accept'] = 'application/octet-stream'
    uheader['Content-Type'] = 'application/x-www-form-urlencoded'
    data = 'post data'
    res = http.post('/', data, uheader)
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    assert_equal data, res.body
    assert_equal data, res.entity
  end

  def _test_post__file(http)
    data = 'post data'
    f = StringIO.new
    http.post('/', data, {'content-type' => 'application/x-www-form-urlencoded'}, f)
    assert_equal data, f.string
  end

  def _test_post__no_data(http)
    unless self.is_a?(TestNetHTTP_v1_2_chunked)
      EnvUtil.suppress_warning do
        data = nil
        res = http.post('/', data)
        assert_not_equal '411', res.code
      end
    end
  end

  def test_s_post
    url = "http://#{config('host')}:#{config('port')}/?q=a"
    res = assert_warning(/Content-Type did not set/) do
      Net::HTTP.post(
              URI.parse(url),
              "a=x")
    end
    assert_equal "application/x-www-form-urlencoded", res["Content-Type"]
    assert_equal "a=x", res.body
    assert_equal url, res["X-request-uri"]

    res = Net::HTTP.post(
              URI.parse(url),
              "hello world",
              "Content-Type" => "text/plain; charset=US-ASCII")
    assert_equal "text/plain; charset=US-ASCII", res["Content-Type"]
    assert_equal "hello world", res.body
  end

  def test_s_post_form
    url = "http://#{config('host')}:#{config('port')}/"
    res = Net::HTTP.post_form(
              URI.parse(url),
              "a" => "x")
    assert_equal ["a=x"], res.body.split(/[;&]/).sort

    res = Net::HTTP.post_form(
              URI.parse(url),
              "a" => "x",
              "b" => "y")
    assert_equal ["a=x", "b=y"], res.body.split(/[;&]/).sort

    res = Net::HTTP.post_form(
              URI.parse(url),
              "a" => ["x1", "x2"],
              "b" => "y")
    assert_equal url, res['X-request-uri']
    assert_equal ["a=x1", "a=x2", "b=y"], res.body.split(/[;&]/).sort

    res = Net::HTTP.post_form(
              URI.parse(url + '?a=x'),
              "b" => "y")
    assert_equal url + '?a=x', res['X-request-uri']
    assert_equal ["b=y"], res.body.split(/[;&]/).sort
  end

  def test_patch
    start {|http|
      _test_patch__base http
    }
  end

  def _test_patch__base(http)
    uheader = {}
    uheader['Accept'] = 'application/octet-stream'
    uheader['Content-Type'] = 'application/x-www-form-urlencoded'
    data = 'patch data'
    res = http.patch('/', data, uheader)
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    assert_equal data, res.body
    assert_equal data, res.entity
  end

  def test_timeout_during_HTTP_session_write
    th = nil
    # listen for connections... but deliberately do not read
    TCPServer.open('localhost', 0) {|server|
      port = server.addr[1]

      conn = Net::HTTP.new('localhost', port)
      conn.write_timeout = EnvUtil.apply_timeout_scale(0.01)
      conn.read_timeout = EnvUtil.apply_timeout_scale(0.01) if windows?
      conn.open_timeout = EnvUtil.apply_timeout_scale(0.1)

      th = Thread.new do
        err = !windows? ? Net::WriteTimeout : Net::ReadTimeout
        assert_raise(err) do
          assert_warning(/Content-Type did not set/) do
            conn.post('/', "a"*50_000_000)
          end
        end
      end
      assert th.join(EnvUtil.apply_timeout_scale(10))
    }
  ensure
    th&.kill
    th&.join
  end

  def test_timeout_during_HTTP_session
    bug4246 = "expected the HTTP session to have timed out but have not. c.f. [ruby-core:34203]"

    th = nil
    # listen for connections... but deliberately do not read
    TCPServer.open('localhost', 0) {|server|
      port = server.addr[1]

      conn = Net::HTTP.new('localhost', port)
      conn.read_timeout = EnvUtil.apply_timeout_scale(0.01)
      conn.open_timeout = EnvUtil.apply_timeout_scale(0.1)

      th = Thread.new do
        assert_raise(Net::ReadTimeout) {
          conn.get('/')
        }
      end
      assert th.join(EnvUtil.apply_timeout_scale(10)), bug4246
    }
  ensure
    th.kill
    th.join
  end
end


module TestNetHTTP_version_1_2_methods

  def test_request
    start {|http|
      _test_request__GET http
      _test_request__accept_encoding http
      _test_request__file http
      # _test_request__range http   # WEBrick does not support Range: header.
      _test_request__HEAD http
      _test_request__POST http
      _test_request__stream_body http
      _test_request__uri http
      _test_request__uri_host http
    }
  end

  def _test_request__GET(http)
    req = Net::HTTP::Get.new('/')
    http.request(req) {|res|
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
      unless self.is_a?(TestNetHTTP_v1_2_chunked)
        assert_not_nil res['content-length']
        assert_equal $test_net_http_data.size, res['content-length'].to_i
      end
      assert_equal $test_net_http_data.size, res.body.size
      assert_equal $test_net_http_data, res.body

      assert res.decode_content, 'Bug #7831' if Net::HTTP::HAVE_ZLIB
    }
  end

  def _test_request__accept_encoding(http)
    req = Net::HTTP::Get.new('/', 'accept-encoding' => 'deflate')
    http.request(req) {|res|
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
      unless self.is_a?(TestNetHTTP_v1_2_chunked)
        assert_not_nil res['content-length']
        assert_equal $test_net_http_data.size, res['content-length'].to_i
      end
      assert_equal $test_net_http_data.size, res.body.size
      assert_equal $test_net_http_data, res.body

      assert_not_predicate res, :decode_content, 'Bug #7831' if Net::HTTP::HAVE_ZLIB
    }
  end

  def _test_request__file(http)
    req = Net::HTTP::Get.new('/')
    http.request(req) {|res|
      assert_kind_of Net::HTTPResponse, res
      unless self.is_a?(TestNetHTTP_v1_2_chunked)
        assert_not_nil res['content-length']
        assert_equal $test_net_http_data.size, res['content-length'].to_i
      end
      f = StringIO.new("".force_encoding("ASCII-8BIT"))
      res.read_body f
      assert_equal $test_net_http_data.bytesize, f.string.bytesize
      assert_equal $test_net_http_data.encoding, f.string.encoding
      assert_equal $test_net_http_data, f.string
    }
  end

  def _test_request__range(http)
    req = Net::HTTP::Get.new('/')
    req['range'] = 'bytes=0-5'
    assert_equal $test_net_http_data[0,6], http.request(req).body
  end

  def _test_request__HEAD(http)
    req = Net::HTTP::Head.new('/')
    http.request(req) {|res|
      assert_kind_of Net::HTTPResponse, res
      unless self.is_a?(TestNetHTTP_v1_2_chunked)
        assert_not_nil res['content-length']
        assert_equal $test_net_http_data.size, res['content-length'].to_i
      end
      assert_nil res.body
    }
  end

  def _test_request__POST(http)
    data = 'post data'
    req = Net::HTTP::Post.new('/')
    req['Accept'] = $test_net_http_data_type
    req['Content-Type'] = 'application/x-www-form-urlencoded'
    http.request(req, data) {|res|
      assert_kind_of Net::HTTPResponse, res
      unless self.is_a?(TestNetHTTP_v1_2_chunked)
        assert_equal data.size, res['content-length'].to_i
      end
      assert_kind_of String, res.body
      assert_equal data, res.body
    }
  end

  def _test_request__stream_body(http)
    req = Net::HTTP::Post.new('/')
    data = $test_net_http_data
    req.content_length = data.size
    req['Content-Type'] = 'application/x-www-form-urlencoded'
    req.body_stream = StringIO.new(data)
    res = http.request(req)
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    assert_equal data.size, res.body.size
    assert_equal data, res.body
  end

  def _test_request__path(http)
    uri = URI 'https://hostname.example/'
    req = Net::HTTP::Get.new('/')

    res = http.request(req)

    assert_kind_of URI::Generic, req.uri

    assert_not_equal uri, req.uri

    assert_equal uri, res.uri

    assert_not_same uri,     req.uri
    assert_not_same req.uri, res.uri
  end

  def _test_request__uri(http)
    uri = URI 'https://hostname.example/'
    req = Net::HTTP::Get.new(uri)

    res = http.request(req)

    assert_kind_of URI::Generic, req.uri

    assert_not_equal uri, req.uri

    assert_equal req.uri, res.uri

    assert_not_same uri,     req.uri
    assert_not_same req.uri, res.uri
  end

  def _test_request__uri_host(http)
    uri = URI 'http://other.example/'

    req = Net::HTTP::Get.new(uri)
    req['host'] = 'hostname.example'

    res = http.request(req)

    assert_kind_of URI::Generic, req.uri

    assert_equal URI("http://hostname.example:#{http.port}"), res.uri
  end

  def test_send_request
    start {|http|
      _test_send_request__GET http
      _test_send_request__HEAD http
      _test_send_request__POST http
    }
  end

  def _test_send_request__GET(http)
    res = http.send_request('GET', '/')
    assert_kind_of Net::HTTPResponse, res
    unless self.is_a?(TestNetHTTP_v1_2_chunked)
      assert_equal $test_net_http_data.size, res['content-length'].to_i
    end
    assert_kind_of String, res.body
    assert_equal $test_net_http_data, res.body
  end

  def _test_send_request__HEAD(http)
    res = http.send_request('HEAD', '/')
    assert_kind_of Net::HTTPResponse, res
    unless self.is_a?(TestNetHTTP_v1_2_chunked)
      assert_not_nil res['content-length']
      assert_equal $test_net_http_data.size, res['content-length'].to_i
    end
    assert_nil res.body
  end

  def _test_send_request__POST(http)
    data = 'aaabbb cc ddddddddddd lkjoiu4j3qlkuoa'
    res = http.send_request('POST', '/', data, 'content-type' => 'application/x-www-form-urlencoded')
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    assert_equal data.size, res.body.size
    assert_equal data, res.body
  end

  def test_set_form
    require 'tempfile'
    Tempfile.create('ruby-test') {|file|
      file << "\u{30c7}\u{30fc}\u{30bf}"
      data = [
        ['name', 'Gonbei Nanashi'],
        ['name', "\u{540d}\u{7121}\u{3057}\u{306e}\u{6a29}\u{5175}\u{885b}"],
        ['s"i\o', StringIO.new("\u{3042 3044 4e9c 925b}")],
        ["file", file, filename: "ruby-test"]
      ]
      expected = <<"__EOM__".gsub(/\n/, "\r\n")
--<boundary>
Content-Disposition: form-data; name="name"

Gonbei Nanashi
--<boundary>
Content-Disposition: form-data; name="name"

\xE5\x90\x8D\xE7\x84\xA1\xE3\x81\x97\xE3\x81\xAE\xE6\xA8\xA9\xE5\x85\xB5\xE8\xA1\x9B
--<boundary>
Content-Disposition: form-data; name="s\\"i\\\\o"

\xE3\x81\x82\xE3\x81\x84\xE4\xBA\x9C\xE9\x89\x9B
--<boundary>
Content-Disposition: form-data; name="file"; filename="ruby-test"
Content-Type: application/octet-stream

\xE3\x83\x87\xE3\x83\xBC\xE3\x82\xBF
--<boundary>--
__EOM__
      start {|http|
        _test_set_form_urlencoded(http, data.reject{|k,v|!v.is_a?(String)})
        _test_set_form_multipart(http, false, data, expected)
        _test_set_form_multipart(http, true, data, expected)
      }
    }
  end

  def _test_set_form_urlencoded(http, data)
    req = Net::HTTP::Post.new('/')
    req.set_form(data)
    res = http.request req
    assert_equal "name=Gonbei+Nanashi&name=%E5%90%8D%E7%84%A1%E3%81%97%E3%81%AE%E6%A8%A9%E5%85%B5%E8%A1%9B", res.body
  end

  def _test_set_form_multipart(http, chunked_p, data, expected)
    data.each{|k,v|v.rewind rescue nil}
    req = Net::HTTP::Post.new('/')
    req.set_form(data, 'multipart/form-data')
    req['Transfer-Encoding'] = 'chunked' if chunked_p
    res = http.request req
    body = res.body
    assert_match(/\A--(?<boundary>\S+)/, body)
    /\A--(?<boundary>\S+)/ =~ body
    expected = expected.gsub(/<boundary>/, boundary)
    assert_equal(expected, body)
  end

  def test_set_form_with_file
    require 'tempfile'
    Tempfile.create('ruby-test') {|file|
      file.binmode
      file << $test_net_http_data
      filename = File.basename(file.to_path)
      data = [['file', file]]
      expected = <<"__EOM__".gsub(/\n/, "\r\n")
--<boundary>
Content-Disposition: form-data; name="file"; filename="<filename>"
Content-Type: application/octet-stream

<data>
--<boundary>--
__EOM__
      expected.sub!(/<filename>/, filename)
      expected.sub!(/<data>/, $test_net_http_data)
      start {|http|
        data.each{|k,v|v.rewind rescue nil}
        req = Net::HTTP::Post.new('/')
        req.set_form(data, 'multipart/form-data')
        res = http.request req
        body = res.body
        header, _ = body.split(/\r\n\r\n/, 2)
        assert_match(/\A--(?<boundary>\S+)/, body)
        /\A--(?<boundary>\S+)/ =~ body
        expected = expected.gsub(/<boundary>/, boundary)
        assert_match(/^--(?<boundary>\S+)\r\n/, header)
        assert_match(
          /^Content-Disposition: form-data; name="file"; filename="#{filename}"\r\n/,
          header)
        assert_equal(expected, body)

        data.each{|k,v|v.rewind rescue nil}
        req['Transfer-Encoding'] = 'chunked'
        res = http.request req
        #assert_equal(expected, res.body)
      }
    }
  end
end

class TestNetHTTP_v1_2 < Test::Unit::TestCase
  CONFIG = {
    'host' => '127.0.0.1',
    'proxy_host' => nil,
    'proxy_port' => nil,
  }

  include TestNetHTTPUtils
  include TestNetHTTP_version_1_1_methods
  include TestNetHTTP_version_1_2_methods

  def new
    Net::HTTP.version_1_2
    super
  end

  def test_send_large_POST_request
    start {|http|
      data = ' '*6000000
      res = http.send_request('POST', '/', data, 'content-type' => 'application/x-www-form-urlencoded')
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
      assert_equal data.size, res.body.size
      assert_equal data, res.body
    }
  end
end

class TestNetHTTP_v1_2_chunked < Test::Unit::TestCase
  CONFIG = {
    'host' => '127.0.0.1',
    'proxy_host' => nil,
    'proxy_port' => nil,
    'chunked' => true,
  }

  include TestNetHTTPUtils
  include TestNetHTTP_version_1_1_methods
  include TestNetHTTP_version_1_2_methods

  def new
    Net::HTTP.version_1_2
    super
  end

  def test_chunked_break
    assert_nothing_raised("[ruby-core:29229]") {
      start {|http|
        http.request_get('/') {|res|
          res.read_body {|chunk|
            break
          }
        }
      }
    }
  end
end

class TestNetHTTPContinue < Test::Unit::TestCase
  CONFIG = {
    'host' => '127.0.0.1',
    'proxy_host' => nil,
    'proxy_port' => nil,
    'chunked' => true,
  }

  include TestNetHTTPUtils

  def logfile
    @debug = StringIO.new('')
  end

  def mount_proc(&block)
    @server.mount('/continue', WEBrick::HTTPServlet::ProcHandler.new(block.to_proc))
  end

  def test_expect_continue
    mount_proc {|req, res|
      req.continue
      res.body = req.query['body']
    }
    start {|http|
      uheader = {'content-type' => 'application/x-www-form-urlencoded', 'expect' => '100-continue'}
      http.continue_timeout = 0.2
      http.request_post('/continue', 'body=BODY', uheader) {|res|
        assert_equal('BODY', res.read_body)
      }
    }
    assert_match(/Expect: 100-continue/, @debug.string)
    assert_match(/HTTP\/1.1 100 continue/, @debug.string)
  end

  def test_expect_continue_timeout
    mount_proc {|req, res|
      sleep 0.2
      req.continue # just ignored because it's '100'
      res.body = req.query['body']
    }
    start {|http|
      uheader = {'content-type' => 'application/x-www-form-urlencoded', 'expect' => '100-continue'}
      http.continue_timeout = 0
      http.request_post('/continue', 'body=BODY', uheader) {|res|
        assert_equal('BODY', res.read_body)
      }
    }
    assert_match(/Expect: 100-continue/, @debug.string)
    assert_match(/HTTP\/1.1 100 continue/, @debug.string)
  end

  def test_expect_continue_error
    mount_proc {|req, res|
      res.status = 501
      res.body = req.query['body']
    }
    start {|http|
      uheader = {'content-type' => 'application/x-www-form-urlencoded', 'expect' => '100-continue'}
      http.continue_timeout = 0
      http.request_post('/continue', 'body=ERROR', uheader) {|res|
        assert_equal('ERROR', res.read_body)
      }
    }
    assert_match(/Expect: 100-continue/, @debug.string)
    assert_not_match(/HTTP\/1.1 100 continue/, @debug.string)
  end

  def test_expect_continue_error_before_body
    @log_tester = nil
    mount_proc {|req, res|
      raise WEBrick::HTTPStatus::Forbidden
    }
    start {|http|
      uheader = {'content-type' => 'application/x-www-form-urlencoded', 'content-length' => '5', 'expect' => '100-continue'}
      http.continue_timeout = 1 # allow the server to respond before sending
      http.request_post('/continue', 'data', uheader) {|res|
        assert_equal(res.code, '403')
      }
    }
    assert_match(/Expect: 100-continue/, @debug.string)
    assert_not_match(/HTTP\/1.1 100 continue/, @debug.string)
  end

  def test_expect_continue_error_while_waiting
    mount_proc {|req, res|
      res.status = 501
      res.body = req.query['body']
    }
    start {|http|
      uheader = {'content-type' => 'application/x-www-form-urlencoded', 'expect' => '100-continue'}
      http.continue_timeout = 0.5
      http.request_post('/continue', 'body=ERROR', uheader) {|res|
        assert_equal('ERROR', res.read_body)
      }
    }
    assert_match(/Expect: 100-continue/, @debug.string)
    assert_not_match(/HTTP\/1.1 100 continue/, @debug.string)
  end
end

class TestNetHTTPSwitchingProtocols < Test::Unit::TestCase
  CONFIG = {
    'host' => '127.0.0.1',
    'proxy_host' => nil,
    'proxy_port' => nil,
    'chunked' => true,
  }

  include TestNetHTTPUtils

  def logfile
    @debug = StringIO.new('')
  end

  def mount_proc(&block)
    @server.mount('/continue', WEBrick::HTTPServlet::ProcHandler.new(block.to_proc))
  end

  def test_info
    mount_proc {|req, res|
      req.instance_variable_get(:@socket) << "HTTP/1.1 101 Switching Protocols\r\n\r\n"
      res.body = req.query['body']
    }
    start {|http|
      http.continue_timeout = 0.2
      http.request_post('/continue', 'body=BODY',
                        'content-type' => 'application/x-www-form-urlencoded') {|res|
        assert_equal('BODY', res.read_body)
      }
    }
    assert_match(/HTTP\/1.1 101 Switching Protocols/, @debug.string)
  end
end

class TestNetHTTPKeepAlive < Test::Unit::TestCase
  CONFIG = {
    'host' => '127.0.0.1',
    'proxy_host' => nil,
    'proxy_port' => nil,
    'RequestTimeout' => 1,
  }

  include TestNetHTTPUtils

  def test_keep_alive_get_auto_reconnect
    start {|http|
      res = http.get('/')
      http.keep_alive_timeout = 1
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
      sleep 1.5
      assert_nothing_raised {
        res = http.get('/')
      }
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
    }
  end

  def test_server_closed_connection_auto_reconnect
    start {|http|
      res = http.get('/')
      http.keep_alive_timeout = 5
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
      sleep 1.5
      assert_nothing_raised {
        # Net::HTTP should detect the closed connection before attempting the
        # request, since post requests cannot be retried.
        res = http.post('/', 'query=foo', 'content-type' => 'application/x-www-form-urlencoded')
      }
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
    }
  end

  def test_keep_alive_get_auto_retry
    start {|http|
      res = http.get('/')
      http.keep_alive_timeout = 5
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
      sleep 1.5
      res = http.get('/')
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
    }
  end

  class MockSocket
    attr_reader :count
    def initialize(success_after: nil)
      @success_after = success_after
      @count = 0
    end
    def close
    end
    def closed?
    end
    def write(_)
    end
    def readline
      @count += 1
      if @success_after && @success_after <= @count
        "HTTP/1.1 200 OK"
      else
        raise Errno::ECONNRESET
      end
    end
    def readuntil(*_)
      ""
    end
    def read_all(_)
    end
  end

  def test_http_retry_success
    start {|http|
      socket = MockSocket.new(success_after: 10)
      http.instance_variable_get(:@socket).close
      http.instance_variable_set(:@socket, socket)
      assert_equal 0, socket.count
      http.max_retries = 10
      res = http.get('/')
      assert_equal 10, socket.count
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
    }
  end

  def test_http_retry_failed
    start {|http|
      socket = MockSocket.new
      http.instance_variable_get(:@socket).close
      http.instance_variable_set(:@socket, socket)
      http.max_retries = 10
      assert_raise(Errno::ECONNRESET){ http.get('/') }
      assert_equal 11, socket.count
    }
  end

  def test_keep_alive_server_close
    def @server.run(sock)
      sock.close
    end

    start {|http|
      assert_raise(EOFError, Errno::ECONNRESET, IOError) {
        http.get('/')
      }
    }
  end
end

class TestNetHTTPLocalBind < Test::Unit::TestCase
  CONFIG = {
    'host' => 'localhost',
    'proxy_host' => nil,
    'proxy_port' => nil,
  }

  include TestNetHTTPUtils

  def test_bind_to_local_host
    @server.mount_proc('/show_ip') { |req, res| res.body = req.remote_ip }

    http = Net::HTTP.new(config('host'), config('port'))
    http.local_host = Addrinfo.tcp(config('host'), config('port')).ip_address
    assert_not_nil(http.local_host)
    assert_nil(http.local_port)

    res = http.get('/show_ip')
    assert_equal(http.local_host, res.body)
  end

  def test_bind_to_local_port
    @server.mount_proc('/show_port') { |req, res| res.body = req.peeraddr[1].to_s }

    http = Net::HTTP.new(config('host'), config('port'))
    http.local_host = Addrinfo.tcp(config('host'), config('port')).ip_address
    http.local_port = Addrinfo.tcp(config('host'), 0).bind {|s|
      s.local_address.ip_port.to_s
    }
    assert_not_nil(http.local_host)
    assert_not_nil(http.local_port)

    res = http.get('/show_port')
    assert_equal(http.local_port, res.body)
  end
end

