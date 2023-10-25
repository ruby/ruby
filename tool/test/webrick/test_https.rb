# frozen_string_literal: false
require "test/unit"
require "net/http"
require "webrick"
require "webrick/https"
require "webrick/utils"
require_relative "utils"

class TestWEBrickHTTPS < Test::Unit::TestCase
  empty_log = Object.new
  def empty_log.<<(str)
    assert_equal('', str)
    self
  end
  NoLog = WEBrick::Log.new(empty_log, WEBrick::BasicLog::WARN)

  class HTTPSNITest < ::Net::HTTP
    attr_accessor :sni_hostname

    def ssl_socket_connect(s, timeout)
      s.hostname = sni_hostname
      super
    end
  end

  def teardown
    WEBrick::Utils::TimeoutHandler.terminate
    super
  end

  def https_get(addr, port, hostname, path, verifyname = nil)
    subject = nil
    http = HTTPSNITest.new(addr, port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.verify_callback = proc { |x, store| subject = store.chain[0].subject.to_s; x }
    http.sni_hostname = hostname
    req = Net::HTTP::Get.new(path)
    req["Host"] = "#{hostname}:#{port}"
    response = http.start { http.request(req).body }
    assert_equal("/CN=#{verifyname || hostname}", subject)
    response
  end

  def test_sni
    config = {
      :ServerName => "localhost",
      :SSLEnable => true,
      :SSLCertName => "/CN=localhost",
    }
    TestWEBrick.start_httpserver(config){|server, addr, port, log|
      server.mount_proc("/") {|req, res| res.body = "master" }

      # catch stderr in create_self_signed_cert
      stderr_buffer = StringIO.new
      old_stderr, $stderr = $stderr, stderr_buffer

      begin
        vhost_config1 = {
          :ServerName => "vhost1",
          :Port => port,
          :DoNotListen => true,
          :Logger => NoLog,
          :AccessLog => [],
          :SSLEnable => true,
          :SSLCertName => "/CN=vhost1",
        }
        vhost1 = WEBrick::HTTPServer.new(vhost_config1)
        vhost1.mount_proc("/") {|req, res| res.body = "vhost1" }
        server.virtual_host(vhost1)

        vhost_config2 = {
          :ServerName => "vhost2",
          :ServerAlias => ["vhost2alias"],
          :Port => port,
          :DoNotListen => true,
          :Logger => NoLog,
          :AccessLog => [],
          :SSLEnable => true,
          :SSLCertName => "/CN=vhost2",
        }
        vhost2 = WEBrick::HTTPServer.new(vhost_config2)
        vhost2.mount_proc("/") {|req, res| res.body = "vhost2" }
        server.virtual_host(vhost2)
      ensure
        # restore stderr
        $stderr = old_stderr
      end

      assert_match(/\A([.+*]+\n)+\z/, stderr_buffer.string)
      assert_equal("master", https_get(addr, port, "localhost", "/localhost"))
      assert_equal("master", https_get(addr, port, "unknown", "/unknown", "localhost"))
      assert_equal("vhost1", https_get(addr, port, "vhost1", "/vhost1"))
      assert_equal("vhost2", https_get(addr, port, "vhost2", "/vhost2"))
      assert_equal("vhost2", https_get(addr, port, "vhost2alias", "/vhost2alias", "vhost2"))
    }
  end

  def test_check_ssl_virtual
    config = {
      :ServerName => "localhost",
      :SSLEnable => true,
      :SSLCertName => "/CN=localhost",
    }
    TestWEBrick.start_httpserver(config){|server, addr, port, log|
      assert_raise ArgumentError do
        vhost = WEBrick::HTTPServer.new({:DoNotListen => true, :Logger => NoLog})
        server.virtual_host(vhost)
      end
    }
  end
end
