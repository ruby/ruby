# frozen_string_literal: true
require 'minitest_helper'

class TestRDocMarkupToMarkdown < RDoc::Markup::TextFormatterTestCase

  add_visitor_tests
  add_text_tests

  def setup
    super

    @to = RDoc::Markup::ToMarkdown.new
  end

  def accept_blank_line
    assert_equal "\n", @to.res.join
  end

  def accept_block_quote
    assert_equal "> quote\n", @to.res.join
  end

  def accept_document
    assert_equal "hello\n", @to.res.join
  end

  def accept_heading
    assert_equal "##### Hello\n", @to.res.join
  end

  def accept_list_end_bullet
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_end_label
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_end_lalpha
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_end_note
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_end_number
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_end_ualpha
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_list_item_end_bullet
    assert_equal 0, @to.indent, 'indent'
  end

  def accept_list_item_end_label
    assert_equal "cat\n:   ", @to.res.join
    assert_equal 0, @to.indent, 'indent'
  end

  def accept_list_item_end_lalpha
    assert_equal 0, @to.indent, 'indent'
    assert_equal 2, @to.list_index.last
  end

  def accept_list_item_end_note
    assert_equal "cat\n:   ", @to.res.join
    assert_equal 0, @to.indent, 'indent'
  end

  def accept_list_item_end_number
    assert_equal 0, @to.indent, 'indent'
    assert_equal 2, @to.list_index.last
  end

  def accept_list_item_end_ualpha
    assert_equal 0, @to.indent, 'indent'
    assert_equal 2, @to.list_index.last
  end

  def accept_list_item_start_bullet
    assert_equal [""], @to.res
    assert_equal '*   ', @to.prefix
  end

  def accept_list_item_start_label
    assert_equal [""], @to.res
    assert_equal "cat\n:   ", @to.prefix

    assert_equal 4, @to.indent
  end

  def accept_list_item_start_lalpha
    assert_equal [""], @to.res
    assert_equal '1.  ', @to.prefix

    assert_equal 1, @to.list_index.last
    assert_equal 4, @to.indent
  end

  def accept_list_item_start_note
    assert_equal [""], @to.res
    assert_equal "cat\n:   ", @to.prefix

    assert_equal 4, @to.indent
  end

  def accept_list_item_start_number
    assert_equal [""], @to.res
    assert_equal '1.  ', @to.prefix

    assert_equal 1, @to.list_index.last
    assert_equal 4, @to.indent
  end

  def accept_list_item_start_ualpha
    assert_equal [""], @to.res
    assert_equal '1.  ', @to.prefix

    assert_equal 1, @to.list_index.last
    assert_equal 4, @to.indent
  end

  def accept_list_start_bullet
    assert_equal "",   @to.res.join
    assert_equal [nil],     @to.list_index
    assert_equal [:BULLET], @to.list_type
    assert_equal [4],       @to.list_width
  end

  def accept_list_start_label
    assert_equal "",  @to.res.join
    assert_equal [nil],    @to.list_index
    assert_equal [:LABEL], @to.list_type
    assert_equal [4],      @to.list_width
  end

  def accept_list_start_lalpha
    assert_equal "",   @to.res.join
    assert_equal [1],     @to.list_index
    assert_equal [:LALPHA], @to.list_type
    assert_equal [4],       @to.list_width
  end

  def accept_list_start_note
    assert_equal "", @to.res.join
    assert_equal [nil],   @to.list_index
    assert_equal [:NOTE], @to.list_type
    assert_equal [4],     @to.list_width
  end

  def accept_list_start_number
    assert_equal "",   @to.res.join
    assert_equal [1],       @to.list_index
    assert_equal [:NUMBER], @to.list_type
    assert_equal [4],       @to.list_width
  end

  def accept_list_start_ualpha
    assert_equal "",   @to.res.join
    assert_equal [1],     @to.list_index
    assert_equal [:UALPHA], @to.list_type
    assert_equal [4],       @to.list_width
  end

  def accept_paragraph
    assert_equal "hi\n", @to.res.join
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
    assert_equal "---\n", @to.res.join
  end

  def accept_verbatim
    assert_equal "    hi\n      world\n\n", @to.res.join
  end

  def end_accepting
    assert_equal "hi", @to.end_accepting
  end

  def start_accepting
    assert_equal 0, @to.indent
    assert_equal [""], @to.res
    assert_empty @to.list_index
    assert_empty @to.list_type
    assert_empty @to.list_width
  end

  def accept_heading_1
    assert_equal "# Hello\n", @to.end_accepting
  end

  def accept_heading_2
    assert_equal "## Hello\n", @to.end_accepting
  end

  def accept_heading_3
    assert_equal "### Hello\n", @to.end_accepting
  end

  def accept_heading_4
    assert_equal "#### Hello\n", @to.end_accepting
  end

  def accept_heading_indent
    assert_equal "   # Hello\n", @to.end_accepting
  end

  def accept_heading_b
    assert_equal "# **Hello**\n", @to.end_accepting
  end

  def accept_heading_suppressed_crossref
    assert_equal "# Hello\n", @to.end_accepting
  end

  def accept_list_item_start_note_2
    assert_equal "`teletype`\n:   teletype description\n\n", @to.res.join
  end

  def accept_list_item_start_note_multi_description
    assert_equal "label\n:   description one\n\n:   description two\n\n",
                 @to.res.join
  end

  def accept_list_item_start_note_multi_label
    assert_equal "one\ntwo\n:   two headers\n\n", @to.res.join
  end

  def accept_paragraph_b
    assert_equal "reg **bold words** reg\n", @to.end_accepting
  end

  def accept_paragraph_br
    assert_equal "one  \ntwo\n", @to.end_accepting
  end

  def accept_paragraph_break
    assert_equal "hello  \nworld\n", @to.end_accepting
  end

  def accept_paragraph_i
    assert_equal "reg *italic words* reg\n", @to.end_accepting
  end

  def accept_paragraph_indent
    expected = <<-EXPECTED
   words words words words words words words words words words words words
   words words words words words words words words words words words words
   words words words words words words
    EXPECTED

    assert_equal expected, @to.end_accepting
  end

  def accept_paragraph_plus
    assert_equal "reg `teletype` reg\n", @to.end_accepting
  end

  def accept_paragraph_star
    assert_equal "reg **bold** reg\n", @to.end_accepting
  end

  def accept_paragraph_underscore
    assert_equal "reg *italic* reg\n", @to.end_accepting
  end

  def accept_paragraph_wrap
    expected = <<-EXPECTED
words words words words words words words words words words words words words
words words words words words words words words words words words words words
words words words words
    EXPECTED

    assert_equal expected, @to.end_accepting
  end

  def accept_rule_indent
    assert_equal "   ---\n", @to.end_accepting
  end

  def accept_verbatim_indent
    assert_equal "      hi\n       world\n\n", @to.end_accepting
  end

  def accept_verbatim_big_indent
    assert_equal "      hi\n      world\n\n", @to.end_accepting
  end

  def list_nested
    expected = <<-EXPECTED
*   l1
    *   l1.1

*   l2

    EXPECTED

    assert_equal expected, @to.end_accepting
  end

  def list_verbatim
    expected = <<-EXPECTED # HACK overblown
*   list stuff

        * list
          with

          second

          1. indented
          2. numbered

          third

        * second


    EXPECTED

    assert_equal expected, @to.end_accepting
  end

  def test_convert_RDOCLINK
    result = @to.convert 'rdoc-garbage:C'

    assert_equal "C\n", result
  end

  def test_convert_RDOCLINK_image
    result = @to.convert 'rdoc-image:/path/to/image.jpg'

    assert_equal "![](/path/to/image.jpg)\n", result
  end

  def test_convert_TIDYLINK
    result = @to.convert \
      '{DSL}[http://en.wikipedia.org/wiki/Domain-specific_language]'

    expected = "[DSL](http://en.wikipedia.org/wiki/Domain-specific_language)\n"

    assert_equal expected, result
  end

  def test_handle_rdoc_link_label_footmark
    assert_equal '[^1]:', @to.handle_rdoc_link('rdoc-label:footmark-1:x')
  end

  def test_handle_rdoc_link_label_foottext
    assert_equal '[^1]',   @to.handle_rdoc_link('rdoc-label:foottext-1:x')
  end

  def test_handle_rdoc_link_label_label
    assert_equal '[x](#label-x)', @to.handle_rdoc_link('rdoc-label:label-x')
  end

  def test_handle_rdoc_link_ref
    assert_equal 'x', @to.handle_rdoc_link('rdoc-ref:x')
  end

end

