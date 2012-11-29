require 'rubygems/test_case'
require 'rubygems/name_tuple'

class TestGemNameTuple < Gem::TestCase
  def test_platform_normalization
    n = Gem::NameTuple.new "a", Gem::Version.new(0), "ruby"
    assert_equal "ruby", n.platform

    n = Gem::NameTuple.new "a", Gem::Version.new(0), nil
    assert_equal "ruby", n.platform

    n = Gem::NameTuple.new "a", Gem::Version.new(0), ""
    assert_equal "ruby", n.platform
  end
end
