require 'test/unit'

class TestForTestHideSkip < Test::Unit::TestCase
  def test_skip
    skip
  end
end
