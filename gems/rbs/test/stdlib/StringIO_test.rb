require_relative "test_helper"

class StringIOTest < StdlibTest
  target StringIO
  using hook.refinement

  def test_close_read
    io = StringIO.new('example')
    io.close_read
  end

  def test_closed_read?
    io = StringIO.new('example')
    io.closed_read?
    io.close_read
    io.closed_read?
  end

  def test_close_write
    io = StringIO.new('example')
    io.close_write
  end

  def test_closed_write?
    io = StringIO.new('example')
    io.closed_write?
    io.close_write
    io.closed_write?
  end
end
