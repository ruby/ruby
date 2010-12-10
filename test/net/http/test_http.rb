# $Id$

require 'test/unit'
require 'net/http'
require 'stringio'
require File.expand_path("utils", File.dirname(__FILE__))

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

  def test_get2
    start {|http|
      http.get2('/') {|res|
        assert_kind_of Net::HTTPResponse, res
        assert_kind_of Net::HTTPResponse, res.header
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
    }
  end

  def _test_post__base(http)
    uheader = {}
    uheader['Accept'] = 'application/octet-stream'
    data = 'post data'
    res = http.post('/', data)
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    assert_equal data, res.body
    assert_equal data, res.entity
  end

  def _test_post__file(http)
    data = 'post data'
    f = StringIO.new
    http.post('/', data, nil, f)
    assert_equal data, f.string
  end

  def test_s_post_form
    res = Net::HTTP.post_form(
              URI.parse("http://#{config('host')}:#{config('port')}/"),
              "a" => "x")
    assert_equal ["a=x"], res.body.split(/[;&]/).sort

    res = Net::HTTP.post_form(
              URI.parse("http://#{config('host')}:#{config('port')}/"),
              "a" => "x",
              "b" => "y")
    assert_equal ["a=x", "b=y"], res.body.split(/[;&]/).sort

    res = Net::HTTP.post_form(
              URI.parse("http://#{config('host')}:#{config('port')}/"),
              "a" => ["x1", "x2"],
              "b" => "y")
    assert_equal ["a=x1", "a=x2", "b=y"], res.body.split(/[;&]/).sort
  end

  def test_patch
    start {|http|
      _test_patch__base http
    }
  end

  def _test_patch__base(http)
    uheader = {}
    uheader['Accept'] = 'application/octet-stream'
    data = 'patch data'
    res = http.patch('/', data)
    assert_kind_of Net::HTTPResponse, res
    assert_kind_of String, res.body
    assert_equal data, res.body
    assert_equal data, res.entity
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
      unless self.is_a?(TestNetHTTP_v1_2_chunked)
        assert_not_nil res['content-length']
        assert_equal $test_net_http_data.size, res['content-length'].to_i
      end
      assert_equal $test_net_http_data.size, res.body.size
      assert_equal $test_net_http_data, res.body
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
    unless self.is_a?(TestNetHTTP_v1_2_chunked)
      assert_equal $test_net_http_data.size, res['content-length'].to_i
    end
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

class TestNetHTTP_v1_2_chunked < Test::Unit::TestCase
  CONFIG = {
    'host' => '127.0.0.1',
    'port' => 10081,
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
    i = 0
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
