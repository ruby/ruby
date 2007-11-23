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

  def test_yoshidam_net_20041111_1
    s = "[\xC2\xA0-\xC3\xBE]"
    assert_match(Regexp.new(s, nil, "u"), "\xC3\xBE")
  end

  def test_yoshidam_net_20041111_2
    assert_raise(RegexpError) do
      s = "[\xFF-\xFF]"
      Regexp.new(s, nil, "u")
    end
  end

  def test_ruby_dev_31309
    assert_equal('Ruby', 'Ruby'.sub(/[^a-z]/i, '-'))
  end

  def test_assert_normal_exit
    # moved from knownbug.  It caused core.
    Regexp.union("a", "a")
  end

  def test_to_s
    assert_equal '(?-mix:\000)', Regexp.new("\0").to_s
  end
end
