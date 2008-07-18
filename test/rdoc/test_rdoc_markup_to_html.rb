require 'test/unit'
require 'rdoc/markup'
require 'rdoc/markup/to_html'

class TestRdocMarkupToHtml < Test::Unit::TestCase

  def setup
    @am = RDoc::Markup::AttributeManager.new
    @th = RDoc::Markup::ToHtml.new
  end

  def test_tt_formatting
    assert_equal "<p>\n<tt>--</tt> &#8212; <tt>(c)</tt> &#169;\n</p>\n",
                 util_format("<tt>--</tt> -- <tt>(c)</tt> (c)")
    assert_equal "<p>\n<b>&#8212;</b>\n</p>\n", util_format("<b>--</b>")
  end

  def util_fragment(text)
    RDoc::Markup::Fragment.new 0, nil, nil, text
  end

  def util_format(text)
    fragment = util_fragment text

    @th.start_accepting
    @th.accept_paragraph @am, fragment
    @th.end_accepting
  end

end
