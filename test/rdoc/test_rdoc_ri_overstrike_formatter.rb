require 'stringio'
require 'rubygems'
require 'minitest/unit'
require 'rdoc/ri/formatter'
require 'rdoc/markup/fragments'
require 'rdoc/markup/to_flow'

class TestRDocRIOverstrikeFormatter < MiniTest::Unit::TestCase

  def setup
    @output = StringIO.new
    @width = 78
    @indent = '  '

    @f = RDoc::RI::OverstrikeFormatter.new @output, @width, @indent
    @markup = RDoc::Markup.new
    @flow = RDoc::Markup::ToFlow.new

    @af = RDoc::RI::AttributeFormatter
  end

  def test_display_verbatim_flow_item_bold
    verbatim = RDoc::Markup::Flow::VERB.new "*a* b c"

    @f.display_verbatim_flow_item verbatim

    assert_equal "  *a* b c\n\n", @output.string
  end

  def test_write_attribute_text_bold
    line = [RDoc::RI::AttributeFormatter::AttrChar.new('b', @af::BOLD)]

    @f.write_attribute_text '  ', line

    assert_equal "  b\bb\n", @output.string
  end

  def test_write_attribute_text_bold_italic
    attr = @af::BOLD | @af::ITALIC
    line = [RDoc::RI::AttributeFormatter::AttrChar.new('d', attr)]

    @f.write_attribute_text '  ', line

    assert_equal "  _\bd\bd\n", @output.string
  end

  def test_write_attribute_text_code
    line = [RDoc::RI::AttributeFormatter::AttrChar.new('c', @af::CODE)]

    @f.write_attribute_text '  ', line

    assert_equal "  _\bc\n", @output.string
  end

  def test_write_attribute_text_italic
    line = [RDoc::RI::AttributeFormatter::AttrChar.new('a', @af::ITALIC)]

    @f.write_attribute_text '  ', line

    assert_equal "  _\ba\n", @output.string
  end

  def test_bold_print
    @f.bold_print 'a b c'

    assert_equal "a\ba \b b\bb \b c\bc", @output.string
  end

end

MiniTest::Unit.autorun
