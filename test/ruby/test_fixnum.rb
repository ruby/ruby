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
      [-1, 0, 1].each do |x|
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
end
