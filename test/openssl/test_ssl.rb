begin
  require "openssl"
  require File.join(File.dirname(__FILE__), "utils.rb")
rescue LoadError
end
require "rbconfig"
require "socket"
require "test/unit"

if defined?(OpenSSL)

class OpenSSL::TestSSL < Test::Unit::TestCase
  RUBY = ENV["RUBY"] || File.join(
    ::Config::CONFIG["bindir"],
    ::Config::CONFIG["ruby_install_name"] + ::Config::CONFIG["EXEEXT"]
  )
  SSL_SERVER = File.join(File.dirname(__FILE__), "ssl_server.rb")
  PORT = 20443
  ITERATIONS = ($0 == __FILE__) ? 100 : 10

  def setup
    @ca_key  = OpenSSL::TestUtils::TEST_KEY_RSA2048
    @svr_key = OpenSSL::TestUtils::TEST_KEY_RSA1024
    @cli_key = OpenSSL::TestUtils::TEST_KEY_DSA256
    @ca  = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")
    @svr = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=localhost")
    @cli = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=localhost")

    now = Time.at(Time.now.to_i)
    ca_exts = [
      ["basicConstraints","CA:TRUE",true],
      ["keyUsage","cRLSign,keyCertSign",true],
    ]
    ee_exts = [
      ["keyUsage","keyEncipherment,digitalSignature",true],
    ]
    @ca_cert  = issue_cert(@ca, @ca_key, 1, now, now+3600, ca_exts,
                           nil, nil, OpenSSL::Digest::SHA1.new)
    @svr_cert = issue_cert(@svr, @svr_key, 2, now, now+1800, ee_exts,
                           @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
    @cli_cert = issue_cert(@cli, @cli_key, 3, now, now+1800, ee_exts,
                           @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
    @server = nil
  end

  def teardown
  end

  def issue_cert(*arg)
    OpenSSL::TestUtils.issue_cert(*arg)
  end

  def issue_crl(*arg)
    OpenSSL::TestUtils.issue_crl(*arg)
  end

  def start_server(port0, verify_mode, start_immediately, &block)
    server = nil
    begin
      cmd = [RUBY]
      cmd << "-d" if $DEBUG
      cmd << SSL_SERVER << port0.to_s << verify_mode.to_s
      cmd << (start_immediately ? "yes" : "no")
      server = IO.popen(cmd.join(" "), "w+")
      server.write(@ca_cert.to_pem)
      server.write(@svr_cert.to_pem)
      server.write(@svr_key.to_pem)
      pid = Integer(server.gets)
      if port = server.gets
        if $DEBUG
          $stderr.printf("%s started: pid=%d port=%d\n", SSL_SERVER, pid, port)
        end
        block.call(server, port.to_i)
      end
    ensure
      if server
        Process.kill(:KILL, pid)
        server.close
      end
    end
  end

  def starttls(ssl)
    ssl.puts("STARTTLS")

    sleep 1   # When this line is eliminated, process on Cygwin blocks
              # forever at ssl.connect. But I don't know why it does.

    ssl.connect
  end

  def test_connect_and_close
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|s, p|
      sock = TCPSocket.new("127.0.0.1", p)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      assert(ssl.connect)
      ssl.close
      assert(!sock.closed?)
      sock.close

      sock = TCPSocket.new("127.0.0.1", p)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true  # !!
      assert(ssl.connect)
      ssl.close
      assert(sock.closed?)
    }
  end

  def test_read_and_write
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|s, p|
      sock = TCPSocket.new("127.0.0.1", p)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      ssl.connect

      # syswrite and sysread
      ITERATIONS.times{|i|
        str = "x" * 100 + "\n"
        ssl.syswrite(str)
        assert_equal(str, ssl.sysread(str.size))

        str = "x" * i * 100 + "\n"
        buf = ""
        ssl.syswrite(str)
        assert_equal(buf.object_id, ssl.sysread(str.size, buf).object_id)
        assert_equal(str, buf)
      }

      # puts and gets
      ITERATIONS.times{
        str = "x" * 100 + "\n"
        ssl.puts(str)
        assert_equal(str, ssl.gets)
      }

      # read and write
      ITERATIONS.times{|i|
        str = "x" * 100 + "\n"
        ssl.write(str)
        assert_equal(str, ssl.read(str.size))

        str = "x" * i * 100 + "\n"
        buf = ""
        ssl.write(str)
        assert_equal(buf.object_id, ssl.read(str.size, buf).object_id)
        assert_equal(str, buf)
      }

      ssl.close
    }
  end

  def test_starttls
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, false){|s, p|
      sock = TCPSocket.new("127.0.0.1", p)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      str = "x" * 1000 + "\n"

      ITERATIONS.times{
        ssl.puts(str)
        assert_equal(str, ssl.gets)
      }

      starttls(ssl)

      ITERATIONS.times{
        ssl.puts(str)
        assert_equal(str, ssl.gets)
      }

      ssl.close
    }
  end

  def test_parallel
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|s, p|
      ssls = []
      10.times{
        sock = TCPSocket.new("127.0.0.1", p)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.connect
        ssl.sync_close = true
        ssls << ssl
      }
      str = "x" * 1000 + "\n"
      ITERATIONS.times{
        ssls.each{|ssl|
          ssl.puts(str)
          assert_equal(str, ssl.gets)
        }
      }
      ssls.each{|ssl| ssl.close }
    }
  end
end

end
