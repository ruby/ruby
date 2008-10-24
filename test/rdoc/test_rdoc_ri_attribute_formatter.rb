require 'stringio'
require 'rubygems'
require 'minitest/unit'
require 'rdoc/ri/formatter'

class TestRDocRIAttributeFormatter < MiniTest::Unit::TestCase

  def setup
    @output = StringIO.new
    @width = 78
    @indent = '  '

    @f = RDoc::RI::AttributeFormatter.new @output, @width, @indent
  end

  def test_wrap_empty
    @f.wrap ''
    assert_equal '', @output.string
  end

  def test_wrap_long
    @f.wrap 'a ' * (@width / 2)
    assert_equal "  a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a \n  a \n",
                 @output.string
  end

  def test_wrap_markup
    @f.wrap 'a <tt>b</tt> c'
    assert_equal "  a b c\n", @output.string
  end

  def test_wrap_nil
    @f.wrap nil
    assert_equal '', @output.string
  end

  def test_wrap_short
    @f.wrap 'a b c'
    assert_equal "  a b c\n", @output.string
  end

end

MiniTest::Unit.autorun
