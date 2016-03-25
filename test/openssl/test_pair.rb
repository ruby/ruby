require_relative 'utils'

if defined?(OpenSSL)

require 'socket'
require_relative '../ruby/ut_eof'

module OpenSSL::SSLPairM
  def server
    host = "127.0.0.1"
    port = 0
    ctx = OpenSSL::SSL::SSLContext.new()
    ctx.ciphers = "ADH"
    ctx.tmp_dh_callback = proc { OpenSSL::TestUtils::TEST_KEY_DH1024 }
    tcps = create_tcp_server(host, port)
    ssls = OpenSSL::SSL::SSLServer.new(tcps, ctx)
    return ssls
  end

  def client(port)
    host = "127.0.0.1"
    ctx = OpenSSL::SSL::SSLContext.new()
    ctx.ciphers = "ADH"
    s = create_tcp_client(host, port)
    ssl = OpenSSL::SSL::SSLSocket.new(s, ctx)
    ssl.connect
    ssl.sync_close = true
    ssl
  end

  def ssl_pair
    ssls = server
    th = Thread.new {
      ns = ssls.accept
      ssls.close
      ns
    }
    port = ssls.to_io.local_address.ip_port
    c = client(port)
    s = th.value
    if block_given?
      begin
        yield c, s
      ensure
        c.close unless c.closed?
        s.close unless s.closed?
      end
    else
      return c, s
    end
  ensure
    if th && th.alive?
      th.kill
      th.join
    end
  end
end

module OpenSSL::SSLPair
  include OpenSSL::SSLPairM

  def create_tcp_server(host, port)
    TCPServer.new(host, port)
  end

  def create_tcp_client(host, port)
    TCPSocket.new(host, port)
  end
end

module OpenSSL::SSLPairLowlevelSocket
  include OpenSSL::SSLPairM

  def create_tcp_server(host, port)
    Addrinfo.tcp(host, port).listen
  end

  def create_tcp_client(host, port)
    Addrinfo.tcp(host, port).connect
  end
end

module OpenSSL::TestEOF1M
  def open_file(content)
    s1, s2 = ssl_pair
    th = Thread.new { s2 << content; s2.close }
    yield s1
  ensure
    th.join
  end
end

module OpenSSL::TestEOF2M
  def open_file(content)
    s1, s2 = ssl_pair
    th = Thread.new { s1 << content; s1.close }
    yield s2
  ensure
    th.join
  end
end

module OpenSSL::TestPairM
  def test_getc
    ssl_pair {|s1, s2|
      s1 << "a"
      assert_equal(?a, s2.getc)
    }
  end

  def test_readpartial
    ssl_pair {|s1, s2|
      s2.write "a\nbcd"
      assert_equal("a\n", s1.gets)
      assert_equal("bcd", s1.readpartial(10))
      s2.write "efg"
      assert_equal("efg", s1.readpartial(10))
      s2.close
      assert_raise(EOFError) { s1.readpartial(10) }
      assert_raise(EOFError) { s1.readpartial(10) }
      assert_equal("", s1.readpartial(0))
    }
  end

  def test_readall
    ssl_pair {|s1, s2|
      s2.close
      assert_equal("", s1.read)
    }
  end

  def test_readline
    ssl_pair {|s1, s2|
      s2.close
      assert_raise(EOFError) { s1.readline }
    }
  end

  def test_puts_meta
    ssl_pair {|s1, s2|
      begin
        old = $/
        $/ = '*'
        s1.puts 'a'
      ensure
        $/ = old
      end
      s1.close
      assert_equal("a\n", s2.read)
    }
  end

  def test_puts_empty
    ssl_pair {|s1, s2|
      s1.puts
      s1.close
      assert_equal("\n", s2.read)
    }
  end

  def test_read_nonblock
    ssl_pair {|s1, s2|
      err = nil
      assert_raise(OpenSSL::SSL::SSLErrorWaitReadable) {
        begin
          s2.read_nonblock(10)
        ensure
          err = $!
        end
      }
      assert_kind_of(IO::WaitReadable, err)
      s1.write "abc\ndef\n"
      IO.select([s2])
      assert_equal("ab", s2.read_nonblock(2))
      assert_equal("c\n", s2.gets)
      ret = nil
      assert_nothing_raised("[ruby-core:20298]") { ret = s2.read_nonblock(10) }
      assert_equal("def\n", ret)
      s1.close
      sleep 0.1
      assert_raise(EOFError) { s2.read_nonblock(10) }
    }
  end

  def test_read_nonblock_no_exception
    ssl_pair {|s1, s2|
      assert_equal :wait_readable, s2.read_nonblock(10, exception: false)
      s1.write "abc\ndef\n"
      IO.select([s2])
      assert_equal("ab", s2.read_nonblock(2, exception: false))
      assert_equal("c\n", s2.gets)
      ret = nil
      assert_nothing_raised("[ruby-core:20298]") { ret = s2.read_nonblock(10, exception: false) }
      assert_equal("def\n", ret)
      s1.close
      sleep 0.1
      assert_equal(nil, s2.read_nonblock(10, exception: false))
    }
  end

  def write_nonblock(socket, meth, str)
    ret = socket.send(meth, str)
    ret.is_a?(Symbol) ? 0 : ret
  end

  def write_nonblock_no_ex(socket, str)
    ret = socket.write_nonblock str, exception: false
    ret.is_a?(Symbol) ? 0 : ret
  end

  def test_write_nonblock
    ssl_pair {|s1, s2|
      n = 0
      begin
        n += write_nonblock s1, :write_nonblock, "a" * 100000
        n += write_nonblock s1, :write_nonblock, "b" * 100000
        n += write_nonblock s1, :write_nonblock, "c" * 100000
        n += write_nonblock s1, :write_nonblock, "d" * 100000
        n += write_nonblock s1, :write_nonblock, "e" * 100000
        n += write_nonblock s1, :write_nonblock, "f" * 100000
      rescue IO::WaitWritable
      end
      s1.close
      assert_equal(n, s2.read.length)
    }
  end

  def test_write_nonblock_no_exceptions
    ssl_pair {|s1, s2|
      n = 0
      begin
        n += write_nonblock_no_ex s1, "a" * 100000
        n += write_nonblock_no_ex s1, "b" * 100000
        n += write_nonblock_no_ex s1, "c" * 100000
        n += write_nonblock_no_ex s1, "d" * 100000
        n += write_nonblock_no_ex s1, "e" * 100000
        n += write_nonblock_no_ex s1, "f" * 100000
      rescue OpenSSL::SSL::SSLError => e
        # on some platforms (maybe depend on OpenSSL version), writing to
        # SSLSocket after SSL_ERROR_WANT_WRITE causes this error.
        raise e if n == 0
      end
      s1.close
      assert_equal(n, s2.read.length)
    }
  end

  def test_write_nonblock_with_buffered_data
    ssl_pair {|s1, s2|
      s1.write "foo"
      s1.write_nonblock("bar")
      s1.write "baz"
      s1.close
      assert_equal("foobarbaz", s2.read)
    }
  end

  def test_write_nonblock_with_buffered_data_no_exceptions
    ssl_pair {|s1, s2|
      s1.write "foo"
      s1.write_nonblock("bar", exception: false)
      s1.write "baz"
      s1.close
      assert_equal("foobarbaz", s2.read)
    }
  end

  def test_connect_accept_nonblock
    host = "127.0.0.1"
    port = 0
    ctx = OpenSSL::SSL::SSLContext.new()
    ctx.ciphers = "ADH"
    ctx.tmp_dh_callback = proc { OpenSSL::TestUtils::TEST_KEY_DH1024 }
    serv = TCPServer.new(host, port)

    port = serv.connect_address.ip_port

    sock1 = TCPSocket.new(host, port)
    sock2 = serv.accept
    serv.close

    th = Thread.new {
      s2 = OpenSSL::SSL::SSLSocket.new(sock2, ctx)
      s2.sync_close = true
      begin
        sleep 0.2
        s2.accept_nonblock
      rescue IO::WaitReadable
        IO.select([s2])
        retry
      rescue IO::WaitWritable
        IO.select(nil, [s2])
        retry
      end
      s2
    }

    sleep 0.1
    ctx = OpenSSL::SSL::SSLContext.new()
    ctx.ciphers = "ADH"
    s1 = OpenSSL::SSL::SSLSocket.new(sock1, ctx)
    begin
      sleep 0.2
      s1.connect_nonblock
    rescue IO::WaitReadable
      IO.select([s1])
      retry
    rescue IO::WaitWritable
      IO.select(nil, [s1])
      retry
    end
    s1.sync_close = true

    s2 = th.value

    s1.print "a\ndef"
    assert_equal("a\n", s2.gets)
  ensure
    th.join
    s1.close if s1 && !s1.closed?
    s2.close if s2 && !s2.closed?
    serv.close if serv && !serv.closed?
    sock1.close if sock1 && !sock1.closed?
    sock2.close if sock2 && !sock2.closed?
  end
end

class OpenSSL::TestEOF1 < Test::Unit::TestCase
  include TestEOF
  include OpenSSL::SSLPair
  include OpenSSL::TestEOF1M
end

class OpenSSL::TestEOF1LowlevelSocket < Test::Unit::TestCase
  include TestEOF
  include OpenSSL::SSLPairLowlevelSocket
  include OpenSSL::TestEOF1M
end

class OpenSSL::TestEOF2 < Test::Unit::TestCase
  include TestEOF
  include OpenSSL::SSLPair
  include OpenSSL::TestEOF2M
end

class OpenSSL::TestEOF2LowlevelSocket < Test::Unit::TestCase
  include TestEOF
  include OpenSSL::SSLPairLowlevelSocket
  include OpenSSL::TestEOF2M
end

class OpenSSL::TestPair < Test::Unit::TestCase
  include OpenSSL::SSLPair
  include OpenSSL::TestPairM
end

class OpenSSL::TestPairLowlevelSocket < Test::Unit::TestCase
  include OpenSSL::SSLPairLowlevelSocket
  include OpenSSL::TestPairM
end

end
