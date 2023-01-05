# frozen_string_literal: true
require_relative 'helper'

class TestRDocParserMarkdown < RDoc::TestCase

  def setup
    super

    @RP = RDoc::Parser

    @tempfile = Tempfile.new self.class.name
    filename = @tempfile.path

    @top_level = @store.add_file filename
    @fn = filename
    @options = RDoc::Options.new
    @stats = RDoc::Stats.new @store, 0
  end

  def teardown
    super

    @tempfile.close!
  end

  def test_file
    assert_kind_of RDoc::Parser::Text, util_parser('')
  end

  def test_class_can_parse
    temp_dir do
      FileUtils.touch 'foo.md'
      assert_equal @RP::Markdown, @RP.can_parse('foo.md')
      FileUtils.touch 'foo.md.ja'
      assert_equal @RP::Markdown, @RP.can_parse('foo.md.ja')

      FileUtils.touch 'foo.markdown'
      assert_equal @RP::Markdown, @RP.can_parse('foo.markdown')
      FileUtils.touch 'foo.markdown.ja'
      assert_equal @RP::Markdown, @RP.can_parse('foo.markdown.ja')
    end
  end

  def test_scan
    parser = util_parser 'it *really* works'

    expected =
      @RM::Document.new(
        @RM::Paragraph.new('it _really_ works'))
    expected.file = @top_level

    parser.scan

    assert_equal expected, @top_level.comment.parse
  end

  def util_parser content
    RDoc::Parser::Markdown.new @top_level, @fn, content, @options, @stats
  end

end
