require 'rdoc/test_case'

class TestRDocMarkupHardBreak < RDoc::TestCase

  def setup
    super

    @hb = RDoc::Markup::HardBreak.new
  end

  def test_accept
    visitor = Object.new

    def visitor.accept_hard_break(obj) @obj = obj end
    def visitor.obj() @obj end

    @hb.accept visitor

    assert_same @hb, visitor.obj
  end

  def test_equals2
    other = RDoc::Markup::HardBreak.new

    assert_equal @hb, other

    refute_equal @hb, Object.new
  end

end

