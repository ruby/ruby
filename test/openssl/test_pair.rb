# frozen_string_literal: true
require_relative 'utils'
require_relative 'ut_eof'

if defined?(OpenSSL::SSL)

module OpenSSL::SSLPairM
  def setup
    svr_dn = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=localhost")
    ee_exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
    ]
    @svr_key = OpenSSL::TestUtils::Fixtures.pkey("rsa-1")
    @svr_cert = issue_cert(svr_dn, @svr_key, 1, ee_exts, nil, nil)
  end

  def ssl_pair
    host = "127.0.0.1"
    tcps = create_tcp_server(host, 0)
    port = tcps.connect_address.ip_port

    th = Thread.new {
      sctx = OpenSSL::SSL::SSLContext.new
      sctx.cert = @svr_cert
      sctx.key = @svr_key
      sctx.options |= OpenSSL::SSL::OP_NO_COMPRESSION
      ssls = OpenSSL::SSL::SSLServer.new(tcps, sctx)
      ns = ssls.accept
      ssls.close
      ns
    }

    tcpc = create_tcp_client(host, port)
    c = OpenSSL::SSL::SSLSocket.new(tcpc)
    c.connect
    s = th.value

    yield c, s
  ensure
    tcpc&.close
    tcps&.close
    s&.close
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
    ssl_pair { |s1, s2|
      begin
        th = Thread.new { s2 << content; s2.close }
        yield s1
      ensure
        th&.join
      end
    }
  end
end

module OpenSSL::TestEOF2M
  def open_file(content)
    ssl_pair { |s1, s2|
      begin
        th = Thread.new { s1 << content; s1.close }
        yield s2
      ensure
        th&.join
      end
    }
  end
end

module OpenSSL::TestPairM
  def test_getc
    ssl_pair {|s1, s2|
      s1 << "a"
      assert_equal(?a, s2.getc)
    }
  end

  def test_gets
    ssl_pair {|s1, s2|
      s1 << "abc\n\n$def123ghi"
      s1.close
      ret = s2.gets
      assert_equal Encoding::BINARY, ret.encoding
      assert_equal "abc\n", ret
      assert_equal "\n$", s2.gets("$")
      assert_equal "def123", s2.gets(/\d+/)
      assert_equal "ghi", s2.gets
      assert_equal nil, s2.gets
    }
  end

  def test_gets_chomp
    ssl_pair {|s1, s2|
      s1 << "line1\r\nline2\r\nline3\r\n"
      s1.close

      assert_equal("line1", s2.gets("\r\n", chomp: true))
      assert_equal("line2\r\n", s2.gets("\r\n", chomp: false))
      assert_equal("line3", s2.gets(chomp: true))
    }
  end

  def test_gets_eof_limit
    ssl_pair {|s1, s2|
      s1.write("hello")
      s1.close # trigger EOF
      assert_match "hello", s2.gets("\n", 6), "[ruby-core:70149] [Bug #11400]"
    }
  end

  def test_readpartial
    ssl_pair {|s1, s2|
      s2.write "a\nbcd"
      assert_equal("a\n", s1.gets)
      result = String.new
      result << s1.readpartial(10) until result.length == 3
      assert_equal("bcd", result)
      s2.write "efg"
      result = String.new
      result << s1.readpartial(10) until result.length == 3
      assert_equal("efg", result)
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

  def test_puts_empty
    ssl_pair {|s1, s2|
      s1.puts
      s1.close
      assert_equal("\n", s2.read)
    }
  end

  def test_multibyte_read_write
    # German a umlaut
    auml = [%w{ C3 A4 }.join('')].pack('H*')
    auml.force_encoding(Encoding::UTF_8)
    bsize = auml.bytesize

    ssl_pair { |s1, s2|
      assert_equal bsize, s1.write(auml)
      read = s2.read(bsize)
      assert_equal Encoding::ASCII_8BIT, read.encoding
      assert_equal bsize, read.bytesize
      assert_equal auml, read.force_encoding(Encoding::UTF_8)

      s1.puts(auml)
      read = s2.gets
      assert_equal Encoding::ASCII_8BIT, read.encoding
      assert_equal bsize + 1, read.bytesize
      assert_equal auml + "\n", read.force_encoding(Encoding::UTF_8)
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
      IO.select([s2])
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
      IO.select([s2])
      assert_equal(nil, s2.read_nonblock(10, exception: false))
    }
  end

  def test_read_with_outbuf
    ssl_pair { |s1, s2|
      s1.write("abc\n")
      buf = String.new
      ret = s2.read(2, buf)
      assert_same ret, buf
      assert_equal "ab", ret

      buf = +"garbage"
      ret = s2.read(2, buf)
      assert_same ret, buf
      assert_equal "c\n", ret

      buf = +"garbage"
      assert_equal :wait_readable, s2.read_nonblock(100, buf, exception: false)
      assert_equal "", buf

      s1.close
      buf = +"garbage"
      assert_equal nil, s2.read(100, buf)
      assert_equal "", buf
    }
  end

  def test_write_nonblock
    ssl_pair {|s1, s2|
      assert_equal 3, s1.write_nonblock("foo")
      assert_equal "foo", s2.read(3)

      data = "x" * 16384
      written = 0
      while true
        begin
          written += s1.write_nonblock(data)
        rescue IO::WaitWritable, IO::WaitReadable
          break
        end
      end
      assert written > 0
      assert_equal written, s2.read(written).bytesize
    }
  end

  def test_write_nonblock_no_exceptions
    ssl_pair {|s1, s2|
      assert_equal 3, s1.write_nonblock("foo", exception: false)
      assert_equal "foo", s2.read(3)

      data = "x" * 16384
      written = 0
      while true
        case ret = s1.write_nonblock(data, exception: false)
        when :wait_readable, :wait_writable
          break
        else
          written += ret
        end
      end
      assert written > 0
      assert_equal written, s2.read(written).bytesize
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

  def test_write_nonblock_retry
    ssl_pair {|s1, s2|
      # fill up a socket so we hit EAGAIN
      written = String.new
      n = 0
      buf = 'a' * 4099
      case ret = s1.write_nonblock(buf, exception: false)
      when :wait_readable then break
      when :wait_writable then break
      when Integer
        written << buf
        n += ret
        exp = buf.bytesize
        if ret != exp
          buf = buf.byteslice(ret, exp - ret)
        end
      end while true
      assert_kind_of Symbol, ret

      # make more space for subsequent write:
      readed = s2.read(n)
      assert_equal written, readed

      # this fails if SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER is missing:
      buf2 = Marshal.load(Marshal.dump(buf))
      assert_kind_of Integer, s1.write_nonblock(buf2, exception: false)
    }
  end

  def test_write_zero
    ssl_pair {|s1, s2|
      assert_equal 0, s2.write_nonblock('', exception: false)
      assert_kind_of Symbol, s1.read_nonblock(1, exception: false)
      assert_equal 0, s2.syswrite('')
      assert_kind_of Symbol, s1.read_nonblock(1, exception: false)
      assert_equal 0, s2.write('')
      assert_kind_of Symbol, s1.read_nonblock(1, exception: false)
    }
  end

  def test_write_multiple_arguments
    ssl_pair {|s1, s2|
      str1 = "foo"; str2 = "bar"
      assert_equal 6, s1.write(str1, str2)
      s1.close
      assert_equal "foobar", s2.read
    }
  end

  def test_partial_tls_record_read_nonblock
    ssl_pair { |s1, s2|
      # the beginning of a TLS record
      s1.io.write("\x17")
      # should raise a IO::WaitReadable since a full TLS record is not available
      # for reading
      assert_raise(IO::WaitReadable) { s2.read_nonblock(1) }
    }
  end

  def tcp_pair
    host = "127.0.0.1"
    serv = TCPServer.new(host, 0)
    port = serv.connect_address.ip_port
    sock1 = TCPSocket.new(host, port)
    sock2 = serv.accept
    serv.close
    [sock1, sock2]
  ensure
    serv.close if serv && !serv.closed?
  end

  def test_connect_accept_nonblock_no_exception
    ctx2 = OpenSSL::SSL::SSLContext.new
    ctx2.cert = @svr_cert
    ctx2.key = @svr_key

    sock1, sock2 = tcp_pair

    s2 = OpenSSL::SSL::SSLSocket.new(sock2, ctx2)
    accepted = s2.accept_nonblock(exception: false)
    assert_equal :wait_readable, accepted

    ctx1 = OpenSSL::SSL::SSLContext.new
    s1 = OpenSSL::SSL::SSLSocket.new(sock1, ctx1)
    th = Thread.new do
      rets = []
      begin
        rv = s1.connect_nonblock(exception: false)
        rets << rv
        case rv
        when :wait_writable
          IO.select(nil, [s1], nil, 5)
        when :wait_readable
          IO.select([s1], nil, nil, 5)
        end
      end until rv == s1
      rets
    end

    until th.join(0.01)
      accepted = s2.accept_nonblock(exception: false)
      assert_include([s2, :wait_readable, :wait_writable ], accepted)
    end

    rets = th.value
    assert_instance_of Array, rets
    rets.each do |rv|
      assert_include([s1, :wait_readable, :wait_writable ], rv)
    end
  ensure
    th.join if th
    s1.close if s1
    s2.close if s2
    sock1.close if sock1
    sock2.close if sock2
    accepted.close if accepted.respond_to?(:close)
  end

  def test_connect_accept_nonblock
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert = @svr_cert
    ctx.key = @svr_key

    sock1, sock2 = tcp_pair

    th = Thread.new {
      s2 = OpenSSL::SSL::SSLSocket.new(sock2, ctx)
      5.times {
        begin
          break s2.accept_nonblock
        rescue IO::WaitReadable
          IO.select([s2], nil, nil, 1)
        rescue IO::WaitWritable
          IO.select(nil, [s2], nil, 1)
        end
        sleep 0.2
      }
    }

    s1 = OpenSSL::SSL::SSLSocket.new(sock1)
    5.times {
      begin
        break s1.connect_nonblock
      rescue IO::WaitReadable
        IO.select([s1], nil, nil, 1)
      rescue IO::WaitWritable
        IO.select(nil, [s1], nil, 1)
      end
      sleep 0.2
    }

    s2 = th.value

    s1.print "a\ndef"
    assert_equal("a\n", s2.gets)
  ensure
    sock1&.close
    sock2&.close
    th&.join
  end
end

class OpenSSL::TestEOF1 < OpenSSL::TestCase
  include OpenSSL::TestEOF
  include OpenSSL::SSLPair
  include OpenSSL::TestEOF1M
end

class OpenSSL::TestEOF1LowlevelSocket < OpenSSL::TestCase
  include OpenSSL::TestEOF
  include OpenSSL::SSLPairLowlevelSocket
  include OpenSSL::TestEOF1M
end

class OpenSSL::TestEOF2 < OpenSSL::TestCase
  include OpenSSL::TestEOF
  include OpenSSL::SSLPair
  include OpenSSL::TestEOF2M
end

class OpenSSL::TestEOF2LowlevelSocket < OpenSSL::TestCase
  include OpenSSL::TestEOF
  include OpenSSL::SSLPairLowlevelSocket
  include OpenSSL::TestEOF2M
end

class OpenSSL::TestPair < OpenSSL::TestCase
  include OpenSSL::SSLPair
  include OpenSSL::TestPairM
end

class OpenSSL::TestPairLowlevelSocket < OpenSSL::TestCase
  include OpenSSL::SSLPairLowlevelSocket
  include OpenSSL::TestPairM
end

end
