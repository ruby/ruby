begin
  require "openssl"
rescue LoadError
end
require 'test/unit'

if defined?(OpenSSL)

require 'socket'
dir = File.expand_path(__FILE__)
2.times {dir = File.dirname(dir)}
$:.replace([File.join(dir, "ruby")] | $:)
require 'ut_eof'

module SSLPair
  def server
    host = "127.0.0.1"
    port = 0
    ctx = OpenSSL::SSL::SSLContext.new()
    ctx.ciphers = "ADH"
    tcps = TCPServer.new(host, port)
    ssls = OpenSSL::SSL::SSLServer.new(tcps, ctx)
    return ssls
  end

  def client(port)
    host = "127.0.0.1"
    ctx = OpenSSL::SSL::SSLContext.new()
    ctx.ciphers = "ADH"
    s = TCPSocket.new(host, port)
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
    port = ssls.to_io.addr[1]
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
  end
end

class OpenSSL::TestEOF1 < Test::Unit::TestCase
  include TestEOF
  include SSLPair

  def open_file(content)
    s1, s2 = ssl_pair
    Thread.new { s2 << content; s2.close }
    yield s1
  end
end

class OpenSSL::TestEOF2 < Test::Unit::TestCase
  include TestEOF
  include SSLPair

  def open_file(content)
    s1, s2 = ssl_pair
    Thread.new { s1 << content; s1.close }
    yield s2
  end
end

class OpenSSL::TestPair < Test::Unit::TestCase
  include SSLPair

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

end

end
