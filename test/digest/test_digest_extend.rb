require 'test/unit'
require 'digest'

class TestDigestExtend < Test::Unit::TestCase
  class MyDigest < Digest::Class
    def initialize(*arg)
      super
      @buf = []
    end

    def update(arg)
      @buf << arg
      self
    end

    alias << update

    def finish
      (@buf.join.length % 256).chr
    end

    def reset
      @buf.clear
      self
    end
  end

  def test_digest
    assert_equal("\3", MyDigest.digest("foo"))
  end

  def test_hexdigest
    assert_equal("03", MyDigest.hexdigest("foo"))
  end

  def test_context
    digester = MyDigest.new
    digester.update("foo")
    assert_equal("\3", digester.digest)
    digester.update("foobar")
    assert_equal("\6", digester.digest)
    digester.update("foo")
    assert_equal("\3", digester.digest)
  end

  def test_to_s
    digester = MyDigest.new
    digester.update("foo")
    assert_equal("03", digester.to_s)
  end

  def test_digest_length # breaks MyDigest#digest_length
    assert_equal(1, MyDigest.new.digest_length)
    MyDigest.class_eval do
      def digest_length
        2
      end
    end
    assert_equal(2, MyDigest.new.digest_length)
  end

  def test_block_length
    assert_raises(RuntimeError) do
      MyDigest.new.block_length
    end
  end
end
