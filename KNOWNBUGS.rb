#
# This is a list of known bugs.
#

require 'test/unit'

class TC_KnownBugs < Test::Unit::TestCase
  def just_yield()
    yield
  end

  def test_block_arg1
    just_yield {|&b|
      assert_equal(nil, b)
    }
  end
end
