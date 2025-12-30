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
      s1.close
      assert_equal(?a, s2.getc)
      assert_nil(s2.getc)
    }
  end

  def test_getbyte
    ssl_pair {|s1, s2|
      s1 << "a"
      s1.close
      assert_equal(97, s2.getbyte)
      assert_nil(s2.getbyte)
    }
  end

  def test_readchar
    ssl_pair {|s1, s2|
      s1 << "b"
      s1.close
      assert_equal("b", s2.readchar)
      assert_raise(EOFError) { s2.readchar }
    }
  end

  def test_readbyte
    ssl_pair {|s1, s2|
      s1 << "b"
      s1.close
      assert_equal(98, s2.readbyte)
      assert_raise(EOFError) { s2.readbyte }
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

  def test_sysread_and_syswrite
    ssl_pair {|s1, s2|
      str = "x" * 100 + "\n"
      s1.syswrite(str)
      newstr = s2.sysread(str.bytesize)
      assert_equal(str, newstr)

      buf = String.new
      s1.syswrite(str)
      assert_same(buf, s2.sysread(str.size, buf))
      assert_equal(str, buf)

      obj = Object.new
      obj.define_singleton_method(:to_str) { str }
      s1.syswrite(obj)
      assert_equal(str, s2.sysread(str.bytesize))
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
      assert_equal "garbage", buf

      s1.close
      buf = +"garbage"
      assert_nil s2.read(100, buf)
      assert_equal "", buf

      buf = +"garbage"
      ret = s2.read(0, buf)
      assert_same buf, ret
      assert_equal "", ret
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

  def test_copy_stream
    ssl_pair { |s1, s2|
      IO.pipe do |r, w|
        str = "hello world\n"
        w.write(str)
        IO.copy_stream(r, s1, str.bytesize)
        IO.copy_stream(s2, w, str.bytesize)
        assert_equal(str, r.read(str.bytesize))
      end
    }
  end

  def test_close_write
    ssl_pair { |s1, s2|
      message = "abc"*1024
      s1.write(message)
      s1.close_write
      assert_equal(message, s2.read)
      s2.write(message)
      s2.close_write
      assert_equal(message, s1.read)
    }
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
