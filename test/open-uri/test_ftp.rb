# frozen_string_literal: true
require 'test/unit'
require 'socket'
require 'open-uri'

class TestOpenURIFtp < Test::Unit::TestCase
  def with_env(h)
    begin
      old = {}
      h.each_key {|k| old[k] = ENV[k] }
      ENV.update(h)
      yield
    ensure
      ENV.update(old)
    end
  end

  begin
    require 'net/ftp'

    def test_ftp_invalid_request
      assert_raise(ArgumentError) { URI("ftp://127.0.0.1/").read }
      assert_raise(ArgumentError) { URI("ftp://127.0.0.1/a%0Db").read }
      assert_raise(ArgumentError) { URI("ftp://127.0.0.1/a%0Ab").read }
      assert_raise(ArgumentError) { URI("ftp://127.0.0.1/a%0Db/f").read }
      assert_raise(ArgumentError) { URI("ftp://127.0.0.1/a%0Ab/f").read }
      assert_nothing_raised(URI::InvalidComponentError) { URI("ftp://127.0.0.1/d/f;type=x") }
    end

    def test_ftp
      TCPServer.open("127.0.0.1", 0) {|serv|
        _, port, _, host = serv.addr
        th = Thread.new {
          s = serv.accept
          begin
            s.print "220 Test FTP Server\r\n"
            assert_equal("USER anonymous\r\n", s.gets); s.print "331 name ok\r\n"
            assert_match(/\APASS .*\r\n\z/, s.gets); s.print "230 logged in\r\n"
            assert_equal("TYPE I\r\n", s.gets); s.print "200 type set to I\r\n"
            assert_equal("CWD foo\r\n", s.gets); s.print "250 CWD successful\r\n"
            assert_equal("PASV\r\n", s.gets)
            TCPServer.open("127.0.0.1", 0) {|data_serv|
              _, data_serv_port, _, _ = data_serv.addr
              hi = data_serv_port >> 8
              lo = data_serv_port & 0xff
              s.print "227 Entering Passive Mode (127,0,0,1,#{hi},#{lo}).\r\n"
              assert_equal("RETR bar\r\n", s.gets); s.print "150 file okay\r\n"
              data_sock = data_serv.accept
              begin
                data_sock << "content"
              ensure
                data_sock.close
              end
              s.print "226 transfer complete\r\n"
              assert_nil(s.gets)
            }
          ensure
            s.close if s
          end
        }
        begin
          content = URI("ftp://#{host}:#{port}/foo/bar").read
          assert_equal("content", content)
        ensure
          Thread.kill(th)
          th.join
        end
      }
    end

    def test_ftp_active
      TCPServer.open("127.0.0.1", 0) {|serv|
        _, port, _, host = serv.addr
        th = Thread.new {
          s = serv.accept
          begin
            content = "content"
            s.print "220 Test FTP Server\r\n"
            assert_equal("USER anonymous\r\n", s.gets); s.print "331 name ok\r\n"
            assert_match(/\APASS .*\r\n\z/, s.gets); s.print "230 logged in\r\n"
            assert_equal("TYPE I\r\n", s.gets); s.print "200 type set to I\r\n"
            assert_equal("CWD foo\r\n", s.gets); s.print "250 CWD successful\r\n"
            assert(m = /\APORT 127,0,0,1,(\d+),(\d+)\r\n\z/.match(s.gets))
            active_port = m[1].to_i << 8 | m[2].to_i
            TCPSocket.open("127.0.0.1", active_port) {|data_sock|
              s.print "200 data connection opened\r\n"
              assert_equal("RETR bar\r\n", s.gets); s.print "150 file okay\r\n"
              begin
                data_sock << content
              ensure
                data_sock.close
              end
              s.print "226 transfer complete\r\n"
              assert_nil(s.gets)
            }
          ensure
            s.close if s
          end
        }
        begin
          content = URI("ftp://#{host}:#{port}/foo/bar").read(:ftp_active_mode=>true)
          assert_equal("content", content)
        ensure
          Thread.kill(th)
          th.join
        end
      }
    end

    def test_ftp_ascii
      TCPServer.open("127.0.0.1", 0) {|serv|
        _, port, _, host = serv.addr
        th = Thread.new {
          s = serv.accept
          begin
            content = "content"
            s.print "220 Test FTP Server\r\n"
            assert_equal("USER anonymous\r\n", s.gets); s.print "331 name ok\r\n"
            assert_match(/\APASS .*\r\n\z/, s.gets); s.print "230 logged in\r\n"
            assert_equal("TYPE I\r\n", s.gets); s.print "200 type set to I\r\n"
            assert_equal("CWD /foo\r\n", s.gets); s.print "250 CWD successful\r\n"
            assert_equal("TYPE A\r\n", s.gets); s.print "200 type set to A\r\n"
            assert_equal("SIZE bar\r\n", s.gets); s.print "213 #{content.bytesize}\r\n"
            assert_equal("PASV\r\n", s.gets)
            TCPServer.open("127.0.0.1", 0) {|data_serv|
              _, data_serv_port, _, _ = data_serv.addr
              hi = data_serv_port >> 8
              lo = data_serv_port & 0xff
              s.print "227 Entering Passive Mode (127,0,0,1,#{hi},#{lo}).\r\n"
              assert_equal("RETR bar\r\n", s.gets); s.print "150 file okay\r\n"
              data_sock = data_serv.accept
              begin
                data_sock << content
              ensure
                data_sock.close
              end
              s.print "226 transfer complete\r\n"
              assert_nil(s.gets)
            }
          ensure
            s.close if s
          end
        }
        begin
          length = []
          progress = []
          content = URI("ftp://#{host}:#{port}/%2Ffoo/b%61r;type=a").read(
          :content_length_proc => lambda {|n| length << n },
          :progress_proc => lambda {|n| progress << n })
          assert_equal("content", content)
          assert_equal([7], length)
          assert_equal(7, progress.inject(&:+))
        ensure
          Thread.kill(th)
          th.join
        end
      }
    end
  rescue LoadError
    # net-ftp is the bundled gems at Ruby 3.1
  end

  def test_ftp_over_http_proxy
    TCPServer.open("127.0.0.1", 0) {|proxy_serv|
      proxy_port = proxy_serv.addr[1]
      th = Thread.new {
        proxy_sock = proxy_serv.accept
        begin
          req = proxy_sock.gets("\r\n\r\n")
          assert_match(%r{\AGET ftp://192.0.2.1/foo/bar }, req)
          proxy_sock.print "HTTP/1.0 200 OK\r\n"
          proxy_sock.print "Content-Length: 4\r\n\r\n"
          proxy_sock.print "ab\r\n"
        ensure
          proxy_sock.close
        end
      }
      begin
        with_env('ftp_proxy'=>"http://127.0.0.1:#{proxy_port}") {
          content = URI("ftp://192.0.2.1/foo/bar").read
          assert_equal("ab\r\n", content)
        }
      ensure
        Thread.kill(th)
        th.join
      end
    }
  end

  def test_ftp_over_http_proxy_auth
    TCPServer.open("127.0.0.1", 0) {|proxy_serv|
      proxy_port = proxy_serv.addr[1]
      th = Thread.new {
        proxy_sock = proxy_serv.accept
        begin
          req = proxy_sock.gets("\r\n\r\n")
          assert_match(%r{\AGET ftp://192.0.2.1/foo/bar }, req)
          assert_match(%r{Proxy-Authorization: Basic #{['proxy-user:proxy-password'].pack('m').chomp}\r\n}, req)
          proxy_sock.print "HTTP/1.0 200 OK\r\n"
          proxy_sock.print "Content-Length: 4\r\n\r\n"
          proxy_sock.print "ab\r\n"
        ensure
          proxy_sock.close
        end
      }
      begin
        content = URI("ftp://192.0.2.1/foo/bar").read(
          :proxy_http_basic_authentication => ["http://127.0.0.1:#{proxy_port}", "proxy-user", "proxy-password"])
        assert_equal("ab\r\n", content)
      ensure
        Thread.kill(th)
        th.join
      end
    }
  end
end
