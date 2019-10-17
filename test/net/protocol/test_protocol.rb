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
end
