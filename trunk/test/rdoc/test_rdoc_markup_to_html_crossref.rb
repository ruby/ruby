require 'test/unit'
require 'rdoc/generator'
require 'rdoc/markup/to_html_crossref'

class TestRdocMarkupToHtmlCrossref < Test::Unit::TestCase

  def setup
    @xref = RDoc::Markup::ToHtmlCrossref.new 'from_path', nil, nil
  end

  def test_handle_special_CROSSREF_no_underscore
    out = @xref.convert 'foo'

    assert_equal "<p>\nfoo\n</p>\n", out
  end

end

