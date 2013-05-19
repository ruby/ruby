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
    assert_equal("こんにちは", escape("こんにちは"))
  end
end
