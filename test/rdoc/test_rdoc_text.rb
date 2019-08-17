# frozen_string_literal: true

require_relative 'helper'
require 'timeout'

class TestRDocText < RDoc::TestCase

  include RDoc::Text

  def setup
    super

    @options = RDoc::Options.new

    @top_level = @store.add_file 'file.rb'
    @language = nil
  end

  def test_self_encode_fallback
    assert_equal '…',
                 RDoc::Text::encode_fallback('…', Encoding::UTF_8,    '...')
    assert_equal '...',
                 RDoc::Text::encode_fallback('…', Encoding::US_ASCII, '...')
  end

  def test_expand_tabs
    assert_equal("hello\n  dave",
                 expand_tabs("hello\n  dave"), 'spaces')

    assert_equal("hello\n        dave",
                 expand_tabs("hello\n\tdave"), 'tab')

    assert_equal("hello\n        dave",
                 expand_tabs("hello\n \tdave"), '1 space tab')

    assert_equal("hello\n        dave",
                 expand_tabs("hello\n  \tdave"), '2 space tab')

    assert_equal("hello\n        dave",
                 expand_tabs("hello\n   \tdave"), '3 space tab')

    assert_equal("hello\n        dave",
                 expand_tabs("hello\n    \tdave"), '4 space tab')

    assert_equal("hello\n        dave",
                 expand_tabs("hello\n     \tdave"), '5 space tab')

    assert_equal("hello\n        dave",
                 expand_tabs("hello\n      \tdave"), '6 space tab')

    assert_equal("hello\n        dave",
                 expand_tabs("hello\n       \tdave"), '7 space tab')

    assert_equal("hello\n                dave",
                 expand_tabs("hello\n         \tdave"), '8 space tab')

    assert_equal('.               .',
                 expand_tabs(".\t\t."), 'dot tab tab dot')

    assert_equal('a       a',
                 Timeout.timeout(1) {expand_tabs("\ra\ta")}, "carriage return")
  end

  def test_expand_tabs_encoding
    inn = "hello\ns\tdave"
    inn = RDoc::Encoding.change_encoding inn, Encoding::BINARY

    out = expand_tabs inn

    assert_equal "hello\ns       dave", out
    assert_equal Encoding::BINARY, out.encoding
  end

  def test_flush_left
    text = <<-TEXT

  we don't worry too much.

  The comments associated with
    TEXT

    expected = <<-EXPECTED

we don't worry too much.

The comments associated with
    EXPECTED

    assert_equal expected, flush_left(text)
  end

  def test_flush_left_encoding
    text = <<-TEXT

  we don't worry too much.

  The comments associated with
    TEXT

    text = RDoc::Encoding.change_encoding text, Encoding::US_ASCII

    expected = <<-EXPECTED

we don't worry too much.

The comments associated with
    EXPECTED

    result = flush_left text

    assert_equal expected, result
    assert_equal Encoding::US_ASCII, result.encoding
  end

  def test_markup_string
    out = markup('hi').gsub("\n", '')

    assert_equal '<p>hi</p>', out
  end

  def test_markup_comment
    out = markup(comment('hi')).gsub("\n", '')

    assert_equal '<p>hi</p>', out
  end

  def test_normalize_comment_hash
    text = <<-TEXT
##
# we don't worry too much.
#
# The comments associated with
    TEXT

    expected = <<-EXPECTED.rstrip
we don't worry too much.

The comments associated with
    EXPECTED

    @language = :ruby

    assert_equal expected, normalize_comment(text)
  end

  def test_normalize_comment_stars_single_space
    text = <<-TEXT
/*
 * we don't worry too much.
 *
 * The comments associated with
 */
    TEXT

    expected = <<-EXPECTED.rstrip
we don't worry too much.

The comments associated with
    EXPECTED

    @language = :c

    assert_equal expected, normalize_comment(text)
  end

  def test_normalize_comment_stars_single_double_space
    text = <<-TEXT
/*
 *  we don't worry too much.
 *
 *  The comments associated with
 */
    TEXT

    expected = <<-EXPECTED.rstrip
we don't worry too much.

The comments associated with
    EXPECTED

    @language = :c

    assert_equal expected, normalize_comment(text)
  end

  def test_parse
    assert_kind_of RDoc::Markup::Document, parse('hi')
  end

  def test_parse_comment
    expected = RDoc::Markup::Document.new
    expected.file = @top_level

    c = comment ''
    parsed = parse c

    assert_equal expected, parsed
    assert_same parsed, parse(c)
  end

  def test_parse_document
    assert_equal RDoc::Markup::Document.new, parse(RDoc::Markup::Document.new)
  end

  def test_parse_empty
    assert_equal RDoc::Markup::Document.new, parse('')
  end

  def test_parse_empty_newline
    @language = :ruby

    assert_equal RDoc::Markup::Document.new, parse("#\n")
  end

  def test_parse_format_markdown
    expected =
      @RM::Document.new(
        @RM::Paragraph.new('it _works_'))

    parsed = parse 'it *works*', 'markdown'

    assert_equal expected, parsed
  end

  def test_parse_format_rd
    expected =
      @RM::Document.new(
        @RM::Paragraph.new('it <em>works</em>'))

    parsed = parse 'it ((*works*))', 'rd'

    assert_equal expected, parsed
  end

  def test_parse_format_tomdoc
    code = verb('1 + 1')
    code.format = :ruby

    expected =
      doc(
        para('It does a thing'),
        blank_line,
        head(3, 'Examples'),
        blank_line,
        code)

    text = <<-TOMDOC
It does a thing

Examples

  1 + 1
    TOMDOC

    parsed = parse text, 'tomdoc'

    assert_equal expected, parsed
  end

  def test_parse_newline
    assert_equal RDoc::Markup::Document.new, parse("\n")
  end

  def test_snippet
    text = <<-TEXT
This is one-hundred characters or more of text in a single paragraph.  This
paragraph will be cut off some point after the one-hundredth character.
    TEXT

    expected = <<-EXPECTED
<p>This is one-hundred characters or more of text in a single paragraph.  This paragraph will be cut off …
    EXPECTED

    assert_equal expected, snippet(text)
  end

  def test_snippet_comment
    c = comment 'This is a comment'

    assert_equal "<p>This is a comment\n", snippet(c)
  end

  def test_snippet_short
    text = 'This is a comment'

    assert_equal "<p>#{text}\n", snippet(text)
  end

  def test_strip_hashes
    text = <<-TEXT
##
# we don't worry too much.
#
# The comments associated with
    TEXT

    expected = <<-EXPECTED

  we don't worry too much.

  The comments associated with
    EXPECTED

    assert_equal expected, strip_hashes(text)
  end

  def test_strip_hashes_encoding
    text = <<-TEXT
##
# we don't worry too much.
#
# The comments associated with
    TEXT

    text = RDoc::Encoding.change_encoding text, Encoding::CP852

    expected = <<-EXPECTED

  we don't worry too much.

  The comments associated with
    EXPECTED

    stripped = strip_hashes text

    assert_equal expected, stripped
    assert_equal Encoding::CP852, stripped.encoding
  end

  def test_strip_newlines
    assert_equal ' ',  strip_newlines("\n \n")

    assert_equal 'hi', strip_newlines("\n\nhi")

    assert_equal 'hi', strip_newlines(    "hi\n\n")

    assert_equal 'hi', strip_newlines("\n\nhi\n\n")
  end

  def test_strip_newlines_encoding
    assert_equal Encoding::UTF_8, ''.encoding, 'Encoding sanity check'

    text = " \n"
    text = RDoc::Encoding.change_encoding text, Encoding::US_ASCII

    stripped = strip_newlines text

    assert_equal ' ', stripped

    assert_equal Encoding::US_ASCII, stripped.encoding
  end

  def test_strip_stars
    text = <<-TEXT
/*
 * * we don't worry too much.
 *
 * The comments associated with
 */
    TEXT

    expected = <<-EXPECTED

   * we don't worry too much.

   The comments associated with
    EXPECTED

    assert_equal expected, strip_stars(text)
  end

  def test_strip_stars_document_method
    text = <<-TEXT
/*
 * Document-method: Zlib::GzipFile#mtime=
 *
 * A comment
 */
    TEXT

    expected = <<-EXPECTED

   A comment
    EXPECTED

    assert_equal expected, strip_stars(text)
  end

  def test_strip_stars_document_method_special
    text = <<-TEXT
/*
 * Document-method: Zlib::GzipFile#mtime=
 * Document-method: []
 * Document-method: `
 * Document-method: |
 * Document-method: &
 * Document-method: <=>
 * Document-method: =~
 * Document-method: +
 * Document-method: -
 * Document-method: +@
 *
 * A comment
 */
    TEXT

    expected = <<-EXPECTED

   A comment
    EXPECTED

    assert_equal expected, strip_stars(text)
  end

  def test_strip_stars_encoding
    text = <<-TEXT
/*
 * * we don't worry too much.
 *
 * The comments associated with
 */
    TEXT

    text = RDoc::Encoding.change_encoding text, Encoding::CP852

    expected = <<-EXPECTED

   * we don't worry too much.

   The comments associated with
    EXPECTED

    result = strip_stars text

    assert_equal expected, result
    assert_equal Encoding::CP852, result.encoding
  end

  def test_strip_stars_encoding2
    text = <<-TEXT
/*
 * * we don't worry too much.
 *
 * The comments associated with
 */
    TEXT

    text = RDoc::Encoding.change_encoding text, Encoding::BINARY

    expected = <<-EXPECTED

   * we don't worry too much.

   The comments associated with
    EXPECTED

    result = strip_stars text

    assert_equal expected, result
    assert_equal Encoding::BINARY, result.encoding
  end

  def test_strip_stars_no_stars
    text = <<-TEXT
* we don't worry too much.

The comments associated with

    TEXT

    expected = <<-EXPECTED
* we don't worry too much.

The comments associated with

    EXPECTED

    assert_equal expected, strip_stars(text)
  end

  def test_to_html_apostrophe
    assert_equal '‘a', to_html("'a")
    assert_equal 'a’', to_html("a'")

    assert_equal '‘a’ ‘', to_html("'a' '")
  end

  def test_to_html_backslash
    assert_equal 'S', to_html('\\S')
  end

  def test_to_html_br
    assert_equal '<br>', to_html('<br>')
  end

  def test_to_html_copyright
    assert_equal '©', to_html('(c)')
  end

  def test_to_html_dash
    assert_equal '-',  to_html('-')
    assert_equal '–',  to_html('--')
    assert_equal '—',  to_html('---')
    assert_equal '—-', to_html('----')
  end

  def test_to_html_double_backtick
    assert_equal '“a',  to_html('``a')
    assert_equal '“a“', to_html('``a``')
  end

  def test_to_html_double_quote
    assert_equal '“a',  to_html('"a')
    assert_equal '“a”', to_html('"a"')
  end

  def test_to_html_double_quote_quot
    assert_equal '“a',  to_html('&quot;a')
    assert_equal '“a”', to_html('&quot;a&quot;')
  end

  def test_to_html_double_tick
    assert_equal '”a',        to_html("''a")
    assert_equal '”a”', to_html("''a''")
  end

  def test_to_html_ellipsis
    assert_equal '..', to_html('..')
    assert_equal '…',  to_html('...')
    assert_equal '.…', to_html('....')
  end

  def test_to_html_encoding
    s = '...(c)'.encode Encoding::Shift_JIS

    html = to_html s

    assert_equal Encoding::Shift_JIS, html.encoding

    expected = '…(c)'.encode Encoding::Shift_JIS

    assert_equal expected, html
  end

  def test_to_html_html_tag
    assert_equal '<a href="http://example">hi’s</a>',
                 to_html('<a href="http://example">hi\'s</a>')
  end

  def test_to_html_registered_trademark
    assert_equal '®', to_html('(r)')
  end

  def test_to_html_tt_tag
    assert_equal '<tt>hi\'s</tt>',   to_html('<tt>hi\'s</tt>')
    assert_equal '<tt>hi\\\'s</tt>', to_html('<tt>hi\\\\\'s</tt>')
  end

  def test_to_html_tt_tag_mismatch
    _, err = verbose_capture_output do
      assert_equal '<tt>hi', to_html('<tt>hi')
    end

    assert_equal "mismatched <tt> tag\n", err
  end

  def formatter
    RDoc::Markup::ToHtml.new @options
  end

  def options
    @options
  end

end
