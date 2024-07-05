# frozen_string_literal: true
require 'test/unit'
require 'open-uri'
require 'stringio'
require_relative 'utils'
begin
  require 'zlib'
rescue LoadError
end

class TestOpenURI < Test::Unit::TestCase
  include TestOpenURIUtils

  def test_200_uri_open
    with_http {|srv, url|
      srv.mount_proc("/urifoo200", lambda { |req, res| res.body = "urifoo200" } )
      URI.open("#{url}/urifoo200") {|f|
        assert_equal("200", f.status[0])
        assert_equal("urifoo200", f.read)
      }
    }
  end

  def test_200
    with_http {|srv, url|
      srv.mount_proc("/foo200", lambda { |req, res| res.body = "foo200" } )
      URI.open("#{url}/foo200") {|f|
        assert_equal("200", f.status[0])
        assert_equal("foo200", f.read)
      }
    }
  end

  def test_200big
    with_http {|srv, url|
      content = "foo200big"*10240
      srv.mount_proc("/foo200big", lambda { |req, res| res.body = content } )
      URI.open("#{url}/foo200big") {|f|
        assert_equal("200", f.status[0])
        assert_equal(content, f.read)
      }
    }
  end

  def test_404
    log_tester = lambda {|server_log|
      assert_equal(1, server_log.length)
      assert_match(%r{ERROR `/not-exist' not found}, server_log[0])
    }
    with_http(log_tester) {|srv, url, server_thread, server_log|
      exc = assert_raise(OpenURI::HTTPError) { URI.open("#{url}/not-exist") {} }
      assert_equal("404", exc.io.status[0])
    }
  end

  def test_open_uri
    with_http {|srv, url|
      srv.mount_proc("/foo_ou", lambda { |req, res| res.body = "foo_ou" } )
      u = URI("#{url}/foo_ou")
      URI.open(u) {|f|
        assert_equal("200", f.status[0])
        assert_equal("foo_ou", f.read)
      }
    }
  end

  def test_open_too_many_arg
    assert_raise(ArgumentError) { URI.open("http://192.0.2.1/tma", "r", 0666, :extra) {} }
  end

  def test_read_timeout
    TCPServer.open("127.0.0.1", 0) {|serv|
      port = serv.addr[1]
      th = Thread.new {
        sock = serv.accept
        begin
          req = sock.gets("\r\n\r\n")
          assert_match(%r{\AGET /foo/bar }, req)
          sock.print "HTTP/1.0 200 OK\r\n"
          sock.print "Content-Length: 4\r\n\r\n"
          sleep 1
          sock.print "ab\r\n"
        ensure
          sock.close
        end
      }
      begin
        assert_raise(Net::ReadTimeout) { URI("http://127.0.0.1:#{port}/foo/bar").read(:read_timeout=>0.1) }
      ensure
        Thread.kill(th)
        th.join
      end
    }
  end

  def test_open_timeout
    assert_raise(Net::OpenTimeout) do
      URI("http://example.com/").read(open_timeout: 0.000001)
    end if false # avoid external resources in tests

    with_http {|srv, url|
      url += '/'
      srv.mount_proc('/', lambda { |_, res| res.body = 'hi' })
      begin
        URI(url).read(open_timeout: 0.000001)
      rescue Net::OpenTimeout
        # not guaranteed to fire, since the kernel negotiates the
        # TCP connection even if the server thread is sleeping
      end
      assert_equal 'hi', URI(url).read(open_timeout: 60), 'should not timeout'
    }
  end

  def test_invalid_option
    assert_raise(ArgumentError) { URI.open("http://127.0.0.1/", :invalid_option=>true) {} }
  end

  def test_pass_keywords
    begin
      f = URI.open(File::NULL, mode: 0666)
      assert_kind_of File, f
    ensure
      f&.close
    end

    o = Object.new
    def o.open(foo: ) foo end
    assert_equal 1, URI.open(o, foo: 1)
  end

  def test_mode
    with_http {|srv, url|
      srv.mount_proc("/mode", lambda { |req, res| res.body = "mode" } )
      URI.open("#{url}/mode", "r") {|f|
        assert_equal("200", f.status[0])
        assert_equal("mode", f.read)
      }
      URI.open("#{url}/mode", "r", 0600) {|f|
        assert_equal("200", f.status[0])
        assert_equal("mode", f.read)
      }
      assert_raise(ArgumentError) { URI.open("#{url}/mode", "a") {} }
      URI.open("#{url}/mode", "r:us-ascii") {|f|
        assert_equal(Encoding::US_ASCII, f.read.encoding)
      }
      URI.open("#{url}/mode", "r:utf-8") {|f|
        assert_equal(Encoding::UTF_8, f.read.encoding)
      }
      assert_raise(ArgumentError) { URI.open("#{url}/mode", "r:invalid-encoding") {} }
    }
  end

  def test_without_block
    with_http {|srv, url|
      srv.mount_proc("/without_block", lambda { |req, res| res.body = "without_block" } )
      begin
        f = URI.open("#{url}/without_block")
        assert_equal("200", f.status[0])
        assert_equal("without_block", f.read)
      ensure
        f.close if f && !f.closed?
      end
    }
  end

  def test_close_in_block_small
    with_http {|srv, url|
      srv.mount_proc("/close200", lambda { |req, res| res.body = "close200" } )
      assert_nothing_raised {
        URI.open("#{url}/close200") {|f|
          f.close
        }
      }
    }
  end

  def test_close_in_block_big
    with_http {|srv, url|
      content = "close200big"*10240
      srv.mount_proc("/close200big", lambda { |req, res| res.body = content } )
      assert_nothing_raised {
        URI.open("#{url}/close200big") {|f|
          f.close
        }
      }
    }
  end

  def test_header
    myheader1 = 'barrrr'
    myheader2 = nil
    with_http {|srv, url|
      srv.mount_proc("/h/", lambda {|req, res| myheader2 = req['myheader']; res.body = "foo" } )
      URI.open("#{url}/h/", 'MyHeader'=>myheader1) {|f|
        assert_equal("foo", f.read)
        assert_equal(myheader1, myheader2)
      }
    }
  end

  def test_multi_proxy_opt
    assert_raise(ArgumentError) {
      URI.open("http://127.0.0.1/", :proxy_http_basic_authentication=>true, :proxy=>true) {}
    }
  end

  def test_non_http_proxy
    assert_raise(RuntimeError) {
      URI.open("http://127.0.0.1/", :proxy=>URI("ftp://127.0.0.1/")) {}
    }
  end

  def test_redirect
    with_http {|srv, url|
      srv.mount_proc("/r1/", lambda {|req, res| res.status = 301; res["location"] = "#{url}/r2"; res.body = "r1" } )
      srv.mount_proc("/r2/", lambda {|req, res| res.body = "r2" } )
      srv.mount_proc("/to-file/", lambda {|req, res| res.status = 301; res["location"] = "file:///foo" } )
      URI.open("#{url}/r1/") {|f|
        assert_equal("#{url}/r2", f.base_uri.to_s)
        assert_equal("r2", f.read)
      }
      assert_raise(OpenURI::HTTPRedirect) { URI.open("#{url}/r1/", :redirect=>false) {} }
      assert_raise(RuntimeError) { URI.open("#{url}/to-file/") {} }
    }
  end

  def test_redirect_loop
    with_http {|srv, url|
      srv.mount_proc("/r1/", lambda {|req, res| res.status = 301; res["location"] = "#{url}/r2"; res.body = "r1" } )
      srv.mount_proc("/r2/", lambda {|req, res| res.status = 301; res["location"] = "#{url}/r1"; res.body = "r2" } )
      assert_raise(RuntimeError) { URI.open("#{url}/r1/") {} }
    }
  end

  def test_redirect_relative
    TCPServer.open("127.0.0.1", 0) {|serv|
      port = serv.addr[1]
      th = Thread.new {
        sock = serv.accept
        begin
          req = sock.gets("\r\n\r\n")
          assert_match(%r{\AGET /foo/bar }, req)
          sock.print "HTTP/1.0 302 Found\r\n"
          sock.print "Location: ../baz\r\n\r\n"
        ensure
          sock.close
        end
        sock = serv.accept
        begin
          req = sock.gets("\r\n\r\n")
          assert_match(%r{\AGET /baz }, req)
          sock.print "HTTP/1.0 200 OK\r\n"
          sock.print "Content-Length: 4\r\n\r\n"
          sock.print "ab\r\n"
        ensure
          sock.close
        end
      }
      begin
        content = URI("http://127.0.0.1:#{port}/foo/bar").read
        assert_equal("ab\r\n", content)
      ensure
        Thread.kill(th)
        th.join
      end
    }
  end

  def test_redirect_invalid
    TCPServer.open("127.0.0.1", 0) {|serv|
      port = serv.addr[1]
      th = Thread.new {
        sock = serv.accept
        begin
          req = sock.gets("\r\n\r\n")
          assert_match(%r{\AGET /foo/bar }, req)
          sock.print "HTTP/1.0 302 Found\r\n"
          sock.print "Location: ::\r\n\r\n"
        ensure
          sock.close
        end
      }
      begin
        assert_raise(OpenURI::HTTPError) {
          URI("http://127.0.0.1:#{port}/foo/bar").read
        }
      ensure
        Thread.kill(th)
        th.join
      end
    }
  end

  def setup_redirect_auth(srv, url)
    srv.mount_proc("/r1/", lambda {|req, res|
      res.status = 301
      res["location"] = "#{url}/r2"
    })
    srv.mount_proc("/r2/", lambda {|req, res|
      if req["Authorization"] != "Basic #{['user:pass'].pack('m').chomp}"
        raise Unauthorized
      end
      res.body = "r2"
    })
  end

  def test_redirect_auth_success
    with_http {|srv, url|
      setup_redirect_auth(srv, url)
      URI.open("#{url}/r2/", :http_basic_authentication=>['user', 'pass']) {|f|
        assert_equal("r2", f.read)
      }
    }
  end

  def test_redirect_auth_failure_r2
    log_tester = lambda {|server_log|
      assert_equal(1, server_log.length)
      assert_match(/ERROR Unauthorized/, server_log[0])
    }
    with_http(log_tester) {|srv, url, server_thread, server_log|
      setup_redirect_auth(srv, url)
      exc = assert_raise(OpenURI::HTTPError) { URI.open("#{url}/r2/") {} }
      assert_equal("401", exc.io.status[0])
    }
  end

  def test_redirect_auth_failure_r1
    log_tester = lambda {|server_log|
      assert_equal(1, server_log.length)
      assert_match(/ERROR Unauthorized/, server_log[0])
    }
    with_http(log_tester) {|srv, url, server_thread, server_log|
      setup_redirect_auth(srv, url)
      exc = assert_raise(OpenURI::HTTPError) { URI.open("#{url}/r1/", :http_basic_authentication=>['user', 'pass']) {} }
      assert_equal("401", exc.io.status[0])
    }
  end

  def test_max_redirects_success
    with_http {|srv, url|
      srv.mount_proc("/r1/", lambda {|req, res| res.status = 301; res["location"] = "#{url}/r2"; res.body = "r1" } )
      srv.mount_proc("/r2/", lambda {|req, res| res.status = 301; res["location"] = "#{url}/r3"; res.body = "r2" } )
      srv.mount_proc("/r3/", lambda {|req, res| res.body = "r3" } )
      URI.open("#{url}/r1/", max_redirects: 2) { |f| assert_equal("r3", f.read) }
    }
  end

  def test_max_redirects_too_many
    with_http {|srv, url|
      srv.mount_proc("/r1/", lambda {|req, res| res.status = 301; res["location"] = "#{url}/r2"; res.body = "r1" } )
      srv.mount_proc("/r2/", lambda {|req, res| res.status = 301; res["location"] = "#{url}/r3"; res.body = "r2" } )
      srv.mount_proc("/r3/", lambda {|req, res| res.body = "r3" } )
      exc = assert_raise(OpenURI::TooManyRedirects) { URI.open("#{url}/r1/", max_redirects: 1) {} }
      assert_equal("Too many redirects", exc.message)
    }
  end

  def test_userinfo
    assert_raise(ArgumentError) { URI.open("http://user:pass@127.0.0.1/") {} }
  end

  def test_progress
    with_http {|srv, url|
      content = "a" * 100000
      srv.mount_proc("/data/", lambda {|req, res| res.body = content })
      length = []
      progress = []
      URI.open("#{url}/data/",
           :content_length_proc => lambda {|n| length << n },
           :progress_proc => lambda {|n| progress << n }
          ) {|f|
        assert_equal(1, length.length)
        assert_equal(content.length, length[0])
        assert(progress.length>1,"maybe test is wrong")
        assert(progress.sort == progress,"monotone increasing expected but was\n#{progress.inspect}")
        assert_equal(content.length, progress[-1])
        assert_equal(content, f.read)
      }
    }
  end

  def test_progress_chunked
    with_http {|srv, url|
      content = "a" * 100000
      srv.mount_proc("/data/", lambda {|req, res| res.body = content; res.chunked = true } )
      length = []
      progress = []
      URI.open("#{url}/data/",
           :content_length_proc => lambda {|n| length << n },
           :progress_proc => lambda {|n| progress << n }
          ) {|f|
        assert_equal(1, length.length)
        assert_equal(nil, length[0])
        assert(progress.length>1,"maybe test is wrong")
        assert(progress.sort == progress,"monotone increasing expected but was\n#{progress.inspect}")
        assert_equal(content.length, progress[-1])
        assert_equal(content, f.read)
      }
    }
  end

  def test_uri_read
    with_http {|srv, url|
      srv.mount_proc("/uriread", lambda { |req, res| res.body = "uriread" } )
      data = URI("#{url}/uriread").read
      assert_equal("200", data.status[0])
      assert_equal("uriread", data)
    }
  end

  def test_encoding
    with_http {|srv, url|
      content_u8 = "\u3042"
      content_ej = "\xa2\xa4".dup.force_encoding("euc-jp")
      srv.mount_proc("/u8/", lambda {|req, res| res.body = content_u8; res['content-type'] = 'text/plain; charset=utf-8' } )
      srv.mount_proc("/ej/", lambda {|req, res| res.body = content_ej; res['content-type'] = 'TEXT/PLAIN; charset=EUC-JP' } )
      srv.mount_proc("/nc/", lambda {|req, res| res.body = "aa"; res['content-type'] = 'Text/Plain' } )
      URI.open("#{url}/u8/") {|f|
        assert_equal(content_u8, f.read)
        assert_equal("text/plain", f.content_type)
        assert_equal("utf-8", f.charset)
      }
      URI.open("#{url}/ej/") {|f|
        assert_equal(content_ej, f.read)
        assert_equal("text/plain", f.content_type)
        assert_equal("euc-jp", f.charset)
        assert_equal(Encoding::EUC_JP, f.read.encoding)
      }
      URI.open("#{url}/ej/", 'r:utf-8') {|f|
        # override charset with encoding option
        assert_equal(content_ej.dup.force_encoding('utf-8'), f.read)
        assert_equal("text/plain", f.content_type)
        assert_equal("euc-jp", f.charset)
        assert_equal(Encoding::UTF_8, f.read.encoding)
      }
      URI.open("#{url}/ej/", :encoding=>'utf-8') {|f|
        # override charset with encoding option
        assert_equal(content_ej.dup.force_encoding('utf-8'), f.read)
        assert_equal("text/plain", f.content_type)
        assert_equal("euc-jp", f.charset)
        assert_equal(Encoding::UTF_8, f.read.encoding)
      }
      assert_raise(ArgumentError) {
        URI.open("#{url}/ej/", 'r:utf-8', :encoding=>'utf-8') {|f| }
      }
      URI.open("#{url}/nc/") {|f|
        assert_equal("aa", f.read)
        assert_equal("text/plain", f.content_type)
        assert_equal("utf-8", f.charset)
        assert_equal("unknown", f.charset { "unknown" })
      }
    }
  end

  def test_quoted_attvalue
    with_http {|srv, url|
      content_u8 = "\u3042"
      srv.mount_proc("/qu8/", lambda {|req, res| res.body = content_u8; res['content-type'] = 'text/plain; charset="utf\-8"' } )
      URI.open("#{url}/qu8/") {|f|
        assert_equal(content_u8, f.read)
        assert_equal("text/plain", f.content_type)
        assert_equal("utf-8", f.charset)
      }
    }
  end

  def test_last_modified
    with_http {|srv, url|
      srv.mount_proc("/data/", lambda {|req, res| res.body = "foo"; res['last-modified'] = 'Fri, 07 Aug 2009 06:05:04 GMT' } )
      URI.open("#{url}/data/") {|f|
        assert_equal("foo", f.read)
        assert_equal(Time.utc(2009,8,7,6,5,4), f.last_modified)
      }
    }
  end

  def test_content_encoding
    with_http {|srv, url|
      content = "abc" * 10000
      Zlib::GzipWriter.wrap(StringIO.new(content_gz="".b)) {|z| z.write content }
      srv.mount_proc("/data/", lambda {|req, res| res.body = content_gz; res['content-encoding'] = 'gzip' } )
      srv.mount_proc("/data2/", lambda {|req, res| res.body = content_gz; res['content-encoding'] = 'gzip'; res.chunked = true } )
      srv.mount_proc("/noce/", lambda {|req, res| res.body = content_gz } )
      URI.open("#{url}/data/") {|f|
        assert_equal [], f.content_encoding
        assert_equal(content, f.read)
      }
      URI.open("#{url}/data2/") {|f|
        assert_equal [], f.content_encoding
        assert_equal(content, f.read)
      }
      URI.open("#{url}/noce/") {|f|
        assert_equal [], f.content_encoding
        assert_equal(content_gz, f.read.force_encoding("ascii-8bit"))
      }
    }
  end if defined?(Zlib::GzipWriter)

  def test_multiple_cookies
    with_http {|srv, url|
      srv.mount_proc("/mcookie/", lambda {|req, res|
        res.cookies << "name1=value1; blabla"
        res.cookies << "name2=value2; blabla"
        res.body = "foo"
      })
      URI.open("#{url}/mcookie/") {|f|
        assert_equal("foo", f.read)
        assert_equal(["name1=value1; blabla", "name2=value2; blabla"],
                     f.metas['set-cookie'].sort)
      }
    }
  end

  # 192.0.2.0/24 is TEST-NET.  [RFC3330]

  def test_meta_init_doesnt_bump_global_constant_state
    omit "RubyVM.stat not defined" unless defined? RubyVM.stat
    omit unless RubyVM.stat.has_key?(:global_constant_state)

    OpenURI::Meta.init(Object.new) # prewarm

    before = RubyVM.stat(:global_constant_state)
    OpenURI::Meta.init(Object.new)
    assert_equal 0, RubyVM.stat(:global_constant_state) - before
  end
end
