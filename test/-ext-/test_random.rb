require 'test/unit'

module TestRandomExt
  class TestLoop < Test::Unit::TestCase
    def setup
      super
      assert_nothing_raised(LoadError) {require '-test-/random'}
    end

    def test_bytes
      rnd = Bug::Random::Loop.new(1)
      assert_equal("\1", rnd.bytes(1))
    end

    def test_rand
      rnd = Bug::Random::Loop.new(1)
      assert_equal(1, rnd.rand(10))
    end
  end
end
