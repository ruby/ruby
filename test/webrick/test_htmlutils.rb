require "test/unit"
require "webrick/htmlutils"

class TestWEBrickHTMLUtils < Test::Unit::TestCase
  include WEBrick::HTMLUtils

  def test_escape
    assert_equal("foo", escape("foo"))
    assert_equal("foo bar", escape("foo bar"))
    assert_equal("foo&amp;bar", escape("foo&bar"))
    assert_equal("foo&quot;bar", escape("foo\"bar"))
    assert_equal("foo&gt;bar", escape("foo>bar"))
    assert_equal("foo&lt;bar", escape("foo<bar"))
    assert_equal("\u{3053 3093 306B 3061 306F}", escape("\u{3053 3093 306B 3061 306F}"))
    bug8425 = '[Bug #8425] [ruby-core:55052]'
    assert_nothing_raised(ArgumentError, Encoding::CompatibilityError, bug8425) {
      assert_equal("\u{3053 3093 306B}\xff&lt;", escape("\u{3053 3093 306B}\xff<"))
    }
  end
end
