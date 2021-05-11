# frozen_string_literal: false
require "test/unit"
require "net/http"
require "webrick"
require "webrick/httpproxy"
begin
  require "webrick/ssl"
  require "net/https"
rescue LoadError
  # test_connect will be skipped
end
require File.expand_path("utils.rb", File.dirname(__FILE__))

class TestWEBrickHTTPProxy < Test::Unit::TestCase
  def teardown
    WEBrick::Utils::TimeoutHandler.terminate
    super
  end

  def test_fake_proxy
    assert_nil(WEBrick::FakeProxyURI.scheme)
    assert_nil(WEBrick::FakeProxyURI.host)
    assert_nil(WEBrick::FakeProxyURI.port)
    assert_nil(WEBrick::FakeProxyURI.path)
    assert_nil(WEBrick::FakeProxyURI.userinfo)
    assert_raise(NoMethodError){ WEBrick::FakeProxyURI.foo }
  end

  def test_proxy
    # Testing GET or POST to the proxy server
    # Note that the proxy server works as the origin server.
    #                    +------+
    #                    V      |
    #  client -------> proxy ---+
    #        GET / POST     GET / POST
    #
    proxy_handler_called = request_handler_called = 0
    config = {
      :ServerName => "localhost.localdomain",
      :ProxyContentHandler => Proc.new{|req, res| proxy_handler_called += 1 },
      :RequestCallback => Proc.new{|req, res| request_handler_called += 1 }
    }
    TestWEBrick.start_httpproxy(config){|server, addr, port, log|
      server.mount_proc("/"){|req, res|
        res.body = "#{req.request_method} #{req.path} #{req.body}"
      }
      http = Net::HTTP.new(addr, port, addr, port)

      req = Net::HTTP::Get.new("/")
      http.request(req){|res|
        assert_equal("1.1 localhost.localdomain:#{port}", res["via"], log.call)
        assert_equal("GET / ", res.body, log.call)
      }
      assert_equal(1, proxy_handler_called, log.call)
      assert_equal(2, request_handler_called, log.call)

      req = Net::HTTP::Head.new("/")
      http.request(req){|res|
        assert_equal("1.1 localhost.localdomain:#{port}", res["via"], log.call)
        assert_nil(res.body, log.call)
      }
      assert_equal(2, proxy_handler_called, log.call)
      assert_equal(4, request_handler_called, log.call)

      req = Net::HTTP::Post.new("/")
      req.body = "post-data"
      req.content_type = "application/x-www-form-urlencoded"
      http.request(req){|res|
        assert_equal("1.1 localhost.localdomain:#{port}", res["via"], log.call)
        assert_equal("POST / post-data", res.body, log.call)
      }
      assert_equal(3, proxy_handler_called, log.call)
      assert_equal(6, request_handler_called, log.call)
    }
  end

  def test_no_proxy
    # Testing GET or POST to the proxy server without proxy request.
    #
    #  client -------> proxy
    #        GET / POST
    #
    proxy_handler_called = request_handler_called = 0
    config = {
      :ServerName => "localhost.localdomain",
      :ProxyContentHandler => Proc.new{|req, res| proxy_handler_called += 1 },
      :RequestCallback => Proc.new{|req, res| request_handler_called += 1 }
    }
    TestWEBrick.start_httpproxy(config){|server, addr, port, log|
      server.mount_proc("/"){|req, res|
        res.body = "#{req.request_method} #{req.path} #{req.body}"
      }
      http = Net::HTTP.new(addr, port)

      req = Net::HTTP::Get.new("/")
      http.request(req){|res|
        assert_nil(res["via"], log.call)
        assert_equal("GET / ", res.body, log.call)
      }
      assert_equal(0, proxy_handler_called, log.call)
      assert_equal(1, request_handler_called, log.call)

      req = Net::HTTP::Head.new("/")
      http.request(req){|res|
        assert_nil(res["via"], log.call)
        assert_nil(res.body, log.call)
      }
      assert_equal(0, proxy_handler_called, log.call)
      assert_equal(2, request_handler_called, log.call)

      req = Net::HTTP::Post.new("/")
      req.content_type = "application/x-www-form-urlencoded"
      req.body = "post-data"
      http.request(req){|res|
        assert_nil(res["via"], log.call)
        assert_equal("POST / post-data", res.body, log.call)
      }
      assert_equal(0, proxy_handler_called, log.call)
      assert_equal(3, request_handler_called, log.call)
    }
  end

  def test_big_bodies
    require 'digest/md5'
    rand_str = File.read(__FILE__)
    rand_str.freeze
    nr = 1024 ** 2 / rand_str.size # bigger works, too
    exp = Digest::MD5.new
    nr.times { exp.update(rand_str) }
    exp = exp.hexdigest
    TestWEBrick.start_httpserver do |o_server, o_addr, o_port, o_log|
      o_server.mount_proc('/') do |req, res|
        case req.request_method
        when 'GET'
          res['content-type'] = 'application/octet-stream'
          if req.path == '/length'
            res['content-length'] = (nr * rand_str.size).to_s
          else
            res.chunked = true
          end
          res.body = ->(socket) { nr.times { socket.write(rand_str) } }
        when 'POST'
          dig = Digest::MD5.new
          req.body { |buf| dig.update(buf); buf.clear }
          res['content-type'] = 'text/plain'
          res['content-length'] = '32'
          res.body = dig.hexdigest
        end
      end

      http = Net::HTTP.new(o_addr, o_port)
      IO.pipe do |rd, wr|
        headers = {
          'Content-Type' => 'application/octet-stream',
          'Transfer-Encoding' => 'chunked',
        }
        post = Net::HTTP::Post.new('/', headers)
        th = Thread.new { nr.times { wr.write(rand_str) }; wr.close }
        post.body_stream = rd
        http.request(post) do |res|
          assert_equal 'text/plain', res['content-type']
          assert_equal 32, res.content_length
          assert_equal exp, res.body
        end
        assert_nil th.value
      end

      TestWEBrick.start_httpproxy do |p_server, p_addr, p_port, p_log|
        http = Net::HTTP.new(o_addr, o_port, p_addr, p_port)
        http.request_get('/length') do |res|
          assert_equal(nr * rand_str.size, res.content_length)
          dig = Digest::MD5.new
          res.read_body { |buf| dig.update(buf); buf.clear }
          assert_equal exp, dig.hexdigest
        end
        http.request_get('/') do |res|
          assert_predicate res, :chunked?
          dig = Digest::MD5.new
          res.read_body { |buf| dig.update(buf); buf.clear }
          assert_equal exp, dig.hexdigest
        end

        IO.pipe do |rd, wr|
          headers = {
            'Content-Type' => 'application/octet-stream',
            'Content-Length' => (nr * rand_str.size).to_s,
          }
          post = Net::HTTP::Post.new('/', headers)
          th = Thread.new { nr.times { wr.write(rand_str) }; wr.close }
          post.body_stream = rd
          http.request(post) do |res|
            assert_equal 'text/plain', res['content-type']
            assert_equal 32, res.content_length
            assert_equal exp, res.body
          end
          assert_nil th.value
        end

        IO.pipe do |rd, wr|
          headers = {
            'Content-Type' => 'application/octet-stream',
            'Transfer-Encoding' => 'chunked',
          }
          post = Net::HTTP::Post.new('/', headers)
          th = Thread.new { nr.times { wr.write(rand_str) }; wr.close }
          post.body_stream = rd
          http.request(post) do |res|
            assert_equal 'text/plain', res['content-type']
            assert_equal 32, res.content_length
            assert_equal exp, res.body
          end
          assert_nil th.value
        end
      end
    end
  end if RUBY_VERSION >= '2.5'

  def test_http10_proxy_chunked
    # Testing HTTP/1.0 client request and HTTP/1.1 chunked response
    # from origin server.
    #                    +------+
    #                    V      |
    #  client -------> proxy ---+
    #           GET          GET
    #           HTTP/1.0     HTTP/1.1
    #           non-chunked  chunked
    #
    proxy_handler_called = request_handler_called = 0
    config = {
      :ServerName => "localhost.localdomain",
      :ProxyContentHandler => Proc.new{|req, res| proxy_handler_called += 1 },
      :RequestCallback => Proc.new{|req, res| request_handler_called += 1 }
    }
    log_tester = lambda {|log, access_log|
      log.reject! {|str|
        %r{WARN  chunked is set for an HTTP/1\.0 request\. \(ignored\)} =~ str
      }
      assert_equal([], log)
    }
    TestWEBrick.start_httpproxy(config, log_tester){|server, addr, port, log|
      body = nil
      server.mount_proc("/"){|req, res|
        body = "#{req.request_method} #{req.path} #{req.body}"
        res.chunked = true
        res.body = -> (socket) { body.each_char {|c| socket.write c } }
      }

      # Don't use Net::HTTP because it uses HTTP/1.1.
      TCPSocket.open(addr, port) {|s|
        s.write "GET / HTTP/1.0\r\nHost: localhost.localdomain\r\n\r\n"
        response = s.read
        assert_equal(body, response[/.*\z/])
      }
    }
  end

  def make_certificate(key, cn)
    subject = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=#{cn}")
    exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
    ]
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = subject
    cert.issuer = subject
    cert.public_key = key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    exts.each {|args| cert.add_extension(ef.create_extension(*args)) }
    cert.sign(key, "sha256")
    return cert
  end if defined?(OpenSSL::SSL)

  def test_connect
    # Testing CONNECT to proxy server
    #
    #  client -----------> proxy -----------> https
    #    1.     CONNECT          establish TCP
    #    2.   ---- establish SSL session --->
    #    3.   ------- GET or POST ---------->
    #
    key = TEST_KEY_RSA2048
    cert = make_certificate(key, "127.0.0.1")
    s_config = {
      :SSLEnable =>true,
      :ServerName => "localhost",
      :SSLCertificate => cert,
      :SSLPrivateKey => key,
    }
    config = {
      :ServerName => "localhost.localdomain",
      :RequestCallback => Proc.new{|req, res|
        assert_equal("CONNECT", req.request_method)
      },
    }
    TestWEBrick.start_httpserver(s_config){|s_server, s_addr, s_port, s_log|
      s_server.mount_proc("/"){|req, res|
        res.body = "SSL #{req.request_method} #{req.path} #{req.body}"
      }
      TestWEBrick.start_httpproxy(config){|server, addr, port, log|
        http = Net::HTTP.new("127.0.0.1", s_port, addr, port)
        http.use_ssl = true
        http.verify_callback = Proc.new do |preverify_ok, store_ctx|
          store_ctx.current_cert.to_der == cert.to_der
        end

        req = Net::HTTP::Get.new("/")
        req["Content-Type"] = "application/x-www-form-urlencoded"
        http.request(req){|res|
          assert_equal("SSL GET / ", res.body, s_log.call + log.call)
        }

        req = Net::HTTP::Post.new("/")
        req["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = "post-data"
        http.request(req){|res|
          assert_equal("SSL POST / post-data", res.body, s_log.call + log.call)
        }
      }
    }
  end if defined?(OpenSSL::SSL)

  def test_upstream_proxy
    # Testing GET or POST through the upstream proxy server
    # Note that the upstream proxy server works as the origin server.
    #                                   +------+
    #                                   V      |
    #  client -------> proxy -------> proxy ---+
    #        GET / POST     GET / POST     GET / POST
    #
    up_proxy_handler_called = up_request_handler_called = 0
    proxy_handler_called = request_handler_called = 0
    up_config = {
      :ServerName => "localhost.localdomain",
      :ProxyContentHandler => Proc.new{|req, res| up_proxy_handler_called += 1},
      :RequestCallback => Proc.new{|req, res| up_request_handler_called += 1}
    }
    TestWEBrick.start_httpproxy(up_config){|up_server, up_addr, up_port, up_log|
      up_server.mount_proc("/"){|req, res|
        res.body = "#{req.request_method} #{req.path} #{req.body}"
      }
      config = {
        :ServerName => "localhost.localdomain",
        :ProxyURI => URI.parse("http://localhost:#{up_port}"),
        :ProxyContentHandler => Proc.new{|req, res| proxy_handler_called += 1},
        :RequestCallback => Proc.new{|req, res| request_handler_called += 1},
      }
      TestWEBrick.start_httpproxy(config){|server, addr, port, log|
        http = Net::HTTP.new(up_addr, up_port, addr, port)

        req = Net::HTTP::Get.new("/")
        http.request(req){|res|
          skip res.message unless res.code == '200'
          via = res["via"].split(/,\s+/)
          assert(via.include?("1.1 localhost.localdomain:#{up_port}"), up_log.call + log.call)
          assert(via.include?("1.1 localhost.localdomain:#{port}"), up_log.call + log.call)
          assert_equal("GET / ", res.body)
        }
        assert_equal(1, up_proxy_handler_called, up_log.call + log.call)
        assert_equal(2, up_request_handler_called, up_log.call + log.call)
        assert_equal(1, proxy_handler_called, up_log.call + log.call)
        assert_equal(1, request_handler_called, up_log.call + log.call)

        req = Net::HTTP::Head.new("/")
        http.request(req){|res|
          via = res["via"].split(/,\s+/)
          assert(via.include?("1.1 localhost.localdomain:#{up_port}"), up_log.call + log.call)
          assert(via.include?("1.1 localhost.localdomain:#{port}"), up_log.call + log.call)
          assert_nil(res.body, up_log.call + log.call)
        }
        assert_equal(2, up_proxy_handler_called, up_log.call + log.call)
        assert_equal(4, up_request_handler_called, up_log.call + log.call)
        assert_equal(2, proxy_handler_called, up_log.call + log.call)
        assert_equal(2, request_handler_called, up_log.call + log.call)

        req = Net::HTTP::Post.new("/")
        req.body = "post-data"
        req.content_type = "application/x-www-form-urlencoded"
        http.request(req){|res|
          via = res["via"].split(/,\s+/)
          assert(via.include?("1.1 localhost.localdomain:#{up_port}"), up_log.call + log.call)
          assert(via.include?("1.1 localhost.localdomain:#{port}"), up_log.call + log.call)
          assert_equal("POST / post-data", res.body, up_log.call + log.call)
        }
        assert_equal(3, up_proxy_handler_called, up_log.call + log.call)
        assert_equal(6, up_request_handler_called, up_log.call + log.call)
        assert_equal(3, proxy_handler_called, up_log.call + log.call)
        assert_equal(3, request_handler_called, up_log.call + log.call)

        if defined?(OpenSSL::SSL)
          # Testing CONNECT to the upstream proxy server
          #
          #  client -------> proxy -------> proxy -------> https
          #    1.   CONNECT        CONNECT      establish TCP
          #    2.   -------- establish SSL session ------>
          #    3.   ---------- GET or POST -------------->
          #
          key = TEST_KEY_RSA2048
          cert = make_certificate(key, "127.0.0.1")
          s_config = {
            :SSLEnable =>true,
            :ServerName => "localhost",
            :SSLCertificate => cert,
            :SSLPrivateKey => key,
          }
          TestWEBrick.start_httpserver(s_config){|s_server, s_addr, s_port, s_log|
            s_server.mount_proc("/"){|req2, res|
              res.body = "SSL #{req2.request_method} #{req2.path} #{req2.body}"
            }
            http = Net::HTTP.new("127.0.0.1", s_port, addr, port, up_log.call + log.call + s_log.call)
            http.use_ssl = true
            http.verify_callback = Proc.new do |preverify_ok, store_ctx|
              store_ctx.current_cert.to_der == cert.to_der
            end

            req2 = Net::HTTP::Get.new("/")
            http.request(req2){|res|
              assert_equal("SSL GET / ", res.body, up_log.call + log.call + s_log.call)
            }

            req2 = Net::HTTP::Post.new("/")
            req2.body = "post-data"
            req2.content_type = "application/x-www-form-urlencoded"
            http.request(req2){|res|
              assert_equal("SSL POST / post-data", res.body, up_log.call + log.call + s_log.call)
            }
          }
        end
      }
    }
  end

  if defined?(OpenSSL::SSL)
    TEST_KEY_RSA2048 = OpenSSL::PKey.read <<-_end_of_pem_
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAuV9ht9J7k4NBs38jOXvvTKY9gW8nLICSno5EETR1cuF7i4pN
s9I1QJGAFAX0BEO4KbzXmuOvfCpD3CU+Slp1enenfzq/t/e/1IRW0wkJUJUFQign
4CtrkJL+P07yx18UjyPlBXb81ApEmAB5mrJVSrWmqbjs07JbuS4QQGGXLc+Su96D
kYKmSNVjBiLxVVSpyZfAY3hD37d60uG+X8xdW5v68JkRFIhdGlb6JL8fllf/A/bl
NwdJOhVr9mESHhwGjwfSeTDPfd8ZLE027E5lyAVX9KZYcU00mOX+fdxOSnGqS/8J
DRh0EPHDL15RcJjV2J6vZjPb0rOYGDoMcH+94wIDAQABAoIBAAzsamqfYQAqwXTb
I0CJtGg6msUgU7HVkOM+9d3hM2L791oGHV6xBAdpXW2H8LgvZHJ8eOeSghR8+dgq
PIqAffo4x1Oma+FOg3A0fb0evyiACyrOk+EcBdbBeLo/LcvahBtqnDfiUMQTpy6V
seSoFCwuN91TSCeGIsDpRjbG1vxZgtx+uI+oH5+ytqJOmfCksRDCkMglGkzyfcl0
Xc5CUhIJ0my53xijEUQl19rtWdMnNnnkdbG8PT3LZlOta5Do86BElzUYka0C6dUc
VsBDQ0Nup0P6rEQgy7tephHoRlUGTYamsajGJaAo1F3IQVIrRSuagi7+YpSpCqsW
wORqorkCgYEA7RdX6MDVrbw7LePnhyuaqTiMK+055/R1TqhB1JvvxJ1CXk2rDL6G
0TLHQ7oGofd5LYiemg4ZVtWdJe43BPZlVgT6lvL/iGo8JnrncB9Da6L7nrq/+Rvj
XGjf1qODCK+LmreZWEsaLPURIoR/Ewwxb9J2zd0CaMjeTwafJo1CZvcCgYEAyCgb
aqoWvUecX8VvARfuA593Lsi50t4MEArnOXXcd1RnXoZWhbx5rgO8/ATKfXr0BK/n
h2GF9PfKzHFm/4V6e82OL7gu/kLy2u9bXN74vOvWFL5NOrOKPM7Kg+9I131kNYOw
Ivnr/VtHE5s0dY7JChYWE1F3vArrOw3T00a4CXUCgYEA0SqY+dS2LvIzW4cHCe9k
IQqsT0yYm5TFsUEr4sA3xcPfe4cV8sZb9k/QEGYb1+SWWZ+AHPV3UW5fl8kTbSNb
v4ng8i8rVVQ0ANbJO9e5CUrepein2MPL0AkOATR8M7t7dGGpvYV0cFk8ZrFx0oId
U0PgYDotF/iueBWlbsOM430CgYEAqYI95dFyPI5/AiSkY5queeb8+mQH62sdcCCr
vd/w/CZA/K5sbAo4SoTj8dLk4evU6HtIa0DOP63y071eaxvRpTNqLUOgmLh+D6gS
Cc7TfLuFrD+WDBatBd5jZ+SoHccVrLR/4L8jeodo5FPW05A+9gnKXEXsTxY4LOUC
9bS4e1kCgYAqVXZh63JsMwoaxCYmQ66eJojKa47VNrOeIZDZvd2BPVf30glBOT41
gBoDG3WMPZoQj9pb7uMcrnvs4APj2FIhMU8U15LcPAj59cD6S6rWnAxO8NFK7HQG
4Jxg3JNNf8ErQoCHb1B3oVdXJkmbJkARoDpBKmTCgKtP8ADYLmVPQw==
-----END RSA PRIVATE KEY-----
    _end_of_pem_
  end
end
