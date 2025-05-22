# frozen_string_literal: true
require_relative 'helper'

class RDocMarkupToJoinedParagraphTest < RDoc::TestCase

  def setup
    super

    @to = RDoc::Markup::ToJoinedParagraph.new
  end

  def test_accept_paragraph
    parsed = para('hello', ' ', 'world')

    @to.accept_paragraph parsed

    expected = para('hello world')

    assert_equal expected, parsed
  end

  def test_accept_paragraph_break
    parsed = para('hello', ' ', 'world', hard_break, 'everyone')

    @to.accept_paragraph parsed

    expected = para('hello world', hard_break, 'everyone')

    assert_equal expected, parsed
  end

end
