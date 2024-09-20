require 'test/unit'

module TestRandomExt
  def setup
    super
    assert_nothing_raised(LoadError) {require '-test-/random'}
  end

  class TestLoop < Test::Unit::TestCase
    include TestRandomExt

    def test_bytes
      rnd = Bug::Random::Loop.new(1)
      assert_equal("\1", rnd.bytes(1))
    end

    def test_rand
      rnd = Bug::Random::Loop.new(1)
      assert_equal(1, rnd.rand(10))
    end

    def test_real
      assert_equal(0.25, Bug::Random::Loop.new(1<<14).rand)
      assert_equal(0.50, Bug::Random::Loop.new(2<<14).rand)
      assert_equal(0.75, Bug::Random::Loop.new(3<<14).rand)
      assert_equal(1.00, Bug::Random::Loop.new(4<<14).rand)
    end
  end

  class TestVersionZero < Test::Unit::TestCase
    include TestRandomExt

    def test_bad_version
      assert_raise(TypeError) {Bug::Random::VersionZero.new}
    end
  end

  class TestVersionMax < Test::Unit::TestCase
    include TestRandomExt

    def test_bad_version
      assert_raise(TypeError) {Bug::Random::VersionMax.new}
    end
  end
end
