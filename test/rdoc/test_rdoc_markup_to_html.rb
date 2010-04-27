require 'rubygems'
require 'rdoc/markup/formatter_test_case'
require 'rdoc/markup/to_html'
require 'minitest/autorun'

class TestRDocMarkupToHtml < RDoc::Markup::FormatterTestCase

  add_visitor_tests

  def setup
    super

    @to = RDoc::Markup::ToHtml.new
  end

  def test_class_gen_relative_url
    def gen(from, to)
      RDoc::Markup::ToHtml.gen_relative_url from, to
    end

    assert_equal 'a.html',    gen('a.html',   'a.html')
    assert_equal 'b.html',    gen('a.html',   'b.html')

    assert_equal 'd.html',    gen('a/c.html', 'a/d.html')
    assert_equal '../a.html', gen('a/c.html', 'a.html')
    assert_equal 'a/c.html',  gen('a.html',   'a/c.html')
  end

  def accept_blank_line
    assert_empty @to.res.join
  end

  def accept_heading
    assert_equal "<h5>Hello</h5>\n", @to.res.join
  end

  def accept_list_end_bullet
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<ul>\n</ul>\n", @to.res.join
  end

  def accept_list_end_label
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<dl>\n</dl>\n", @to.res.join
  end

  def accept_list_end_lalpha
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<ol style=\"display: lower-alpha\">\n</ol>\n", @to.res.join
  end

  def accept_list_end_number
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<ol>\n</ol>\n", @to.res.join
  end

  def accept_list_end_note
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<table>\n</table>\n", @to.res.join
  end

  def accept_list_end_ualpha
    assert_equal [], @to.list
    assert_equal [], @to.in_list_entry

    assert_equal "<ol style=\"display: upper-alpha\">\n</ol>\n", @to.res.join
  end

  def accept_list_item_end_bullet
    assert_equal %w[</li>], @to.in_list_entry
  end

  def accept_list_item_end_label
    assert_equal %w[</dd>], @to.in_list_entry
  end

  def accept_list_item_end_lalpha
    assert_equal %w[</li>], @to.in_list_entry
  end

  def accept_list_item_end_note
    assert_equal %w[</td></tr>], @to.in_list_entry
  end

  def accept_list_item_end_number
    assert_equal %w[</li>], @to.in_list_entry
  end

  def accept_list_item_end_ualpha
    assert_equal %w[</li>], @to.in_list_entry
  end

  def accept_list_item_start_bullet
    assert_equal "<ul>\n<li>", @to.res.join
  end

  def accept_list_item_start_label
    assert_equal "<dl>\n<dt>cat</dt><dd>", @to.res.join
  end

  def accept_list_item_start_lalpha
    assert_equal "<ol style=\"display: lower-alpha\">\n<li>", @to.res.join
  end

  def accept_list_item_start_note
    assert_equal "<table>\n<tr><td valign=\"top\">cat</td><td>", @to.res.join
  end

  def accept_list_item_start_number
    assert_equal "<ol>\n<li>", @to.res.join
  end

  def accept_list_item_start_ualpha
    assert_equal "<ol style=\"display: upper-alpha\">\n<li>", @to.res.join
  end

  def accept_list_start_bullet
    assert_equal [:BULLET], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<ul>\n", @to.res.join
  end

  def accept_list_start_label
    assert_equal [:LABEL], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<dl>\n", @to.res.join
  end

  def accept_list_start_lalpha
    assert_equal [:LALPHA], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<ol style=\"display: lower-alpha\">\n", @to.res.join
  end

  def accept_list_start_note
    assert_equal [:NOTE], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<table>\n", @to.res.join
  end

  def accept_list_start_number
    assert_equal [:NUMBER], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<ol>\n", @to.res.join
  end

  def accept_list_start_ualpha
    assert_equal [:UALPHA], @to.list
    assert_equal [false], @to.in_list_entry

    assert_equal "<ol style=\"display: upper-alpha\">\n", @to.res.join
  end

  def accept_paragraph
    assert_equal "<p>\nhi\n</p>\n", @to.res.join
  end

  def accept_raw
    raw = <<-RAW.rstrip
<table>
<tr><th>Name<th>Count
<tr><td>a<td>1
<tr><td>b<td>2
</table>
    RAW

    assert_equal raw, @to.res.join
  end

  def accept_rule
    assert_equal '<hr style="height: 4px"></hr>', @to.res.join
  end

  def accept_verbatim
    assert_equal "<pre>\n  hi\n  world\n</pre>\n", @to.res.join
  end

  def end_accepting
    assert_equal 'hi', @to.end_accepting
  end

  def start_accepting
    assert_equal [], @to.res
    assert_equal [], @to.in_list_entry
    assert_equal [], @to.list
  end

  def test_list_verbatim
    str = "* one\n    verb1\n    verb2\n* two\n"

    expected = <<-EXPECTED
<ul>
<li><p>
one
</p>
<pre>
  verb1
  verb2
</pre>
</li>
<li><p>
two
</p>
</li>
</ul>
    EXPECTED

    assert_equal expected, @m.convert(str, @to)
  end

  def test_tt_formatting
    assert_equal "<p>\n<tt>--</tt> &#8212; <tt>cats'</tt> cats&#8217;\n</p>\n",
                 util_format("<tt>--</tt> -- <tt>cats'</tt> cats'")

    assert_equal "<p>\n<b>&#8212;</b>\n</p>\n", util_format("<b>--</b>")
  end

  def test_convert_string_fancy
    #
    # The HTML typesetting is broken in a number of ways, but I have fixed
    # the most glaring issues for single and double quotes.  Note that
    # "strange" symbols (periods or dashes) need to be at the end of the
    # test case strings in order to suppress cross-references.
    #
    assert_equal "<p>\n&#8220;cats&#8221;.\n</p>\n", util_format("\"cats\".")
    assert_equal "<p>\n&#8216;cats&#8217;.\n</p>\n", util_format("\'cats\'.")
    assert_equal "<p>\ncat&#8217;s-\n</p>\n", util_format("cat\'s-")
  end

  def util_paragraph(text)
    RDoc::Markup::Paragraph.new text
  end

  def util_format(text)
    paragraph = util_paragraph text

    @to.start_accepting
    @to.accept_paragraph paragraph
    @to.end_accepting
  end

end

