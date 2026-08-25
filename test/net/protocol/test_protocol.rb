# frozen_string_literal: true
require "test/unit"
require "net/protocol"
require "stringio"

class TestProtocol < Test::Unit::TestCase
  def test_should_properly_dot_stuff_period_with_no_endline
    bug9627 = '[ruby-core:61441] [Bug #9627]'
    sio = StringIO.new("".dup)
    imio = Net::InternetMessageIO.new(sio)
    email = "To: bob@aol.com\nlook, a period with no endline\n."
    imio.write_message(email)
    assert_equal("To: bob@aol.com\r\nlook, a period with no endline\r\n..\r\n.\r\n", sio.string, bug9627)
  end

  def test_each_crlf_line
    assert_output('', '') do
      sio = StringIO.new("".dup)
      imio = Net::InternetMessageIO.new(sio)
      assert_equal(23, imio.write_message("\u3042\r\u3044\n\u3046\r\n\u3048"))
      assert_equal("\u3042\r\n\u3044\r\n\u3046\r\n\u3048\r\n.\r\n", sio.string)

      sio = StringIO.new("".dup)
      imio = Net::InternetMessageIO.new(sio)
      assert_equal(8, imio.write_message("\u3042\r"))
      assert_equal("\u3042\r\n.\r\n", sio.string)
    end
  end

  def create_mockio(capacity: 100, max: nil)
    mockio = Object.new
    mockio.instance_variable_set(:@str, +'')
    mockio.instance_variable_set(:@capacity, capacity)
    mockio.instance_variable_set(:@max, max)
    def mockio.string; @str; end
    def mockio.to_io; self; end
    def mockio.wait_writable(sec); sleep sec; false; end
    def mockio.write_nonblock(*strs, exception: true)
      if @capacity <= @str.bytesize
        if exception
          raise Net::WaitWritable
        else
          return :wait_writable
        end
      end
      len = 0
      max = @max ? [@capacity, @str.bytesize + @max].min : @capacity
      strs.each do |str|
        len1 = @str.bytesize
        break if max <= len1
        @str << str.byteslice(0, max - @str.bytesize)
        len2 = @str.bytesize
        len += len2 - len1
      end
      len
    end
    mockio
  end

  def test_readuntil
    assert_output("", "") do
      sio = StringIO.new("12345".dup)
      io = Net::BufferedIO.new(sio)
      assert_equal "12345", io.readuntil("5")
    end
  end

  def test_readuntil_limit
    io = Net::BufferedIO.new(StringIO.new("123\n45678\n".dup))
    assert_equal "123\n", io.readuntil("\n", limit: 4)
    assert_raise(Net::ReadLimitExceeded) { io.readuntil("\n", limit: 4) }
  end

  # The limit measures the result, not the position of the terminator in
  # the buffer, so bytes consumed by an earlier read must not count
  # against it.
  def test_readuntil_limit_ignores_already_consumed_bytes
    io = Net::BufferedIO.new(StringIO.new("123\n45678\n".dup))
    assert_equal "123\n", io.readuntil("\n", limit: 4)
    assert_equal "45678\n", io.readuntil("\n", limit: 6)
  end

  def test_readuntil_limit_is_a_protocol_error
    assert_operator Net::ReadLimitExceeded, :<, Net::ProtocolError
  end

  # Which of the two checks fires is decided by how the peer split its
  # writes, so both have to report the same thing.
  def test_readuntil_limit_message_does_not_depend_on_chunking
    whole = Net::BufferedIO.new(StringIO.new("45678\n".dup))
    split = Net::BufferedIO.new(FakeReadPartialIO.new(["45678", "\n"]))
    messages = [whole, split].map do |io|
      assert_raise(Net::ReadLimitExceeded) { io.readuntil("\n", limit: 4) }.message
    end
    assert_equal messages.first, messages.last
    assert_match(/\b4\b/, messages.first)
    assert_match(/limit/, messages.first)
  end

  def test_readuntil_limit_after_a_long_earlier_read
    io = Net::BufferedIO.new(FakeReadPartialIO.new(["aaaaaaaaaa\nbc", "\n"]))
    assert_equal "aaaaaaaaaa\n", io.readuntil("\n", limit: 11)
    assert_equal "bc\n", io.readuntil("\n", limit: 3)
  end

  def test_readuntil_limit_rejects_values_that_are_not_a_positive_integer
    { 0 => "0", -1 => "-1", false => "a non-Integer",
      4.5 => "a non-Integer", "4" => "a non-Integer" }.each do |limit, expected|
      io = Net::BufferedIO.new(StringIO.new("123\n".dup))
      e = assert_raise(ArgumentError, "limit: #{limit.inspect}") do
        io.readuntil("\n", limit: limit)
      end
      assert_equal "limit must be a positive Integer, got #{expected}", e.message
    end

    io = Net::BufferedIO.new(StringIO.new("123\n".dup))
    assert_equal "123\n", io.readuntil("\n", limit: nil)
  end

  def test_readuntil_limit_counts_the_terminator
    io = Net::BufferedIO.new(StringIO.new("1234\n".dup))
    assert_raise(Net::ReadLimitExceeded) { io.readuntil("\n", limit: 4) }

    io = Net::BufferedIO.new(StringIO.new("1234\n".dup))
    assert_equal "1234\n", io.readuntil("\n", limit: 5)
  end

  def test_readuntil_limit_consumes_nothing_when_it_raises
    io = Net::BufferedIO.new(StringIO.new("45678\nrest\n".dup))
    assert_raise(Net::ReadLimitExceeded) { io.readuntil("\n", limit: 4) }
    assert_equal "45678\n", io.readuntil("\n", limit: 6)
    assert_equal "rest\n", io.readuntil("\n")
  end

  def test_readuntil_limit_ignore_eof
    io = Net::BufferedIO.new(StringIO.new("abc".dup))
    assert_equal "abc", io.readuntil("\n", true, limit: 10)
  end

  # The EOF path returns the buffer without consulting the limit, so
  # only the loop's earlier check keeps it inside.
  def test_readuntil_limit_bounds_what_ignore_eof_returns_at_eof
    io = Net::BufferedIO.new(FakeReadPartialIO.new(["abcde"]))
    assert_equal "abcde", io.readuntil("\n", true, limit: 5)

    io = Net::BufferedIO.new(FakeReadPartialIO.new(["abcdef"]))
    assert_raise(Net::ReadLimitExceeded) { io.readuntil("\n", true, limit: 5) }
  end

  def test_readuntil_limit_applies_with_ignore_eof
    io = Net::BufferedIO.new(StringIO.new("abcdefghij".dup))
    assert_raise(Net::ReadLimitExceeded) { io.readuntil("\n", true, limit: 5) }
  end

  # Never yields the terminator. Capping the reads makes a regression in
  # the limit check fail instead of running the CI host out of memory.
  class EndlessIO
    MAX_READS = 2

    def initialize
      @reads = 0
    end

    def read_nonblock(size, buf = nil, exception: false)
      @reads += 1
      raise "readuntil ignored its limit: #{@reads} reads" if @reads > MAX_READS
      s = ("a" * size).b
      buf ? buf.replace(s) : s
    end
  end

  def test_readuntil_limit_endless_stream
    io = Net::BufferedIO.new(EndlessIO.new)
    assert_raise(Net::ReadLimitExceeded) { io.readuntil("\n", limit: 1024) }
  end

  def test_write0_multibyte
    mockio = create_mockio(max: 1)
    io = Net::BufferedIO.new(mockio)
    assert_equal(3, io.write("\u3042"))
  end

  def test_write0_timeout
    mockio = create_mockio
    io = Net::BufferedIO.new(mockio)
    io.write_timeout = 0.1
    assert_raise(Net::WriteTimeout){ io.write("a"*1000) }
  end

  def test_write0_success
    mockio = create_mockio
    io = Net::BufferedIO.new(mockio)
    io.write_timeout = 0.1
    len = io.write("a"*10)
    assert_equal "a"*10, mockio.string
    assert_equal 10, len
  end

  def test_write0_success2
    mockio = create_mockio
    io = Net::BufferedIO.new(mockio)
    io.write_timeout = 0.1
    len = io.write("a"*100)
    assert_equal "a"*100, mockio.string
    assert_equal 100, len
  end

  def test_write0_success_multi1
    mockio = create_mockio
    io = Net::BufferedIO.new(mockio)
    io.write_timeout = 0.1
    len = io.write("a"*50, "a"*49)
    assert_equal "a"*99, mockio.string
    assert_equal 99, len
  end

  def test_write0_success_multi2
    mockio = create_mockio
    io = Net::BufferedIO.new(mockio)
    io.write_timeout = 0.1
    len = io.write("a"*50, "a"*50)
    assert_equal "a"*100, mockio.string
    assert_equal 100, len
  end

  def test_write0_timeout_multi1
    mockio = create_mockio
    io = Net::BufferedIO.new(mockio)
    io.write_timeout = 0.1
    assert_raise(Net::WriteTimeout){ io.write("a"*50,"a"*51) }
  end

  def test_write0_timeout_multi2
    mockio = create_mockio
    io = Net::BufferedIO.new(mockio)
    io.write_timeout = 0.1
    assert_raise(Net::WriteTimeout){ io.write("a"*50,"a"*50,"a") }
  end

  class FakeReadPartialIO
    def initialize(chunks)
      # Binary, like a real IO. String#b also copies, which matters
      # because rbuf_fill clears a string it was not handed as the buffer.
      @chunks = chunks.map(&:b)
    end

    def read_nonblock(size, buf = nil, exception: false)
      chunk = @chunks.shift
      return nil if chunk.nil?
      if buf
        buf.replace(chunk)
        buf
      else
        chunk
      end
    end
  end

  def test_shareable_buffer_leak # https://github.com/ruby/net-protocol/pull/19
    expected_chunks = [
      "aaaaa",
      "bbbbb",
    ]
    fake_io = FakeReadPartialIO.new(expected_chunks)
    io = Net::BufferedIO.new(fake_io)
    actual_chunks = []
    reader = Net::ReadAdapter.new(-> (chunk) { actual_chunks << chunk })
    io.read(5, reader)
    io.read(5, reader)
    assert_equal expected_chunks, actual_chunks
  end

  def test_readuntil_limit_with_a_terminator_spanning_chunks
    io = Net::BufferedIO.new(FakeReadPartialIO.new(["abc\r", "\ndef\r\n"]))
    assert_equal "abc\r\n", io.readuntil("\r\n", limit: 5)

    io = Net::BufferedIO.new(FakeReadPartialIO.new(["abc\r", "\ndef\r\n"]))
    assert_raise(Net::ReadLimitExceeded) { io.readuntil("\r\n", limit: 4) }
  end

  def test_readuntil_terminator_spanning_chunks # https://github.com/ruby/net-protocol/pull/66
    fake_io = FakeReadPartialIO.new(["abc\r", "\ndef\r\n"])
    io = Net::BufferedIO.new(fake_io)
    assert_equal "abc\r\n", io.readuntil("\r\n")
    assert_equal "def\r\n", io.readuntil("\r\n")
  end

  def test_readuntil_terminator_spanning_more_than_two_chunks # https://github.com/ruby/net-protocol/pull/66
    fake_io = FakeReadPartialIO.new(["a", "\r", "\n", "\r", "\n"])
    io = Net::BufferedIO.new(fake_io)
    assert_equal "a\r\n\r\n", io.readuntil("\r\n\r\n")
  end

  def test_readuntil_clamps_a_negative_rewind # https://github.com/ruby/net-protocol/pull/66
    fake_io = FakeReadPartialIO.new(["ab\n"])
    io = Net::BufferedIO.new(fake_io)
    assert_equal "ab", io.readuntil("ab")
  end

  def test_readuntil_does_not_rewind_into_consumed_bytes # https://github.com/ruby/net-protocol/pull/66
    fake_io = FakeReadPartialIO.new(["ab\r\n\r", "\nc"])
    io = Net::BufferedIO.new(fake_io)
    assert_equal "ab\r", io.readuntil("\r")
    assert_raise(EOFError) { io.readuntil("\r\n\r\n") }
  end

  def test_readuntil_ignore_eof_returns_what_is_left # https://github.com/ruby/net-protocol/pull/66
    fake_io = FakeReadPartialIO.new(["ab\r\n\r", "\nc"])
    io = Net::BufferedIO.new(fake_io)
    assert_equal "ab\r", io.readuntil("\r")
    assert_equal "\n\r\nc", io.readuntil("\r\n\r\n", true)
  end
end
