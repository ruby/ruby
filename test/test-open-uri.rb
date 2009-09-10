require 'test/unit'
require 'open-uri'
require 'webrick'
require 'webrick/httpproxy'

class TestOpenURI < Test::Unit::TestCase

  def with_http
    Dir.mktmpdir {|dr|
      srv = WEBrick::HTTPServer.new({
        :DocumentRoot => dr,
        :ServerType => Thread,
        :Logger => WEBrick::Log.new(StringIO.new("")),
        :AccessLog => [[StringIO.new(""), ""]],
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, port, _, host = srv.listeners[0].addr
      begin
        th = srv.start
        yield dr, "http://#{host}:#{port}"
      ensure
        srv.shutdown
      end
    }
  end

  def test_200
    with_http {|dr, url|
      open("#{dr}/foo200", "w") {|f| f << "foo200" }
      open("#{url}/foo200") {|f|
        assert_equal("200", f.status[0])
        assert_equal("foo200", f.read)
      }
    }
  end

  def test_404
    with_http {|dr, url|
      exc = assert_raise(OpenURI::HTTPError) { open("#{url}/not-exist") {} }
      assert_equal("404", exc.io.status[0])
    }
  end

  def test_open_uri
    with_http {|dr, url|
      open("#{dr}/foo_ou", "w") {|f| f << "foo_ou" }
      u = URI("#{url}/foo_ou")
      open(u) {|f|
        assert_equal("200", f.status[0])
        assert_equal("foo_ou", f.read)
      }
    }
  end

  def test_invalid_option
    assert_raise(ArgumentError) { open("http://127.0.0.1/", :invalid_option=>true) {} }
  end

  def test_mode
    with_http {|dr, url|
      open("#{dr}/mode", "w") {|f| f << "mode" }
      open("#{url}/mode", "r") {|f|
        assert_equal("200", f.status[0])
        assert_equal("mode", f.read)
      }
      open("#{url}/mode", "r", 0600) {|f|
        assert_equal("200", f.status[0])
        assert_equal("mode", f.read)
      }
      assert_raise(ArgumentError) { open("#{url}/mode", "a") {} }
    }
  end

  def test_without_block
    with_http {|dr, url|
      open("#{dr}/without_block", "w") {|g| g << "without_block" }
      begin
        f = open("#{url}/without_block")
        assert_equal("200", f.status[0])
        assert_equal("without_block", f.read)
      ensure
        f.close
      end
    }
  end

  def test_multi_proxy_opt
    assert_raise(ArgumentError) {
      open("http://127.0.0.1/", :proxy_http_basic_authentication=>true, :proxy=>true) {}
    }
  end

  def test_proxy
    with_http {|dr, url|
      prxy = WEBrick::HTTPProxyServer.new({
                                     :ServerType => Thread,
                                     :Logger => WEBrick::Log.new(StringIO.new("")),
                                     :AccessLog => [[StringIO.new(""), ""]],
                                     :BindAddress => '127.0.0.1',
                                     :Port => 0})
      _, p_port, _, p_host = prxy.listeners[0].addr
      begin
        th = prxy.start
        open("#{dr}/proxy", "w") {|f| f << "proxy" }
        open("#{url}/proxy", :proxy=>"http://#{p_host}:#{p_port}/") {|f|
          assert_equal("200", f.status[0])
          assert_equal("proxy", f.read)
        }
      ensure
        prxy.shutdown
      end
    }
  end

  def test_proxy_http_basic_authentication
    with_http {|dr, url|
      prxy = WEBrick::HTTPProxyServer.new({
        :ServerType => Thread,
        :Logger => WEBrick::Log.new(StringIO.new("")),
        :AccessLog => [[StringIO.new(""), ""]],
        :ProxyAuthProc => lambda {|req, res|
          if req["Proxy-Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
            raise WEBrick::HTTPStatus::ProxyAuthenticationRequired
          end
        },
        :BindAddress => '127.0.0.1',
        :Port => 0})
      _, p_port, _, p_host = prxy.listeners[0].addr
      p_url = "http://#{p_host}:#{p_port}/"
      begin
        th = prxy.start
        open("#{dr}/proxy", "w") {|f| f << "proxy" }
        exc = assert_raise(OpenURI::HTTPError) { open("#{url}/proxy", :proxy=>p_url) {} }
        assert_equal("407", exc.io.status[0])
        open("#{url}/proxy",
            :proxy_http_basic_authentication=>[p_url, "user", "pass"]) {|f|
          assert_equal("200", f.status[0])
          assert_equal("proxy", f.read)
        }
        assert_raise(ArgumentError) {
          open("#{url}/proxy",
              :proxy_http_basic_authentication=>[true, "user", "pass"]) {}
        }
      ensure
        prxy.shutdown
      end
    }
  end

end

