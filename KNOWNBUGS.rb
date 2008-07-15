#
# This is a list of known bugs.
#

require 'test/unit'

class TC_KnownBugs < Test::Unit::TestCase
  def just_yield()
    yield
  end

  def test_block_arg1
    # &b wrongly captures the upper block such as the one given to
    # this method, if no block is given on yield.
    just_yield {|&b|
      assert_equal(nil, b)
    }
  end
end
