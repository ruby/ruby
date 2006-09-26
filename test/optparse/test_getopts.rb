require 'test/unit'

class TestOptionParser < Test::Unit::TestCase
  def setup
    @opt = OptionParser.new
  end

  def test_getopts
    assert_equal({'a' => true}, @opt.getopts(['-a'], "a"))
  end
end
