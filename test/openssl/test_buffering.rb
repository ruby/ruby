require_relative 'utils'
require 'stringio'
require 'minitest/unit'

class OpenSSL::TestBuffering < MiniTest::Unit::TestCase

  class IO
    include OpenSSL::Buffering

    attr_accessor :sync

    def initialize
      @io = StringIO.new

      super

      @sync = false
    end

    def string
      @io.string
    end

    def sysread *a
      @io.sysread *a
    end

    def syswrite *a
      @io.syswrite *a
    end
  end

  def setup
    @io = IO.new
  end

  def test_flush
    @io.write 'a'

    refute @io.sync
    assert_empty @io.string

    assert_equal @io, @io.flush

    refute @io.sync
    assert_equal 'a', @io.string
  end

  def test_flush_error
    @io.write 'a'

    refute @io.sync
    assert_empty @io.string

    def @io.syswrite *a
      raise SystemCallError, 'fail'
    end

    assert_raises SystemCallError do
      @io.flush
    end

    refute @io.sync, 'sync must not change'
  end

end if defined?(OpenSSL)
