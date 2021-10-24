# frozen_string_literal: true
require_relative 'utils'

if defined?(OpenSSL)

class OpenSSL::TestBuffering < OpenSSL::TestCase
  class IO
    include OpenSSL::Buffering

    attr_accessor :sync

    def initialize
      @io = Buffer.new
      def @io.sync
        true
      end

      super

      @sync = false
    end

    def string
      @io
    end

    def sysread(size)
      str = @io.slice!(0, size)
      raise EOFError if str.empty?
      str
    end

    def syswrite(str)
      @io << str
      str.size
    end
  end

  def setup
    super
    @io = IO.new
  end

  def test_encoding
    @io.write '😊'
    @io.flush

    assert_equal @io.string.encoding, Encoding::BINARY
  end

  def test_flush
    @io.write 'a'

    assert_not_predicate @io, :sync
    assert_empty @io.string

    assert_equal @io, @io.flush

    assert_not_predicate @io, :sync
    assert_equal 'a', @io.string
  end

  def test_flush_error
    @io.write 'a'

    assert_not_predicate @io, :sync
    assert_empty @io.string

    def @io.syswrite *a
      raise SystemCallError, 'fail'
    end

    assert_raise SystemCallError do
      @io.flush
    end

    assert_not_predicate @io, :sync, 'sync must not change'
  end

  def test_getc
    @io.syswrite('abc')
    assert_equal(?a, @io.getc)
    assert_equal(?b, @io.getc)
    assert_equal(?c, @io.getc)
  end

  def test_each_byte
    @io.syswrite('abc')
    res = []
    @io.each_byte do |c|
      res << c
    end
    assert_equal([97, 98, 99], res)
  end
end

end
