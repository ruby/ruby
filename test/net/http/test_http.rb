# $Id$

require 'test/unit'
require 'net/http'
require 'webrick'
require 'webrick/httpservlet/abstract'
require 'stringio'

module TestNetHTTP_version_1_1_methods

  def test_s_get
    assert_equal $test_net_http_data,
        Net::HTTP.get(config('host'), '/', config('port'))
  end

  def test_head
    start {|http|
      res = http.head('/')
      assert_kind_of Net::HTTPResponse, res
      assert_equal $test_net_http_data_type, res['Content-Type']
      assert_equal $test_net_http_data.size, res['Content-Length'].to_i
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
    res, body = *http.get('/')
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    assert_kind_of String, body
    assert_not_nil res['content-length']
    assert_equal $test_net_http_data.size, res['content-length'].to_i
    assert_equal $test_net_http_data_type, res['Content-Type']
    assert_equal $test_net_http_data.size, body.size
    assert_equal $test_net_http_data, body
    assert_equal $test_net_http_data.size, res.body.size
    assert_equal $test_net_http_data, res.body
  end

  def _test_get__iter(http)
    buf = ''
    res, body = http.get('/') {|s| buf << s }
    assert_kind_of Net::HTTPResponse, res
    # assert_kind_of String, res.body
    # assert_kind_of String, body
    assert_not_nil res['content-length']
    assert_equal $test_net_http_data.size, res['content-length'].to_i
    assert_equal $test_net_http_data_type, res['Content-Type']
    assert_equal $test_net_http_data.size, buf.size
    assert_equal $test_net_http_data, buf
    # assert_equal $test_net_http_data.size, res.body.size
    # assert_equal $test_net_http_data, res.body
  end

  def _test_get__chunked(http)
    buf = ''
    res, body = *http.get('/') {|s| buf << s }
    assert_kind_of Net::HTTPResponse, res
    # assert_kind_of String, res.body
    # assert_kind_of String, body
    assert_not_nil res['content-length']
    assert_equal $test_net_http_data.size, res['content-length'].to_i
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
  end

  def test_get__implicit_start
    res, body = *new().get('/')
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, body
    assert_kind_of String, res.body
    assert_not_nil res['content-length']
    assert_equal $test_net_http_data_type, res['Content-Type']
    assert_equal $test_net_http_data.size, res.body.size
    assert_equal $test_net_http_data, res.body
  end

  def test_get2
    start {|http|
      http.get2('/') {|res|
        assert_kind_of Net::HTTPResponse, res
        assert_kind_of Net::HTTPResponse, res.header
        assert_not_nil res['content-length']
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
    }
  end

  def _test_post__base(http)
    uheader = {}
    uheader['Accept'] = 'application/octet-stream'
    data = 'post data'
    res, body = http.post('/', data)
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, body
    assert_kind_of String, res.body
    assert_equal data, body
    assert_equal data, res.body
    assert_equal data, res.entity
  end

  def _test_post__file(http)
    data = 'post data'
    f = StringIO.new
    http.post('/', data, nil, f)
    assert_equal data, f.string
  end

end


module TestNetHTTP_version_1_2_methods

  def test_request
    start {|http|
      _test_request__GET http
      _test_request__file http
      # _test_request__range http   # WEBrick does not support Range: header.
      _test_request__HEAD http
      _test_request__POST http
      _test_request__stream_body http
    }
  end

  def _test_request__GET(http)
    req = Net::HTTP::Get.new('/')
    http.request(req) {|res|
      assert_kind_of Net::HTTPResponse, res
      assert_kind_of String, res.body
      assert_not_nil res['content-length']
      assert_equal $test_net_http_data.size, res['content-length'].to_i
      assert_equal $test_net_http_data.size, res.body.size
      assert_equal $test_net_http_data, res.body
    }
  end

  def _test_request__file(http)
    req = Net::HTTP::Get.new('/')
    http.request(req) {|res|
      assert_kind_of Net::HTTPResponse, res
      assert_not_nil res['content-length']
      assert_equal $test_net_http_data.size, res['content-length'].to_i
      f = StringIO.new
      res.read_body f
      assert_equal $test_net_http_data.size, f.string.size
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
      assert_not_nil res['content-length']
      assert_equal $test_net_http_data.size, res['content-length'].to_i
      assert_nil res.body
    }
  end

  def _test_request__POST(http)
    data = 'post data'
    req = Net::HTTP::Post.new('/')
    req['Accept'] = $test_net_http_data_type
    http.request(req, data) {|res|
      assert_kind_of Net::HTTPResponse, res
      assert_equal data.size, res['content-length'].to_i
      assert_kind_of String, res.body
      assert_equal data, res.body
    }
  end

  def _test_request__stream_body(http)
    req = Net::HTTP::Post.new('/')
    data = $test_net_http_data
    req.content_length = data.size
    req.body_stream = StringIO.new(data)
    res = http.request(req)
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    assert_equal data.size, res.body.size
    assert_equal data, res.body
  end

  def test_send_request
    start {|http|
      _test_send_request__GET http
      _test_send_request__POST http
    }
  end

  def _test_send_request__GET(http)
    res = http.send_request('GET', '/')
    assert_kind_of Net::HTTPResponse, res
    assert_equal $test_net_http_data.size, res['content-length'].to_i
    assert_kind_of String, res.body
    assert_equal $test_net_http_data, res.body
  end
  
  def _test_send_request__POST(http)
    data = 'aaabbb cc ddddddddddd lkjoiu4j3qlkuoa'
    res = http.send_request('POST', '/', data)
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    assert_equal data.size, res.body.size
    assert_equal data, res.body
  end
end


module TestNetHTTPUtils
  def start(&block)
    new().start(&block)
  end

  def new
    klass = Net::HTTP::Proxy(config('proxy_host'), config('proxy_port'))
    http = klass.new(config('host'), config('port'))
    http.set_debug_output logfile()
    http
  end

  def config(key)
    self.class::CONFIG[key]
  end

  def logfile
    $DEBUG ? $stderr : NullWriter.new
  end

  def setup
    spawn_server
  end

  def teardown
    # resume global state
    Net::HTTP.version_1_2
  end

  def spawn_server
    return if $test_net_http_server_running
    server = WEBrick::HTTPServer.new(
      :BindAddress => config('host'),
      :Port => config('port'),
      :Logger => WEBrick::Log.new(NullWriter.new),
      :AccessLog => []
    )
    server.mount '/', Servlet
    Signal.trap(:INT) {
      server.shutdown
    }
    Thread.fork {
      server.start
    }
    n_try_max = 5
    begin
      TCPSocket.open(config('host'), config('port')).close
    rescue Errno::ECONNREFUSED
      sleep 0.2
      n_try_max -= 1
      raise 'cannot spawn server; give up' if n_try_max < 0
      retry
    end
    $test_net_http_server_running = true
  end

  $test_net_http = nil
  $test_net_http_data = (0...256).to_a.map {|i| i.chr }.join('') * 64
  $test_net_http_data_type = 'application/octet-stream'

  class Servlet < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(req, res)
      res['Content-Type'] = $test_net_http_data_type
      res.body = $test_net_http_data
    end

    def do_POST(req, res)
      res['Content-Type'] = req['Content-Type']
      res.body = req.body
    end
  end

  class NullWriter
    def <<(s) end
    def puts(*args) end
    def print(*args) end
    def printf(*args) end
  end
end

class TestNetHTTP_version_1_1 < Test::Unit::TestCase
  CONFIG = {
    'host' => '127.0.0.1',
    'port' => 10081,
    'proxy_host' => nil,
    'proxy_port' => nil,
  }

  include TestNetHTTPUtils
  include TestNetHTTP_version_1_1_methods

  def new
    Net::HTTP.version_1_1
    super
  end
end

class TestNetHTTP_v1_2 < Test::Unit::TestCase
  CONFIG = {
    'host' => '127.0.0.1',
    'port' => 10081,
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
end

=begin
class TestNetHTTP_proxy < Test::Unit::TestCase
  CONFIG = {
    'host' => '127.0.0.1',
    'port' => 10081,
    'proxy_host' => '127.0.0.1',
    'proxy_port' => 10082,
  }

  include TestNetHTTPUtils
  include TestNetHTTP_version_1_1_methods
  include TestNetHTTP_version_1_2_methods

  def new
    Net::HTTP.version_1_2
    super
  end
end
=end
