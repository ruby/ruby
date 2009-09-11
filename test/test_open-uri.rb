require 'test/unit'
require 'open-uri'
require 'webrick'
require 'webrick/httpproxy'
require 'zlib'

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
        yield srv, dr, "http://#{host}:#{port}"
      ensure
        srv.shutdown
      end
    }
  end

  def test_200
    with_http {|srv, dr, url|
      open("#{dr}/foo200", "w") {|f| f << "foo200" }
      open("#{url}/foo200") {|f|
        assert_equal("200", f.status[0])
        assert_equal("foo200", f.read)
      }
    }
  end

  def test_200big
    with_http {|srv, dr, url|
      content = "foo200big"*10240
      open("#{dr}/foo200big", "w") {|f| f << content }
      open("#{url}/foo200big") {|f|
        assert_equal("200", f.status[0])
        assert_equal(content, f.read)
      }
    }
  end

  def test_404
    with_http {|srv, dr, url|
      exc = assert_raise(OpenURI::HTTPError) { open("#{url}/not-exist") {} }
      assert_equal("404", exc.io.status[0])
    }
  end

  def test_open_uri
    with_http {|srv, dr, url|
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
    with_http {|srv, dr, url|
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
    with_http {|srv, dr, url|
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
    with_http {|srv, dr, url|
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
        open("#{url}/proxy", :proxy=>URI("http://#{p_host}:#{p_port}/")) {|f|
          assert_equal("200", f.status[0])
          assert_equal("proxy", f.read)
        }
        open("#{url}/proxy", :proxy=>nil) {|f|
          assert_equal("200", f.status[0])
          assert_equal("proxy", f.read)
        }
        assert_raise(ArgumentError) {
          open("#{url}/proxy", :proxy=>:invalid) {}
        }
      ensure
        prxy.shutdown
      end
    }
  end

  def test_proxy_http_basic_authentication
    with_http {|srv, dr, url|
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

  def test_redirect
    with_http {|srv, dr, url|
      srv.mount_proc("/r1/") {|req, res| res.status = 301; res["location"] = "#{url}/r2"; res.body = "r1" }
      srv.mount_proc("/r2/") {|req, res| res.body = "r2" }
      srv.mount_proc("/to-file/") {|req, res| res.status = 301; res["location"] = "file:///foo" }
      open("#{url}/r1/") {|f|
        assert_equal("#{url}/r2", f.base_uri.to_s)
        assert_equal("r2", f.read)
      }
      assert_raise(OpenURI::HTTPRedirect) { open("#{url}/r1/", :redirect=>false) {} }
      assert_raise(RuntimeError) { open("#{url}/to-file/") {} }
    }
  end

  def test_redirect_auth
    with_http {|srv, dr, url|
      srv.mount_proc("/r1/") {|req, res| res.status = 301; res["location"] = "#{url}/r2" }
      srv.mount_proc("/r2/") {|req, res|
        if req["Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
          raise WEBrick::HTTPStatus::Unauthorized
        end
        res.body = "r2"
      }
      exc = assert_raise(OpenURI::HTTPError) { open("#{url}/r2/") {} }
      assert_equal("401", exc.io.status[0])
      open("#{url}/r2/", :http_basic_authentication=>['user', 'pass']) {|f|
        assert_equal("r2", f.read)
      }
      exc = assert_raise(OpenURI::HTTPError) { open("#{url}/r1/", :http_basic_authentication=>['user', 'pass']) {} }
      assert_equal("401", exc.io.status[0])
    }
  end

  def test_userinfo
    if "1.9.0" <= RUBY_VERSION
      assert_raise(ArgumentError) { open("http://user:pass@127.0.0.1/") {} }
    end
  end

  def test_progress
    with_http {|srv, dr, url|
      content = "a" * 10000
      srv.mount_proc("/data/") {|req, res| res.body = content }
      length = []
      progress = []
      open("#{url}/data/",
           :content_length_proc => lambda {|n| length << n },
           :progress_proc => lambda {|n| progress << n },
          ) {|f|
        assert_equal(1, length.length)
        assert_equal(content.length, length[0])
        assert_equal(content.length, progress.inject(&:+))
        assert_equal(content, f.read)
      }
    }
  end

  def test_progress_chunked
    with_http {|srv, dr, url|
      content = "a" * 10000
      srv.mount_proc("/data/") {|req, res| res.body = content; res.chunked = true }
      length = []
      progress = []
      open("#{url}/data/",
           :content_length_proc => lambda {|n| length << n },
           :progress_proc => lambda {|n| progress << n },
          ) {|f|
        assert_equal(1, length.length)
        assert_equal(nil, length[0])
        assert_equal(content.length, progress.inject(&:+))
        assert_equal(content, f.read)
      }
    }
  end

  def test_uri_read
    with_http {|srv, dr, url|
      open("#{dr}/uriread", "w") {|f| f << "uriread" }
      data = URI("#{url}/uriread").read
      assert_equal("200", data.status[0])
      assert_equal("uriread", data)
    }
  end

  def test_encoding
    with_http {|srv, dr, url|
      content_u8 = "\u3042"
      content_ej = "\xa2\xa4".force_encoding("euc-jp")
      srv.mount_proc("/u8/") {|req, res| res.body = content_u8; res['content-type'] = 'text/plain; charset=utf-8' }
      srv.mount_proc("/ej/") {|req, res| res.body = content_ej; res['content-type'] = 'TEXT/PLAIN; charset=EUC-JP' }
      srv.mount_proc("/nc/") {|req, res| res.body = "aa"; res['content-type'] = 'Text/Plain' }
      open("#{url}/u8/") {|f|
        assert_equal(content_u8, f.read)
        assert_equal("text/plain", f.content_type)
        assert_equal("utf-8", f.charset)
      }
      open("#{url}/ej/") {|f|
        assert_equal(content_ej, f.read)
        assert_equal("text/plain", f.content_type)
        assert_equal("euc-jp", f.charset)
      }
      open("#{url}/nc/") {|f|
        assert_equal("aa", f.read)
        assert_equal("text/plain", f.content_type)
        assert_equal("iso-8859-1", f.charset)
        assert_equal("unknown", f.charset { "unknown" })
      }
    }
  end

  def test_last_modified
    with_http {|srv, dr, url|
      srv.mount_proc("/data/") {|req, res| res.body = "foo"; res['last-modified'] = 'Fri, 07 Aug 2009 06:05:04 GMT' }
      open("#{url}/data/") {|f|
        assert_equal("foo", f.read)
        assert_equal(Time.utc(2009,8,7,6,5,4), f.last_modified)
      }
    }
  end

  def test_content_encoding
    with_http {|srv, dr, url|
      content = "abc" * 10000
      Zlib::GzipWriter.wrap(StringIO.new(content_gz="".force_encoding("ascii-8bit"))) {|z| z.write content }
      srv.mount_proc("/data/") {|req, res| res.body = content_gz; res['content-encoding'] = 'gzip' }
      srv.mount_proc("/data2/") {|req, res| res.body = content_gz; res['content-encoding'] = 'gzip'; res.chunked = true }
      srv.mount_proc("/noce/") {|req, res| res.body = content_gz }
      open("#{url}/data/") {|f|
        assert_equal ['gzip'], f.content_encoding
        assert_equal(content_gz, f.read.force_encoding("ascii-8bit"))
      }
      open("#{url}/data2/") {|f|
        assert_equal ['gzip'], f.content_encoding
        assert_equal(content_gz, f.read.force_encoding("ascii-8bit"))
      }
      open("#{url}/noce/") {|f|
        assert_equal [], f.content_encoding
        assert_equal(content_gz, f.read.force_encoding("ascii-8bit"))
      }
    }
  end

end

