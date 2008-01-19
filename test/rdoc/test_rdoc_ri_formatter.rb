require 'stringio'
require 'test/unit'
require 'rdoc/ri/formatter'
require 'rdoc/markup/to_flow'

class TestRDocRIFormatter < Test::Unit::TestCase

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

  def test_display_list_bullet
    list = util_convert('* a b c').first

    @f.display_list list

    assert_equal "  *   a b c\n\n", @output.string
  end

  def test_display_list_unknown
    list = util_convert('* a b c').first
    list.instance_variable_set :@type, :UNKNOWN

    e = assert_raise ArgumentError do
      @f.display_list list
    end

    assert_equal 'unknown list type UNKNOWN', e.message
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

    assert_equal "a b c\n", @output.string
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

  def util_convert(text)
    @markup.convert text, @flow
  end
end

