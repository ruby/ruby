require 'tempfile'
require 'rubygems'
require 'minitest/autorun'
require 'rdoc/options'
require 'rdoc/parser'

class TestRDocParserSimple < MiniTest::Unit::TestCase

  def setup
    @tempfile = Tempfile.new self.class.name
    filename = @tempfile.path

    @top_level = RDoc::TopLevel.new filename
    @fn = filename
    @options = RDoc::Options.new
    @stats = RDoc::Stats.new 0

    RDoc::TopLevel.reset
  end

  def teardown
    @tempfile.close
  end

  def test_initialize_metadata
    parser = util_parser ":unhandled: \n# :markup: not rdoc\n"

    assert_equal nil,        @top_level.metadata['unhandled']
    assert_equal 'not rdoc', @top_level.metadata['markup']

    assert_equal ":unhandled: \n# :markup: not rdoc\n", parser.content
  end

  def test_remove_coding_comment
    parser = util_parser <<-TEXT
# -*- mode: rdoc; coding: utf-8; fill-column: 74; -*-

Regular expressions (<i>regexp</i>s) are patterns which describe the
contents of a string.
    TEXT

    parser.scan

    expected = <<-TEXT.strip

Regular expressions (<i>regexp</i>s) are patterns which describe the
contents of a string.
    TEXT

    assert_equal expected, @top_level.comment
  end

  def test_remove_private_comments
    parser = util_parser ''
    text = "foo\n\n--\nbar\n++\n\nbaz\n"

    expected = "foo\n\n\n\nbaz\n"

    assert_equal expected, parser.remove_private_comments(text)
  end

  def test_remove_private_comments_star
    parser = util_parser ''

    text = "* foo\n* bar\n"
    expected = text.dup

    assert_equal expected, parser.remove_private_comments(text)
  end

  def util_parser(content)
    RDoc::Parser::Simple.new @top_level, @fn, content, @options, @stats
  end

end

