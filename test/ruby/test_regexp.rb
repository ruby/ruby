require 'test/unit'

class TestRegexp < Test::Unit::TestCase
  def test_ruby_dev_24643
    assert_nothing_raised("[ruby-dev:24643]") {
      /(?:(?:[a]*[a])?b)*a*$/ =~ "aabaaca"
    }
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
      s = "[\xFF-\xFF]".force_encoding("utf-8")
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
    assert_equal '(?-mix:\x00)', Regexp.new("\0").to_s
  end

  def test_union
    assert_equal :ok, begin
      Regexp.union(
        "a",
        Regexp.new("\xc2\xa1".force_encoding("euc-jp")),
        Regexp.new("\xc2\xa1".force_encoding("utf-8")))
      :ng
    rescue ArgumentError
      :ok
    end
  end

  def test_named_capture
    m = /&(?<foo>.*?);/.match("aaa &amp; yyy")
    assert_equal("amp", m["foo"])
    assert_equal("amp", m[:foo])
    assert_equal(5, m.begin(:foo))
    assert_equal(8, m.end(:foo))
    assert_equal([5,8], m.offset(:foo))

    assert_equal("aaa [amp] yyy",
      "aaa &amp; yyy".sub(/&(?<foo>.*?);/, '[\k<foo>]'))

    assert_equal('#<MatchData "&amp; y" foo:"amp">',
      /&(?<foo>.*?); (y)/.match("aaa &amp; yyy").inspect)
    assert_equal('#<MatchData "&amp; y" 1:"amp" 2:"y">',
      /&(.*?); (y)/.match("aaa &amp; yyy").inspect)
    assert_equal('#<MatchData "&amp; y" foo:"amp" bar:"y">',
      /&(?<foo>.*?); (?<bar>y)/.match("aaa &amp; yyy").inspect)
    assert_equal('#<MatchData "&amp; y" foo:"amp" foo:"y">',
      /&(?<foo>.*?); (?<foo>y)/.match("aaa &amp; yyy").inspect)

    /(?<id>[A-Za-z_]+)/ =~ "!abc"
    assert_equal("abc", Regexp.last_match(:id))

    /a/ =~ "b" # doesn't match.
    assert_equal(nil, Regexp.last_match)
    assert_equal(nil, Regexp.last_match(1))
    assert_equal(nil, Regexp.last_match(:foo))

    assert_equal(["foo", "bar"], /(?<foo>.)(?<bar>.)/.names)
    assert_equal(["foo"], /(?<foo>.)(?<foo>.)/.names)
    assert_equal([], /(.)(.)/.names)

    assert_equal(["foo", "bar"], /(?<foo>.)(?<bar>.)/.match("ab").names)
    assert_equal(["foo"], /(?<foo>.)(?<foo>.)/.match("ab").names)
    assert_equal([], /(.)(.)/.match("ab").names)

    assert_equal({"foo"=>[1], "bar"=>[2]},
                 /(?<foo>.)(?<bar>.)/.named_captures)
    assert_equal({"foo"=>[1, 2]},
                 /(?<foo>.)(?<foo>.)/.named_captures)
    assert_equal({}, /(.)(.)/.named_captures)

    assert_equal("a[b]c", "abc".sub(/(?<x>[bc])/, "[\\k<x>]"))
  end

  def test_assign_named_capture
    assert_equal("a", eval('/(?<foo>.)/ =~ "a"; foo'))
    assert_equal("a", eval('foo = 1; /(?<foo>.)/ =~ "a"; foo'))
    assert_equal("a", eval('1.times {|foo| /(?<foo>.)/ =~ "a"; break foo }'))
    assert_nothing_raised { eval('/(?<Foo>.)/ =~ "a"') }
    assert_nil(eval('/(?<Foo>.)/ =~ "a"; defined? Foo'))
  end

  def test_assign_named_capture_to_reserved_word
    /(?<nil>.)/ =~ "a"
    assert(!local_variables.include?(:nil), "[ruby-dev:32675]")
  end

  def test_match_regexp
    r = /./
    m = r.match("a")
    assert_equal(r, m.regexp)
  end
end
