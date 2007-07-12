require 'test/unit'

class TestFixnum < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_pow
    [1, 2, 2**64, 2**63*3, 2**64*3].each do |y|
      [1, 3].each do |x|
        z1 = x**y
        z2 = (-x)**y
        if y % 2 == 1
          assert_equal(z2, -z1)
        else
          assert_equal(z2, z1)
        end
      end
    end
  end

  def test_succ
    assert_equal(0x40000000, 0x3fffffff.succ, "[ruby-dev:31189]")
    assert_equal(0x4000000000000000, 0x3fffffffffffffff.succ, "[ruby-dev:31190]")
  end

  def test_plus
    assert_equal(0x4000000000000000, 0x3fffffffffffffff+1)
  end

end
