require 'stringio'
require 'rubygems'
require 'minitest/unit'
require 'rdoc/ri/formatter'
require 'rdoc/markup/to_flow'

class TestRDocRIFormatter < MiniTest::Unit::TestCase

  def setup
    @output = StringIO.new
    @width = 78
    @indent = '  '

    @f = RDoc::RI::Formatter.new @output, @width, @indent
    @markup = RDoc::Markup.new
    @flow = RDoc::Markup::ToFlow.new
  end

  def test_blankline
    @f.blankline

    assert_equal "\n", @output.string
  end

  def test_bold_print
    @f.bold_print 'a b c'

    assert_equal 'a b c', @output.string
  end

  def test_break_to_newline
    @f.break_to_newline

    assert_equal '', @output.string
  end

  def test_conv_html
    assert_equal '> < " &', @f.conv_html('&gt; &lt; &quot; &amp;')
  end

  def test_conv_markup
    text = '<tt>a</tt> <code>b</code> <b>c</b> <em>d</em>'

    expected = '+a+ +b+ *c* _d_'

    assert_equal expected, @f.conv_markup(text)
  end

  def test_display_flow
    flow = [
      RDoc::Markup::Flow::H.new(1, 'heading'),
      RDoc::Markup::Flow::P.new('paragraph'),
    ]

    @f.display_flow flow

    assert_equal "\nHEADING\n=======\n\n  paragraph\n\n", @output.string
  end

  def test_display_flow_item_h
    item = RDoc::Markup::Flow::H.new 1, 'heading'

    @f.display_flow_item item

    assert_equal "\nHEADING\n=======\n\n", @output.string
  end

  def test_display_flow_item_li
    item = RDoc::Markup::Flow::LI.new nil, 'paragraph'

    @f.display_flow_item item

    assert_equal "  paragraph\n\n", @output.string
  end

  def test_display_flow_item_list
    item = RDoc::Markup::Flow::LIST.new :NUMBER

    @f.display_flow_item item

    assert_equal "", @output.string
  end

  def test_display_flow_item_p
    item = RDoc::Markup::Flow::P.new 'paragraph'

    @f.display_flow_item item

    assert_equal "  paragraph\n\n", @output.string
  end

  def test_display_flow_item_rule
    item = RDoc::Markup::Flow::RULE.new 1

    @f.display_flow_item item

    assert_equal "#{'-' * 78}\n", @output.string
  end

  def test_display_flow_item_unknown
    e = assert_raises RDoc::Error do
      @f.display_flow_item Object.new
    end

    assert_equal "Unknown flow element: Object", e.message
  end

  def test_display_flow_item_verb
    item = RDoc::Markup::Flow::VERB.new 'a b c'

    @f.display_flow_item item

    assert_equal "  a b c\n\n", @output.string
  end

  def test_display_heading_1
    @f.display_heading 'heading', 1, '  '

    assert_equal "\nHEADING\n=======\n\n", @output.string
  end

  def test_display_heading_2
    @f.display_heading 'heading', 2, '  '

    assert_equal "\nheading\n-------\n\n", @output.string
  end

  def test_display_heading_3
    @f.display_heading 'heading', 3, '  '

    assert_equal "  heading\n\n", @output.string
  end

  def test_display_list
    list = RDoc::Markup::Flow::LIST.new :NUMBER
    list << RDoc::Markup::Flow::LI.new(nil, 'a b c')
    list << RDoc::Markup::Flow::LI.new(nil, 'd e f')

    @f.display_list list

    assert_equal "  1.  a b c\n\n  2.  d e f\n\n", @output.string
  end

  def test_display_list_bullet
    list = RDoc::Markup::Flow::LIST.new :BULLET
    list << RDoc::Markup::Flow::LI.new(nil, 'a b c')

    @f.display_list list

    assert_equal "  *   a b c\n\n", @output.string
  end

  def test_display_list_labeled
    list = RDoc::Markup::Flow::LIST.new :LABELED
    list << RDoc::Markup::Flow::LI.new('label', 'a b c')

    @f.display_list list

    assert_equal "  label a b c\n\n", @output.string
  end

  def test_display_list_lower_alpha
    list = RDoc::Markup::Flow::LIST.new :LOWERALPHA
    list << RDoc::Markup::Flow::LI.new(nil, 'a b c')

    @f.display_list list

    assert_equal "  a.  a b c\n\n", @output.string
  end

  def test_display_list_note
    list = RDoc::Markup::Flow::LIST.new :NOTE
    list << RDoc::Markup::Flow::LI.new('note:', 'a b c')

    @f.display_list list

    assert_equal "  note: a b c\n\n", @output.string
  end

  def test_display_list_number
    list = RDoc::Markup::Flow::LIST.new :NUMBER
    list << RDoc::Markup::Flow::LI.new(nil, 'a b c')

    @f.display_list list

    assert_equal "  1.  a b c\n\n", @output.string
  end

  def test_display_list_unknown
    list = RDoc::Markup::Flow::LIST.new :UNKNOWN
    list << RDoc::Markup::Flow::LI.new(nil, 'a b c')

    e = assert_raises ArgumentError do
      @f.display_list list
    end

    assert_equal 'unknown list type UNKNOWN', e.message
  end

  def test_display_list_upper_alpha
    list = RDoc::Markup::Flow::LIST.new :UPPERALPHA
    list << RDoc::Markup::Flow::LI.new(nil, 'a b c')

    @f.display_list list

    assert_equal "  A.  a b c\n\n", @output.string
  end

  def test_display_verbatim_flow_item
    verbatim = RDoc::Markup::Flow::VERB.new "a b c\nd e f"

    @f.display_verbatim_flow_item verbatim

    assert_equal "  a b c\n  d e f\n\n", @output.string
  end

  def test_display_verbatim_flow_item_bold
    verbatim = RDoc::Markup::Flow::VERB.new "*a* b c"

    @f.display_verbatim_flow_item verbatim

    assert_equal "  *a* b c\n\n", @output.string
  end

  def test_draw_line
    @f.draw_line

    expected = '-' * @width + "\n"
    assert_equal expected, @output.string
  end

  def test_draw_line_label
    @f.draw_line 'label'

    expected = '-' * (@width - 6) + " label\n"
    assert_equal expected, @output.string
  end

  def test_draw_line_label_long
    @f.draw_line 'a' * @width

    expected = '-' * @width + "\n" + ('a' * @width) + "\n"
    assert_equal expected, @output.string
  end

  def test_raw_print_line
    @f.raw_print_line 'a b c'

    assert_equal "a b c", @output.string
  end

  def test_strip_attributes_b
    text = @f.strip_attributes 'hello <b>world</b>'

    expected = 'hello world'

    assert_equal expected, text
  end

  def test_strip_attributes_code
    text = @f.strip_attributes 'hello <code>world</code>'

    expected = 'hello world'

    assert_equal expected, text
  end

  def test_strip_attributes_em
    text = @f.strip_attributes 'hello <em>world</em>'

    expected = 'hello world'

    assert_equal expected, text
  end

  def test_strip_attributes_i
    text = @f.strip_attributes 'hello <i>world</i>'

    expected = 'hello world'

    assert_equal expected, text
  end

  def test_strip_attributes_tt
    text = @f.strip_attributes 'hello <tt>world</tt>'

    expected = 'hello world'

    assert_equal expected, text
  end

  def test_wrap_empty
    @f.wrap ''
    assert_equal '', @output.string
  end

  def test_wrap_long
    @f.wrap 'a ' * (@width / 2)
    assert_equal "  a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a a\n  a \n",
                 @output.string
  end

  def test_wrap_markup
    @f.wrap 'a <tt>b</tt> c'
    assert_equal "  a +b+ c\n", @output.string
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
