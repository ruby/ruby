# frozen_string_literal: true
require_relative 'utils'
require_relative 'ut_eof'

return unless defined?(OpenSSL::SSL)

module OpenSSL::SSLPair
  def ssl_pair
    svr_dn = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=localhost")
    ee_exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
    ]
    svr_key = OpenSSL::TestUtils::Fixtures.pkey("rsa-1")
    svr_cert = issue_cert(svr_dn, svr_key, 1, ee_exts, nil, nil)

    host = "127.0.0.1"
    svr = TCPServer.new(host, 0)
    svr.setsockopt(:TCP, :NODELAY, 1)
    port = svr.connect_address.ip_port

    tcps = nil
    th = Thread.new {
      tcps = svr.accept
      sctx = OpenSSL::SSL::SSLContext.new
      sctx.add_certificate(svr_cert, svr_key)
      ssl = OpenSSL::SSL::SSLSocket.new(tcps, sctx)
      ssl.accept
      ssl
    }

    tcpc = TCPSocket.new(host, port)
    tcpc.setsockopt(:TCP, :NODELAY, 1)
    c = OpenSSL::SSL::SSLSocket.new(tcpc)
    c.connect
    s = th.value

    yield c, s
  ensure
    tcpc&.close
    tcps&.close
    svr&.close
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

  def test_each_char
    ssl_pair {|s1, s2|
      s1 << "abc"
      s1.close
      chars = []
      ret = s2.each_char { |c| chars << c }
      assert_same(s2, ret)
      assert_equal(["a", "b", "c"], chars)
      chars = []
      s2.each_char { |c| chars << c }
      assert_equal([], chars)
    }
  end

  def test_each_char_enumerator
    ssl_pair {|s1, s2|
      s1 << "abc"
      s1.close
      assert_equal(["a", "b", "c"], s2.each_char.to_a)
      assert_equal([], s2.each_char.to_a)
    }
  end

  def test_each_byte
    ssl_pair {|s1, s2|
      s1 << "abc"
      s1.close
      bytes = []
      ret = s2.each_byte { |b| bytes << b }
      assert_same(s2, ret)
      assert_equal([97, 98, 99], bytes)
      bytes = []
      s2.each_byte { |b| bytes << b }
      assert_equal([], bytes)
    }
  end

  def test_each_byte_enumerator
    ssl_pair {|s1, s2|
      s1 << "abc"
      s1.close
      assert_equal([97, 98, 99], s2.each_byte.to_a)
      assert_equal([], s2.each_byte.to_a)
    }
  end

  def test_ungetc
    ssl_pair {|s1, s2|
      s1 << "abc"
      s1.close
      assert_equal("a", s2.read(1))
      assert_nil(s2.ungetc("A"))
      assert_equal("Abc", s2.read(3))
      assert_predicate(s2, :eof?)

      s2.ungetc("B")
      assert_not_predicate(s2, :eof?)
      assert_equal("B", s2.read)

      s2.ungetc("あ") # \xe3\x81\x82
      s = s2.read(2)
      assert_equal("\xe3\x81".b, s)
      assert_equal(Encoding::BINARY, s.encoding)
      s2.ungetc("")
      assert_equal("\x82".b, s2.read)

      s2.ungetc(1)
      assert_equal("\x01".b, s2.read)
      assert_raise(RangeError) { s2.ungetc(258) }
      assert_raise(RangeError) { s2.ungetc(-1) }
    }
  end

  def test_ungetbyte
    ssl_pair {|s1, s2|
      s1 << "abc"
      s1.close

      assert_equal("a", s2.read(1))
      assert_nil(s2.ungetbyte("A"))
      assert_equal("Abc", s2.read(3))
      assert_predicate(s2, :eof?)

      s2.ungetbyte("B")
      assert_not_predicate(s2, :eof?)
      assert_equal("B", s2.read)

      s2.ungetbyte("あ") # \xe3\x81\x82
      s = s2.read(2)
      assert_equal("\xe3\x81".b, s)
      assert_equal(Encoding::BINARY, s.encoding)
      s2.ungetbyte("")
      assert_equal("\x82".b, s2.read)

      s2.ungetbyte(1)
      assert_equal("\x01".b, s2.read)
      s2.ungetbyte(258)
      assert_equal("\x02".b, s2.read)
      s2.ungetbyte(-1)
      assert_equal("\xff".b, s2.read)
    }
  end

  def test_gets
    ssl_pair {|s1, s2|
      s1 << "abc\n\n$def123ghij"
      s1.close
      ret = s2.gets
      assert_equal Encoding::BINARY, ret.encoding
      assert_equal "abc\n", ret
      assert_equal "\n$", s2.gets("$")
      assert_equal "def123", s2.gets("123")
      assert_equal "ghi", s2.gets(":", 3)
      assert_equal "j", s2.gets(1)
      assert_equal nil, s2.gets
      assert_equal "", s2.gets(0)
    }
    # rs spans multiple sysreads
    ssl_pair {|s1, s2|
      s1 << "a" * 8192 + "b" * 16384
      s1.close
      assert_equal("a" * 8192, s2.gets("b" * 10000, chomp: true))
    }
  end

  def test_gets_rs_nil
    ssl_pair {|s1, s2|
      s1 << "abc\n\ndef"
      s1.close
      assert_equal("", s2.gets(nil, 0))
      assert_equal("a", s2.gets(nil, 1))
      assert_equal("bc\n\ndef", s2.gets(nil))

      # At EOF
      assert_equal("", s2.gets(nil, 0))
      assert_nil(s2.gets(nil))
      assert_nil(s2.gets(nil, 1))
    }
  end

  def test_gets_rs_empty_leading_newlines
    ssl_pair {|s1, s2|
      s1 << "abc\n\ndef\n\nghi"
      s1.close
      assert_equal("a", s2.gets("", 1))
      assert_equal("bc", s2.gets("", 2))
      assert_equal("def\n\n", s2.gets(""))
      assert_equal("ghi", s2.gets(""))
    }
    # Leading and trailing newlines are trimmed
    ssl_pair {|s1, s2|
      s1 << "\n\nabc\n\n\n"
      s1.close
      assert_equal("abc\n\n", s2.gets(""))
      assert_predicate(s2, :eof?)
    }
    # Leading and trailing newlines do not count towards limit, and
    # trailing newlines are still trimmed after limit is reached
    ssl_pair {|s1, s2|
      s1 << "\n\nabc\n\n\n\ndef"
      s1.close
      assert_equal("a", s2.gets("", 1))
      assert_equal("bc\n", s2.gets("", 3))
      assert_equal("def", s2.read)
    }
    # chomp: true
    ssl_pair {|s1, s2|
      s1 << "a\n\n\ndef\n\n\n"
      s1.close
      assert_equal("a\n", s2.gets("", 2, chomp: true))
      assert_equal("def", s2.gets("", chomp: true))
    }
    # \r does not have any special meaning in paragraph mode
    ssl_pair {|s1, s2|
      s1 << "\r\nabc\r\n\r\ndef\r\n"
      s1.close
      assert_equal("\r\nabc\r\n\r\ndef\r\n", s2.gets("", chomp: true))
      assert_predicate(s2, :eof?)
    }
  end

  def test_gets_rs_regexp
    ssl_pair {|s1, s2|
      # OpenSSL::Buffering-specific behavior
      next unless s2.is_a?(OpenSSL::Buffering)

      s1 << "abc\n\n$def123ghi"
      s1.close
      assert_equal("abc\n", s2.gets(/\d+/, 4))
      assert_equal("\n$def123", s2.gets(/\d+/))
      assert_equal("ghi", s2.gets(/\d+/))
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

  def test_gets_chomp_rs
    ssl_pair {|s1, s2|
      s1 << "aaa::bbb:"
      s1.close

      assert_equal("aaa", s2.gets("::", chomp: true))
      assert_equal("bbb:", s2.gets("::", chomp: true))
      assert_nil(s2.gets("::", chomp: true))
    }
  end

  def test_gets_chomp_default_rs
    ssl_pair {|s1, s2|
      s1 << "aaa\r\nbbb\nccc"
      s1.close

      assert_equal("aaa", s2.gets(chomp: true))
      assert_equal("bbb", s2.gets(chomp: true))
      assert_equal("ccc", s2.gets(chomp: true))
      assert_nil(s2.gets(chomp: true))
    }
  end

  def test_gets_chomp_default_rs_limit
    ssl_pair {|s1, s2|
      s1 << "aaa\r\nbbb"
      assert_equal("aaa", s2.gets(10, chomp: true))
      assert_equal("bbb", s2.read(3))
      s1 << "aaa\r\nbbb"
      assert_equal("aaa", s2.gets(3, chomp: true))
      assert_equal("\r\nbbb", s2.read(5))
      s1 << "aaa\r\nbbb"
      assert_equal("aaa\r", s2.gets(4, chomp: true))
      assert_equal("\nbbb", s2.read(4))
    }
  end

  def test_gets_eof_limit
    ssl_pair {|s1, s2|
      s1.write("hello")
      s1.close # trigger EOF
      assert_match "hello", s2.gets("\n", 6), "[ruby-core:70149] [Bug #11400]"
    }
  end

  def test_each_line
    ssl_pair {|s1, s2|
      s1 << "a\nb\nc"
      s1.close
      lines = []
      ret = s2.each_line(chomp: true) { |line| lines << line }
      assert_same(s2, ret)
      assert_equal(["a", "b", "c"], lines)
      lines = []
      s2.each_line { |line| lines << line }
      assert_equal([], lines)
    }
  end

  def test_each_line_enumerator
    ssl_pair {|s1, s2|
      s1 << "a\nb\nc"
      s1.close
      assert_equal(["a", "b", "c"], s2.each_line(chomp: true).to_a)
      assert_equal([], s2.each_line.to_a)
    }
  end

  def test_readlines
    ssl_pair {|s1, s2|
      s1 << "a\nb\nc"
      s1.close
      assert_equal(["a\n", "b\n", "c"], s2.readlines)
      assert_equal([], s2.readlines)
      assert_raise(ArgumentError) { s2.readlines(0) }
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
      assert_equal("", s1.readline(0))
      assert_raise(EOFError) { s1.readline }
    }
  end

  def test_puts
    ssl_pair {|s1, s2|
      s1.puts "a\n", "b"
      s1.puts nil
      s1.close
      assert_equal("a\nb\n\n", s2.read)
    }
  end

  def test_puts_array
    ssl_pair {|s1, s2|
      s1.puts ["a\n", ["b", ["c"]]]
      s1.puts [], [[]]
      def (obj = Object.new).to_ary
        ["d", []]
      end
      s1.puts obj
      s1.close
      assert_equal("a\nb\nc\nd\n", s2.read)
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
      obj.define_singleton_method(:to_s) { str }
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

  def test_write_ltlt_convert_to_s
    ssl_pair {|s1, s2|
      def (obj = Object.new).to_s() "obj" end
      assert_equal(6, s1.write("str", obj))
      assert_same(s1, s1 << obj)
      s1.close
      assert_equal("strobjobj", s2.read)
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

class OpenSSL::TestSSLPair < OpenSSL::TestCase
  include OpenSSL::SSLPair
  include OpenSSL::TestPairM
  include OpenSSL::TestEOF
end
