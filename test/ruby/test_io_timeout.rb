# frozen_string_literal: false

require 'io/nonblock'
require 'socket'

class TestIOTimeout < Test::Unit::TestCase
  def with_pipe
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    begin
      i, o = UNIXSocket.pair

      yield i, o
    ensure
      i.close
      o.close
    end
  end

  def test_timeout_attribute
    with_pipe do |i, o|
      assert_nil i.timeout

      i.timeout = 10
      assert_equal 10, i.timeout
      assert_nil o.timeout

      o.timeout = 20
      assert_equal 20, o.timeout
      assert_equal 10, i.timeout
    end
  end

  def test_timeout_read_exception
    with_pipe do |i, o|
      i.timeout = 0.0001

      assert_raise(IO::TimeoutError) {i.read}
    end
  end

  def test_timeout_read_preserves_buffered_data
    with_pipe do |i, o|
      data = "Hello" * 4_000
      o.write(data)
      i.timeout = 0.0001

      assert_raise(IO::TimeoutError) {i.read}
      assert_equal data, i.read_nonblock(data.bytesize)
    end
  end

  def test_timeout_sized_read_preserves_partial_data
    with_pipe do |i, o|
      o.write("Hello")
      i.timeout = 0.0001

      assert_raise(IO::TimeoutError) {i.read(10)}
      assert_equal "Hello", i.read_nonblock(5)
    end
  end

  def test_timeout_read_preserves_existing_read_buffer
    with_pipe do |i, o|
      data = "Hello" * 3_276 + "Hell"
      o.write("header\n" + data)
      assert_equal "header\n", i.gets
      i.timeout = 0.0001

      assert_raise(IO::TimeoutError) {i.read(data.bytesize + 1)}
      assert_equal data, i.read_nonblock(data.bytesize)
    end
  end

  def test_timeout_gets_exception
    with_pipe do |i, o|
      i.timeout = 0.0001

      assert_raise(IO::TimeoutError) {i.gets}
    end
  end

  def test_timeout_puts
    with_pipe do |i, o|
      i.timeout = 0.0001
      o.puts("Hello World")
      o.close

      assert_equal "Hello World", i.gets.chomp
    end
  end
end
