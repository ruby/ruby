require 'test/unit'

class TestRegexp < Test::Unit::TestCase
  def test_undefined_bytecode_bug
    assert_nothing_raised("[ruby-dev:24643]") { /(?:(?:[a]*[a])?b)*a*$/ =~ "aabaaca" }
  end
end
