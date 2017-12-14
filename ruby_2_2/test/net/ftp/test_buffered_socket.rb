require "net/ftp"
require "test/unit"
require "ostruct"
require "stringio"

class FTPTest < Test::Unit::TestCase
  def test_gets_empty
    sock = create_buffered_socket("")
    assert_equal(nil, sock.gets)
  end

  def test_gets_one_line
    sock = create_buffered_socket("foo\n")
    assert_equal("foo\n", sock.gets)
  end

  def test_gets_one_line_without_term
    sock = create_buffered_socket("foo")
    assert_equal("foo", sock.gets)
  end

  def test_gets_two_lines
    sock = create_buffered_socket("foo\nbar\n")
    assert_equal("foo\n", sock.gets)
    assert_equal("bar\n", sock.gets)
  end

  def test_gets_two_lines_without_term
    sock = create_buffered_socket("foo\nbar")
    assert_equal("foo\n", sock.gets)
    assert_equal("bar", sock.gets)
  end

  private

  def create_buffered_socket(s)
    io = StringIO.new(s)
    return Net::FTP::BufferedSocket.new(io)
  end
end
