require 'test/unit'

class TestRegexp < Test::Unit::TestCase
  def test_ruby_dev_24643
    assert_nothing_raised("[ruby-dev:24643]") { /(?:(?:[a]*[a])?b)*a*$/ =~ "aabaaca" }
  end

  def test_ruby_talk_116455
    assert_match(/^(\w{2,}).* ([A-Za-z\xa2\xc0-\xff]{2,}?)$/, "Hallo Welt")
  end

  def test_ruby_dev_24887
    assert_equal("a".gsub(/a\Z/, ""), "")
  end
end
