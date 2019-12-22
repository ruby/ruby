# frozen_string_literal: true
require_relative 'helper'

class TestRDocMarkup < RDoc::TestCase

  def test_class_parse
    expected = @RM::Document.new(
      @RM::Paragraph.new('hello'))

    assert_equal expected, RDoc::Markup.parse('hello')
  end

  def test_convert
    str = <<-STR
now is
the time

  hello
  dave

1. l1
2. l2
    STR

    m = RDoc::Markup.new

    tt = RDoc::Markup::ToTest.new m

    out = m.convert str, tt

    expected = [
      "now is the time",
      "\n",
      "  hello\n  dave\n",
      "1: ",
      "l1",
      "1: ",
      "l2",
    ]

    assert_equal expected, out
  end

  def test_convert_custom_markup
    str = <<-STR
{stricken}
    STR

    m = RDoc::Markup.new
    m.add_word_pair '{', '}', :STRIKE

    tt = RDoc::Markup::ToTest.new nil, m
    tt.add_tag :STRIKE, 'STRIKE ', ' STRIKE'

    out = m.convert str, tt

    expected = [
      "STRIKE stricken STRIKE",
    ]

    assert_equal expected, out
  end

  def test_convert_document
    doc = RDoc::Markup::Parser.parse <<-STR
now is
the time

  hello
  dave

1. l1
2. l2
    STR

    m = RDoc::Markup.new

    tt = RDoc::Markup::ToTest.new m

    out = m.convert doc, tt

    expected = [
      "now is the time",
      "\n",
      "  hello\n  dave\n",
      "1: ",
      "l1",
      "1: ",
      "l2",
    ]

    assert_equal expected, out
  end

end

